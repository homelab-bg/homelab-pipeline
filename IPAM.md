# IP address management

How static IP addresses are allocated across the LAN, tracked in [NetBox](https://netboxlabs.com)
(self-hosted at `ipam.lan.example.com`, see [`ansible-pve-netbox`](ansible-pve-netbox/)) - same
relationship this project's [`SECRETS.md`](SECRETS.md) has to Infisical: NetBox is the source of truth,
this file documents the allocation policy, the SOP for claiming a new address, and a manually-kept
snapshot for human reference.

**NetBox is not yet populated.** It was stood up in this session but holds no IP/prefix data yet - the
real inventory below was reconstructed from each module's own `tfvars`/`hosts.yml`/DNS records.
Backfilling NetBox with this inventory is a separate, not-yet-done follow-up (see the bottom of this
file); until that's done, this file's inventory table is the de facto source of truth, not NetBox itself.

## VLANs

| VLAN | Subnet | Gateway | DNS | DHCP pool | Status |
|---|---|---|---|---|---|
| default | `172.16.0.0/24` | `172.16.0.1` | `172.16.0.2`-`.4` | `172.16.0.101`-`.199` | in use - everything this pipeline manages lives here |
| management | `172.16.1.0/24` | `172.16.1.1` | `172.16.0.2`-`.4` (cross-VLAN) | `172.16.1.101`-`.199` | defined, not used yet |
| IoT | `172.16.2.0/24` | `172.16.2.1` | `172.16.0.2`-`.4` (cross-VLAN) | `172.16.2.101`-`.199` | out of scope for this pipeline |
| Guest | `172.16.199.0/24` | `172.16.199.1` | `172.16.199.1` (self-contained, no cross-VLAN DNS) | `172.16.199.101`-`.199` | out of scope for this pipeline |

Only the **default** VLAN is this pipeline's concern today. **management** is reserved for later (e.g. a
future OOB/control-plane separation) but nothing here provisions into it yet. IoT/Guest are consumer-network
concerns managed elsewhere, listed here only so their ranges are never mistaken for available space.

## Addressing scheme (default VLAN, `172.16.0.0/24`)

`.101`-`.199` is the router's DHCP pool - **not available for new static allocation**. Everything below
assumes static allocations stay in `.2`-`.99` or `.200`-`.254`.

| Range | Purpose | Notes |
|---|---|---|
| `.1` | Gateway | |
| `.2`-`.9` | Core network services | Technitium `ns1`-`ns3` currently `.2`-`.4` |
| `.10`-`.19` | Core shared platform/storage services | TrueNAS/MinIO `.10`; `secrets` LXC `.15`; `netbox` LXC `.17` |
| `.20`-`.30` | Reserved / available | |
| `.31`-`.39` | **Kubernetes control-plane nodes** | `.31`-`.32` in use (`.33` next); remainder held for expansion room, not a fixed target node count |
| `.40` | `docker-green` (`docker1`) | moved from `.41` to make room for k8s workers below |
| `.41`-`.49` | **Kubernetes worker nodes** | reserved, not yet provisioned; `.41`-`.43` for the initial 3, remainder held for expansion |
| `.50` | Reserved / available | |
| `.51`-`.59` | **MetalLB LoadBalancer pool** | reserved, not yet provisioned - deliberately separate from node IPs; L2 mode needs a block never handed to a node or by DHCP, but still on-segment |
| `.60`-`.99` | Reserved / available | |
| `.101`-`.199` | **DHCP pool** | router-assigned, not for static allocation - see the flagged overlap below |
| `.200`-`.209` | Proxmox hypervisor hosts | `pve1`-`pve3` = `.201`-`.203` |
| `.210`-`.240` | Reserved / available | |
| `.241`-`.249` | Out-of-band management (AMT/iLO/etc.) | `pve1-amt`-`pve3-amt` = `.241`-`.243` |
| `.250`-`.254` | Ephemeral / smoketest | precedent: `tf-pve-talos-smoketest` used `.250`, torn down, now free again |
| `.255` | Broadcast | |

**Flagged - not confirmed safe:** three existing static hosts sit *inside* the `.101`-`.199` DHCP pool -
`jump` (`.111`), `packer-builder` (`.112`), and the GH Actions runner (`.184`). Whether the DHCP server
has static reservations/exclusions carved out for these wasn't confirmed while writing this file. Until
checked, treat this as a real conflict risk, not settled history - if the DHCP server ever hands one of
these addresses to another device, the corresponding static host becomes unreachable or double-assigned.

