# Case Study 01: Migrating a Flat Network to 11 VLANs Without Losing Services

**Period:** May–June 2026
**Scope:** OPNsense firewall, MikroTik CRS309/CRS326 switches, Proxmox VE hypervisor, six virtual machines

## Summary

The lab began as a mostly flat network: the hypervisor, its management controller, and nearly every VM shared one user subnet (192.168.30.0/24). I redesigned it into 11 VLANs grouped by trust level and migrated every VM, the hypervisor, and its out-of-band controller one at a time while the services stayed in use. The migration surfaced six distinct failure modes. Each was diagnosed and resolved, and each became a standing rule in the lab's runbooks.

## Motivation

On a flat network, any compromised device, such as a smart plug or a guest phone, could reach the NAS, the hypervisor's management interface, and its BMC directly. The goal was to make every cross-segment flow pass through the firewall, where it is explicitly allowed or denied.

## Design

**Segmentation.** Workloads were grouped by trust and function: management (1), DMZ (10), IoT (20), users (30), guest (40), cameras (50), containers (60), media (70), storage (80), automation (90), and VPN egress (110).

**A constraint found during planning.** The ISP cable modem answers on a hardcoded 192.168.100.1, which made 192.168.100.0/24 unusable internally. The VPN egress VLAN was renumbered to 110 to avoid an address collision with the modem.

**Execution order.** The order was fixed before any change was made:

1. Finalize every VM's VLAN and IP on paper.
2. Build the OPNsense interfaces and firewall rules for each VLAN.
3. Tag the VLANs on the MikroTik trunks.
4. Move the hypervisor and its BMC to the management VLAN.
5. Migrate VMs one at a time, lowest risk first.

**Guiding rule.** Never remove the old configuration until the new one is confirmed working.

## Building the data path

The hypervisor (Gaia) originally carried all VM traffic over a single onboard copper NIC. I built a dedicated path instead: a 2×10G LACP bond over an Intel X520 fiber card to the CRS309 core switch, with a VLAN-aware Linux bridge (`vmbr2`) on top. Each VM's virtual NIC then needs only a VLAN tag; the hypervisor needs no per-VLAN sub-interfaces.

Passing the X520 through was the first obstacle. It shared an IOMMU group with the storage HBA, which blocked clean assignment. The PCIe ACS override (`pcie_acs_override=downstream,multifunction`) split the groups. I confirmed beforehand that the iGPU used for media transcoding sat in its own group and would not be affected.

## Failure modes encountered

### 1. The hypervisor firewall silently broke routing

- **Observation:** Enabling VLAN awareness on the original bridge broke routing for every VM at once.
- **Cause:** With Proxmox's per-VM firewall enabled, Proxmox inserts an intermediate firewall bridge for each tagged NIC. In this setup those interfered with forwarding.
- **Resolution:** I disabled the per-VM firewall on all VMs. OPNsense is the single point of policy enforcement, so a second firewall layer added failure modes without adding protection.

### 2. A VLAN defined on the switch but not carried on the port

- **Observation:** After the first VM moved to VLAN 80 on the new bridge, it could not reach its gateway.
- **Hypothesis:** The VLAN existed in the switch's bridge VLAN table but was not tagged on the bond facing the hypervisor.
- **Confirmation and fix:** The bond had never been added as a bridge port, and VLAN 80 was not tagged on it. I added the port, then extended the existing VLAN entry with `set` instead of `add`, because `add` would have created a conflicting duplicate entry.

### 3. The network tool failed on a dependency the system never used

- **Observation:** `netplan apply` failed, reporting that the Open vSwitch database service was not running, on a VM that used no Open vSwitch at all.
- **Cause:** The installed netplan version probed for Open vSwitch regardless of which renderer was configured.
- **Resolution:** I ran `netplan generate` and then restarted `systemd-networkd` directly, which bypasses the probe.

### 4. Configuration changes that would not persist

- **Observation:** The Ubuntu VMs used cloud-init, which regenerates the network configuration on every boot.
- **Resolution:** Before every netplan edit, I disabled cloud-init's network management (`99-disable-network-config.cfg`) so the new configuration would persist.

### 5. A VM attached to the wrong bridge

- **Observation:** One VM had no connectivity after its migration, even though its VLAN tag, IP address, and firewall rules were all correct.
- **Cause:** Its virtual NIC was attached to the legacy copper bridge rather than `vmbr2`. That bridge reaches the edge switch, not the core switch where the VLAN was trunked.
- **Resolution:** I moved the NIC to `vmbr2` and adopted a permanent rule: every VM uses `vmbr2` plus a VLAN tag, never the legacy bridge.

### 6. The management controller ignored its own port

- **Observation:** After the hypervisor's management bond moved to VLAN 1, the BMC stayed unreachable.
- **Cause:** The BMC's switch port had its own PVID, separate from the management bond's, and the BMC also needed its gateway's MAC address set explicitly.
- **Resolution:** I changed the PVID on the BMC's port and set the gateway MAC with `ipmitool`. After that, the BMC came up on the management VLAN.

## Cutover procedure

The same procedure was used for each VM:

1. Disable cloud-init network management.
2. Stage the new netplan file without applying it.
3. Change the virtual NIC to `vmbr2` with the target VLAN tag. SSH drops at this point.
4. Apply the network configuration from the hypervisor's console.
5. Verify the address, gateway reachability, DNS, and every dependent mount or service.
6. Update NFS export ACLs and firewall rules that referenced the old address.

Staging the configuration before changing the bridge kept each VM's console-only recovery window short.

## Firewall cleanup

The migration was also used to audit the firewall rules. Rules with raw IP addresses were rewritten to use named aliases. Rules nobody could account for were disabled. One egress rule turned out to have its source and destination inverted, and was corrected. Each VLAN now follows the same pattern: explicit allows, then internet egress restricted to the ports it needs, then a block on all other private ranges.

## Results

- All six VMs were migrated to their target VLANs on the 10G bonded path, along with the hypervisor and its BMC.
- No data was lost, and every service was restored at its new address.
- Every cross-VLAN flow now crosses an explicit, alias-based firewall rule.

## Limitations

- **Downtime was not instrumented.** I didn't record per-VM outage durations, so this report can't quantify service interruption. For future changes, I'll run a timestamped reachability probe (`ping -D`, or a scripted HTTP check) through each cutover.
- **Throughput was not fully characterized.** An iperf3 test between the media server and the NAS across VLANs reached about 2.2 Gbit/s aggregate over four streams, with several thousand TCP retransmits. That result will be investigated in a separate benchmark write-up.

## Lessons

1. Verify each layer in order: switch port tagging, then the bridge, then the guest OS, then the firewall. Most failures here were at a layer below where the symptom appeared.
2. Enforce policy in one place. Duplicate firewall layers add failure modes.
3. Stage the new configuration before cutting over, and keep a console path for recovery.
4. Turn every failure into a written rule. The wrong-bridge error never recurred once it was written down.
5. Measure the things you'll want to report later. The missing downtime data is the clearest gap in this write-up.