## NetBox structure

**One IPAM instance for the whole pipeline**, not one per module - matches Infisical's single-project
reasoning in `SECRETS.md`: one operator, one homelab, no isolation boundary that would justify the
overhead of more than one.

**One aggregate + one prefix per VLAN** (starting with `172.16.0.0/24`), with individual IP address
objects underneath for each allocated host - not a prefix per range band. The range table above is
documentation/policy, not a structure NetBox itself needs to enforce.

**`vmid`-matches-last-octet convention** (established with `tf-pve-netbox`, e.g. NetBox itself is `vmid
117` at `.17`): where a static IP is assigned to a new Proxmox VM/LXC, match its Proxmox `vmid` to the
IP's last octet where practical. Not retrofitted onto pre-existing hosts that don't already follow it.

**Description convention** for each IP address object: `<hostname> - <module/consumer>`, e.g. `netbox -
tf-pve-netbox`, so the reverse lookup from NetBox back to the owning module/repo doesn't require guessing.

## Two allocation paths: bootstrap infra vs. everything else

**"Bootstrap infra"** - NetBox itself, Infisical (`secrets`), the Technitium DNS servers, the Proxmox
hosts, and anything else needed just to *reach* NetBox in the first place - can't rely on NetBox for its
own address allocation; it either predates NetBox or has to exist before NetBox is reachable. These get
entered into NetBox as a one-time backfill/hydration pass after the fact, the same way
`tf-dns-technitium/records.tf`'s baseline records were hydrated from the retired Unbound config rather
than allocated through Technitium itself. This is a permanent characteristic of bootstrap infra, not a
gap to eventually close.

**Everything else** (workload modules - `docker-green` today, the upcoming k8s module, future
general-purpose VMs/LXCs) is meant to move to **programmatic allocation**: the module's own Terraform
claims its IP from NetBox at `apply` time (via the NetBox Terraform provider against the
`tf-pve-netbox-ipam` credential - see `SECRETS.md`), instead of a human picking a free address from this
file by hand. This isn't built anywhere yet - the SOP below is the current (manual) process, used until a
given module gets its own "IPAM section" added. Cycling back to retrofit existing modules with this is
tracked as a follow-up, not done as part of writing this file.

## SOP: allocating a new static IP (current, manual process)

1. **Pick a free address** in the appropriate range band above (check NetBox once it's populated; until
   then, check the inventory table below and each module's own `tfvars`/`hosts.yml` directly, since this
   table can go stale between updates). Never from `.101`-`.199` (DHCP pool).
2. **Create the IP address object in NetBox** (web UI, or the `tf-pve-netbox-ipam` Terraform module once
   built) - status `active`, description per the convention above.
3. **Set the static IP in the provisioning module** - Terraform's `initialization.ip_config.ipv4.address`
   for a `proxmox_virtual_environment_container`/`_vm` resource, or the equivalent NoCloud/cloud-init
   mechanism for anything not using that resource directly.
4. **Add the DNS A record** via `tf-dns-technitium` (for baseline infra) or the module's own `dns.tf`
   (for anything provisioned by its own `tf-pve-*` module - see `tf-pve-netbox/dns.tf` for the pattern).
5. **Add an SSH config entry** (`~/.ssh/config`) if direct/root SSH access is needed, matching the
   existing per-host block style.
6. **Update this file's inventory table** below - NetBox is authoritative once populated, but the table
   here is kept as a human-readable snapshot, same as `SECRETS.md`'s inventory table is for Infisical.
7. If the new host also needs secrets, follow `SECRETS.md`'s own SOP for that half separately - the two
   are independent (an IP allocation doesn't imply a secrets folder, and vice versa).

## Current inventory (default VLAN unless noted)

| IP | Hostname | Purpose | Provisioned by |
|---|---|---|---|
| `.1` | (gateway) | Router | out of band |
| `.2` / `.3` / `.4` | `ns1` / `ns2` / `ns3` | Technitium DNS (HA cluster) | out of band (LXC/host itself); DNS records via `tf-dns-technitium` |
| `.10` | `truenas-bne1` / `minio` / `minio-console` | TrueNAS + MinIO (Terraform state backend) | out of band; DNS records via `tf-dns-technitium` |
| `.15` | `secrets` | Infisical (self-hosted secrets manager) | community-scripts (`ct/docker.sh`), no matching `tf-pve-*` module yet - see README's `tf-pve-netbox` section |
| `.17` | `netbox` | NetBox (this file's own IPAM instance) | `tf-pve-netbox` + `ansible-pve-netbox` |
| `.40` | `docker-green` (`docker1`) | Playground-tier Docker host (Traefik/Portainer) | `tf-pve-docker-green` + `ansible-pve-docker-green` - moved from `.41` on 2026-08-25 to free `.41`-`.43` for k8s workers |
| `.111` | `jump` | Jump host | out of band; DNS record via `tf-dns-technitium`; sits inside the DHCP pool - see flagged concern above |
| `.112` | `packer-builder` | Packer template builder VM | `tf-pve-packer`; sits inside the DHCP pool - see flagged concern above |
| `.184` | (GH Actions runner) | `homelab-ci` self-hosted runner | community-scripts (`ct/docker.sh`), no matching `tf-pve-*` module yet; sits inside the DHCP pool - see flagged concern above |
| `.201` / `.202` / `.203` | `pve1` / `pve2` / `pve3` | Proxmox VE hypervisor hosts | out of band (the cluster itself); DNS records via `tf-dns-technitium` |
| `.241` / `.242` / `.243` | `pve1-amt` / `pve2-amt` / `pve3-amt` | Out-of-band management (Intel AMT) | out of band; DNS records via `tf-dns-technitium` |
| `192.168.15.10` | `truenas-cns1` | Remote TrueNAS, reachable via site-to-site VPN | out of band; only address in this file outside `172.16.0.0/24` |

**Reserved for the k8s module (not yet provisioned):**

| IP | Purpose |
|---|---|
| `.31`, `.32` | Control-plane nodes |
| `.33`-`.39` | Control-plane expansion room, not yet allocated to specific nodes |
| `.41`, `.42`, `.43` | Worker nodes (initial 3) - replaces the retired docker-swarm cluster that previously used `.31`-`.33` |
| `.44`-`.49` | Worker expansion room, not yet allocated to specific nodes |
| `.51`-`.59` | MetalLB LoadBalancer pool |

**Uncertain / flagged, not in the range scheme above:**

- `.101` (`mc`, in the separate `lan.homelab.blue` zone per `tf-dns-technitium/records.tf`) - not
  referenced anywhere else in this pipeline; likely predates it and unrelated to this project's IaC. Also
  sits inside the DHCP pool boundary, same concern as `.111`/`.112`/`.184` above.

The old docker-swarm hosts (`.31`-`.33`, module retired to `_archive/`) are no longer flagged as
uncertain - they're being directly repurposed for the k8s control plane above, per plan.

## Bootstrap / root-of-trust addresses

Same reasoning as `SECRETS.md`'s "Root-of-trust secrets" section: NetBox can't be the source of truth for
the addresses needed to *reach* NetBox in the first place. If NetBox itself is down or the LXC needs
rebuilding, these addresses have to already be known, not looked up:

- **Gateway** (`.1`) and **Technitium DNS** (`.2`-`.4`) - without these, nothing on the LAN resolves or
  routes anywhere, including to NetBox itself.
- **NetBox's own address** (`.17`) - has to be a fixed, remembered value; it can't be self-referential.
- **Proxmox hosts** (`.201`-`.203`) - every VM/LXC in this pipeline, including NetBox, is provisioned
  through the Proxmox API at these addresses; losing track of them blocks rebuilding anything.

These are recorded here, in each module's own `tfvars`/`hosts.yml`, and in `~/.ssh/config` - deliberately
redundant, same as `SECRETS.md`'s root-of-trust secrets being kept outside Infisical.

## Next steps

- **Confirm the DHCP-pool overlap** (`.111`, `.112`, `.184`, and `mc` at `.101`) - check the router/DHCP
  server for static reservations or exclusions before treating it as safe.
- **Backfill NetBox** with the inventory table above (aggregate + prefix + one IP address object per
  host) so it's actually trustworthy as source of truth, not just an empty tool.
- Build the `tf-pve-netbox-ipam` Terraform module (credential already provisioned - see `SECRETS.md`'s
  `/tf-pve-netbox-ipam` entry), then cycle back through existing workload modules (starting with
  `docker-green`) to add their own "IPAM section" using it, per the two-path model above.
