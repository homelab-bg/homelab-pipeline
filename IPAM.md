# IP address management

How static IP addresses are allocated, tracked in [NetBox](https://netboxlabs.com) (self-hosted at
`ipam.lan.example.com`, see [`ansible-pve-netbox`](ansible-pve-netbox/)) - same relationship this
project's [`SECRETS.md`](SECRETS.md) has to Infisical: NetBox is the source of truth, this file documents
the allocation policy, the SOP for claiming a new address, and a manually-kept snapshot for human
reference.

**NetBox is partially populated.** Site `steve`'s "bootstrap infra" (see below) has been hydrated via the
[`tf-pve-netbox-ipam`](tf-pve-netbox-ipam/) module - RIR, aggregate, site, `default` role, the
`172.16.0.0/24` prefix, and one IP address object per bootstrap-infra host. Nothing else yet: the other
two sites (`mum-and-dad`, `dan`), the `iot`/`camera`/`guest` roles, and every workload module's own IP
(docker-green, packer-builder, the future k8s module) are still only recorded in this file, not NetBox.

## Multi-site model

This NetBox instance spans **three physically separate UniFi networks**, not just this repo's own
homelab: `steve` (this pipeline), `mum-and-dad`, and `dan`. Each site has a numeric ID that drives a
consistent subnet/VLAN numbering scheme across all three.

**Sites** (NetBox `Site` objects, each with a custom `site_id` text field - see the gotcha below):

| Site | Slug | `site_id` |
|---|---|---|
| Steve | `steve` | 14 |
| Mum & Dad | `mum-and-dad` | 15 |
| Dan | `dan` | 16 |

**Roles** (NetBox `Role` objects, created once, shared across all three sites' matching prefixes):
`default`, `iot`, `camera`, `guest`.

**Subnets** (site-scoped prefixes, no VRF - the three networks are physically separate/non-overlapping by
construction, so there's no address-space conflict a VRF exists to solve):

| Role | Formula | 14 (steve) | 15 (mum-and-dad) | 16 (dan) |
|---|---|---|---|---|
| default | `172.16.<id>.0/24` | `.14.0/24` | `.15.0/24` | `.16.0/24` |
| iot | `192.168.<id>.0/24` | `.14.0/24` | `.15.0/24` | `.16.0/24` |
| camera | `10.0.<id>.0/24` | `.14.0/24` | `.15.0/24` | `.16.0/24` |
| guest | `192.168.199.0/24` (same everywhere - isolated, internet-only, never bridged) | same | same | same |

**VLAN IDs** (not yet applied in UniFi - currently arbitrary `1`/`2`/`3`/`4` tags; whether to actually
retag to match this formula is still an open decision, not needed to use NetBox/IPAM in the meantime):

| Role | Formula | 14 | 15 | 16 |
|---|---|---|---|---|
| default | `<id>` | 14 | 15 | 16 |
| iot | `100 + <id>` | 114 | 115 | 116 |
| camera | `200 + <id>` | 214 | 215 | 216 |
| guest | fixed `199` (shared, matches the shared subnet) | 199 | 199 | 199 |

**Site-to-site VPN overlay**: UniFi provides a VPN overlay connecting each site's **default** network to
the others (remote access from any site's default network to any other's). This is why the default-role
subnets specifically need to be unique per site - it's what makes flat routing across the overlay work
without renumbering. Recorded as a plain-text note on each default-network prefix's description, not
modeled as a NetBox `vpn.Tunnel` object (NetBox 4.6.8 has native Tunnel/TunnelTermination support,
confirmed against its live API schema, but modeling it properly needs to know the actual
encapsulation/topology UniFi uses underneath - deferred until that's worked out).

**`site_id` custom field gotcha**: created as an `integer` type first, which failed - the NetBox Terraform
provider's `custom_fields` argument always sends values as strings, and NetBox's own validation rejects a
quoted string for an integer-typed custom field (`"Value must be an integer"`, confirmed live). Custom
field types can't be changed in place either (`"Changing the type of custom fields is not supported"`) -
had to delete and recreate it as `text`. Works fine for lookup purposes either way; nothing does arithmetic
on `site_id` inside NetBox itself.

## IPv6 addendum (dual-stack; IPv4 scheme unchanged)

Layered on top of the multi-site model above - same sites, same roles, same site-to-site VPN
constraints. AussieBroadband (ABB) is the ISP at all three sites. **Not yet applied anywhere** - this is
the target scheme, sequenced behind the v4 migration below (see "Rollout order").

### Status

- ABB has IPv6 available at all three sites; not yet enabled on any UDM.
- Site Magic (the UniFi site-to-site VPN overlay) is **IPv4-only** - no v6 across the overlay. v6 is
  per-site; cross-site traffic keeps using v4, same as it does today.

### Prefixes

| Site (id) | ABB delegated GUA /48 | Notes |
|---|---|---|
| steve (14) | `2403:581e:bae5::/48` | static v4 |
| mum-and-dad (15) | `2403:5819:cec1::/48` | static v4 |
| dan (16) | TBD | personal plan, v4 is CGNAT - confirm PD is actually offered on this plan tier (not just its size) before assuming `/48`; record prefix + size once known |

- **ULA**: one random `/48` shared across all three sites, `<ULA48>` (generate once per RFC 4193, never
  `fd00::/48` - that's a documented example prefix, not a real one). Record in NetBox as a container
  prefix. Sharing one `/48` across sites only avoids collisions because the subnet-ID convention below
  already makes every site's subnet IDs globally unique (14/114/214/199 vs 15/115/215/199 vs
  16/116/216/199) - if a future site ever reused an ID already in use elsewhere, its ULA subnets would
  collide. Worth a note wherever the ULA `/48` gets recorded, same spirit as the `site_id` custom-field
  gotcha above.
- ABB's WAN `/64`s are the UDM-to-ISP link only - never assign one to a LAN.
- ABB says delegated `/48`s can change occasionally: don't hard-code GUAs in firewall rules or DNS - use
  ULA/hostnames/groups instead.

### Subnet ID convention

4th hextet = VLAN ID digits written **literally** (`14`, `114`, `214`, `199`), not hex-converted - a
mnemonic, not an arithmetic encoding. Safe here because every VLAN ID in this scheme is built from
decimal digits `0`-`9` only (never needs a hex letter `a`-`f`), so the literal digits always mean what
they look like. GUA: `<site GUA48>:<vlan>::/64`; ULA: `<ULA48>:<vlan>::/64`.

| Role | VLAN (14/15/16) | GUA | ULA |
|---|---|---|---|
| default | 14/15/16 | yes | yes |
| iot | 114/115/116 | yes | yes |
| camera | 214/215/216 | no | yes (or leave v4-only, see open items) |
| guest | 199 | yes | no |

Guest gets GUA but not ULA - it's internet-only and isolated by design (never talks to anything
internal), so a stable internal-only address is pointless for it; default and iot get both since they
need internet reachability *and* a stable address that survives ABB reassigning the delegated `/48`.

### UniFi implementation

- WAN: DHCPv6 with prefix delegation.
- Networks: Prefix Delegation for GUA, ULA configured as an "Additional IPv6 Network" on the VLAN
  interface, SLAAC for address assignment.

### Firewall

- Mirror every v4 zone policy for v6 (IoT and guest isolation) - v6 doesn't inherit v4's isolation just
  because it's on the same VLAN; each policy needs its own v6 rule.
- Allow ICMPv6 always - never blanket-block it. IPv6 depends on it for NDP/PMTUD/etc.; blocking it
  breaks IPv6 itself, not just some feature riding on top of it.
- Default-deny inbound GUA.
- Block `fc00::/7` (the full ULA range, not just `fd00::/8`) at WAN - ULA should never leak onto the
  internet.
- **IoT: default-deny outbound, not just default-deny inbound.** Stated policy, not yet applied anywhere
  (v4 or v6). Exceptions get added as explicit per-device firewall rules, not by opening the whole VLAN.
  Example: Shelly relays currently reach the internet directly for cloud/app control - the preferred end
  state is to cut that entirely and drive them solely through Home Assistant (LAN-local), removing the
  need for an exception at all rather than adding one. This is a dual-stack policy - it applies to
  today's v4 IoT VLAN too, not just the future v6 one - see "Rollout order" below for why it's sequenced
  ahead of enabling v6 on IoT specifically.

### DNS

Cross-site service names return `A` records only - `AAAA` would send clients down a v6 path that
doesn't exist across sites (Site Magic is v4-only, see "Status" above).

### Open items (verify before applying)

1. Does UniFi's Prefix ID field accept 4-digit IDs (e.g. `0214`)? If it's only 8-bit, every subnet ID in
   this scheme (max `216`) still fits in a single byte, so the scheme survives either way - but confirm
   against the actual UDM firmware before relying on that assumption.
2. Can a camera VLAN be ULA-only (no GUA advertised at all)? Yes - an interface with only a ULA prefix
   in its RA is a normal, fully-supported IPv6 configuration; devices get ULA + link-local and nothing
   else. Not blocked on anything, just needs the camera VLAN's RA to omit the GUA prefix.
3. Dan's delegated prefix - confirm PD is actually offered on that specific ABB personal-plan tier (not
   just its size) before assuming `/48`; some residential tiers do CGNAT-v4 with no PD at all rather than
   full delegation.
4. **Given the IoT default-deny-outbound policy above, does IoT still need a GUA at all?** With outbound
   denied by default and exceptions added per-device, IoT could plausibly stay ULA-only (like camera) and
   let any genuinely internet-facing exception device fall back to its existing IPv4 path instead of
   needing a v6-specific firewall exception built at all. Worth deciding before WAN v6 is enabled on the
   IoT VLAN, not after - changes the "iot: GUA yes" row above if decided the other way.

### Rollout order

1. **Fix v4 first** - migrate steve's site to the target v4 scheme (see "Next steps" below). Not
   parallel work: the v6 scheme's subnet IDs are derived from the v4-target VLAN IDs, so the v4 migration
   is a hard prerequisite, not just a nice-to-do-first.
2. **Validate the IoT default-deny-outbound firewall policy on v4** - apply it, work through the actual
   exception list (Shelly and anything else currently phoning home), confirm nothing breaks. Deliberately
   proven on v4 first, one well-understood stack, before adding v6 into the mix.
3. **Enable IPv6 local-only** - ULA addressing via SLAAC across VLANs, no WAN prefix delegation and no
   GUA yet. Validates DNS/SLAAC/firewall-mirroring behavior internally without adding any new
   internet-facing exposure - deliberate choice, not wanting to double the exposure surface before the v4
   firewall-rule model (step 2) is proven.
4. **Enable WAN v6** (PD + GUA) at steve's site, trial on one lab VLAN first, carry the validated
   outbound-deny model over to it (see open item 4 above for whether IoT needs this at all).
5. **Roll out remaining networks at steve's, then mum-and-dad's, then dan's.**

## Steve's site (14): current addressing, not yet migrated

Steve's network needs reallocation to fit the scheme above - none of this has happened yet, only the
*default* network's current (unmigrated) state has been hydrated into NetBox:

| Role | Current | Target |
|---|---|---|
| default | `172.16.0.0/24` (hydrated into NetBox as-is) | `172.16.14.0/24` |
| iot | `172.16.2.0/24` | `192.168.14.0/24` |
| camera | none | `10.0.14.0/24` (new) |
| guest | `172.16.199.0/24` | `192.168.199.0/24` (shared with the other two sites) |

A fourth VLAN, `management` (`172.16.1.0/24`, never used), doesn't correspond to any of the 4 subnet
roles above and is being retired rather than migrated.

### Addressing scheme (current `172.16.0.0/24`, before migration)

`.101`-`.199` is the router's DHCP pool - **not available for new static allocation**. Everything below
assumes static allocations stay in `.2`-`.99` or `.200`-`.254`.

| Range | Purpose | Notes |
|---|---|---|
| `.1` | Gateway | |
| `.2`-`.9` | Core network services | Technitium `ns1`-`ns3` currently `.2`-`.4` |
| `.10`-`.19` | Core shared platform/storage services | TrueNAS/MinIO `.10`; `secrets` LXC `.15`; `netbox` LXC `.17` |
| `.20`-`.30` | Reserved / available | |
| `.31`-`.39` | **Kubernetes control-plane nodes** | `.31`-`.32` in use (`.33` next); remainder held for expansion room, not a fixed target node count |
| `.40` | `docker-green` | moved from `.41` to make room for k8s workers below |
| `.41`-`.49` | **Kubernetes worker nodes** | reserved, not yet provisioned; `.41`-`.43` for the initial 3, remainder held for expansion |
| `.50` | Reserved / available | |
| `.51`-`.59` | **MetalLB LoadBalancer pool** | reserved, not yet provisioned - deliberately separate from node IPs; L2 mode needs a block never handed to a node or by DHCP, but still on-segment |
| `.60`-`.99` | General-purpose VMs/LXCs (requested from NetBox, not hand-picked) | `.60` = `docker-mcp-agents`, first host provisioned via `netbox_available_ip_address` rather than a manually-chosen address - see "Two allocation paths" below |
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

**One IPAM instance for all three sites**, not one per site or per module - matches Infisical's
single-project reasoning in `SECRETS.md`: one operator, no isolation boundary that would justify the
overhead of more than one.

**One RIR (`RFC1918`) + one aggregate + one prefix per site per role**, with individual IP address objects
underneath for each allocated host. Roles are shared objects, not duplicated per site - see "Multi-site
model" above.

**`vmid`-matches-last-octet convention** (established with `tf-pve-netbox`, e.g. NetBox itself is `vmid
117` at `.17`): where a static IP is assigned to a new Proxmox VM/LXC, match its Proxmox `vmid` to the
IP's last octet where practical. Not retrofitted onto pre-existing hosts that don't already follow it.

**Description convention** for each IP address/prefix object: `<hostname-or-site>-<role-or-consumer>`,
e.g. `netbox - bootstrap infra`, `steve-default`, so the reverse lookup from NetBox back to the owning
module/repo doesn't require guessing.

**One `netbox_ip_range` + matching `netbox_tag` per band** in the addressing-scheme table below (see
`tf-pve-netbox-ipam/hydration.tf`) - `netbox_ip_range` has no name/slug field of its own, so a tag (named
identically to the range, e.g. `reserved-60-99`, `k8s-control-plane`) is the only structured way for a
consuming module to look one up (`data "netbox_ip_ranges" { filter { name = "tag" ... } }`) without
hardcoding a numeric ID. Confirmed live that this provider's `tags` argument does **not** auto-create a
referenced tag - it errors ("could not locate referenced tag") if one doesn't already exist as a real
`netbox_tag` resource.

## Two allocation paths: bootstrap infra vs. everything else

**"Bootstrap infra"** - NetBox itself, Infisical (`secrets`), the Technitium DNS servers, the Proxmox
hosts, and anything else needed just to *reach* NetBox in the first place - can't rely on NetBox for its
own address allocation; it either predates NetBox or has to exist before NetBox is reachable. These get
entered into NetBox as a one-time backfill/hydration pass after the fact (`tf-pve-netbox-ipam/hydration.tf`),
the same way `tf-dns-technitium/records.tf`'s baseline records were hydrated from the retired Unbound
config rather than allocated through Technitium itself. This is a permanent characteristic of bootstrap
infra, not a gap to eventually close. Deliberately excludes `docker-green` and `packer-builder` - both
already have their own `tf-pve-*` module, so they follow the path below instead, not this one.

**Everything else** (workload modules - `docker-green`/`packer-builder`/`docker-mcp-agents` today, the
upcoming k8s module, future general-purpose VMs/LXCs) is meant to move to **programmatic allocation**: the
module's own Terraform claims its IP from NetBox at `apply` time (via the `e-breuninger/netbox` Terraform
provider against the shared `NETBOX_URL`/`NETBOX_API_TOKEN` credential in `/shared` - see `SECRETS.md`),
instead of a human picking a free address from this file by hand. `tf-pve-mcp-agents` is the first real
example: `netbox_available_ip_address`, scoped to the `reserved-60-99` range's `ip_range_id` (found via a
`data "netbox_ip_ranges"` filter on that range's tag - see "NetBox structure" below), returned `.60` on
first apply. Given this project's general preference for deliberate static assignment otherwise (see the
range tables above, all pre-planned rather than DHCP-style auto-pick), expect hosts with a specific planned
address (like the k8s nodes) to keep using `netbox_ip_address` with an explicit value - `mcp-agents` used
the "claim next free from a general-purpose band" path specifically because it didn't have one. Cycling
back to retrofit `docker-green` and `packer-builder` with their own IPAM section is tracked as a follow-up
below.

## SOP: allocating a new static IP (current, manual process)

1. **Pick a free address** in the appropriate range band above (check NetBox once it's populated; until
   then, check the inventory table below and each module's own `tfvars`/`hosts.yml` directly, since this
   table can go stale between updates). Never from `.101`-`.199` (DHCP pool).
2. **Create the IP address object in NetBox** (web UI, or the `tf-pve-netbox-ipam` module for
   bootstrap-infra-style hosts, or the owning module's own future "IPAM section" for anything else) -
   status `active`, description per the convention above.
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

## Current inventory (steve site, current/unmigrated `172.16.0.0/24`, unless noted)

All rows below marked **hydrated** are now live in NetBox (`tf-pve-netbox-ipam`), not just this table.

| IP | Hostname | Purpose | Provisioned by |
|---|---|---|---|
| `.1` | (gateway) | Router | out of band, not hydrated (not "our" infra to register) |
| `.2` / `.3` / `.4` | `ns1` / `ns2` / `ns3` | Technitium DNS (HA cluster) | out of band; DNS records via `tf-dns-technitium`; **hydrated** |
| `.10` | `truenas-bne1` / `minio` / `minio-console` | TrueNAS + MinIO (Terraform state backend) | out of band; DNS records via `tf-dns-technitium`; **hydrated** |
| `.12` | `truenas-bne2` | Second TrueNAS unit (backup target) | out of band; DNS records via `tf-dns-technitium`; **hydrated** |
| `.15` | `secrets` | Infisical (self-hosted secrets manager) | community-scripts (`ct/docker.sh`), no matching `tf-pve-*` module yet; **hydrated** |
| `.17` | `netbox` | NetBox (this file's own IPAM instance) | `tf-pve-netbox` + `ansible-pve-netbox`; **hydrated** (permanent exception - can't self-register, see "Two allocation paths") |
| `.40` | `docker-green` | Playground-tier Docker host (Traefik/Portainer) | `tf-pve-docker-green` + `ansible-pve-docker-green` - moved from `.41` on 2026-08-25 to free `.41`-`.43` for k8s workers; **has its own IPAM section**: `netbox_ip_address` with the existing fixed value (`var.vm.ipaddr`), not `netbox_available_ip_address` - this host already had a planned address, unlike `mcp-agents`; not part of the bootstrap-infra hydration |
| `.60` | `docker-mcp-agents` | MCP servers (HA/UniFi/TrueNAS) + agents for Claude Desktop/Code, behind Caddy | `tf-pve-mcp-agents` + `ansible-pve-mcp-agents` - **first host with its own IPAM section from day one**: requested via `netbox_available_ip_address` scoped to the `reserved-60-99` range's tag, not hand-picked; not part of the bootstrap-infra hydration |
| `.111` | `jump` | Jump host | out of band; DNS record via `tf-dns-technitium`; sits inside the DHCP pool - see flagged concern above; **hydrated** |
| `.112` | `packer-builder` | Packer template builder VM | `tf-pve-packer`; sits inside the DHCP pool - see flagged concern above; **has its own IPAM section**: `netbox_ip_address` with the existing fixed value, same pattern as `docker-green` - not part of the bootstrap-infra hydration |
| `.184` | (GH Actions runner) | `homelab-ci` self-hosted runner | community-scripts (`ct/docker.sh`), no matching `tf-pve-*` module yet; sits inside the DHCP pool - see flagged concern above; **hydrated** |
| `.201` / `.202` / `.203` | `pve1` / `pve2` / `pve3` | Proxmox VE hypervisor hosts | out of band (the cluster itself); DNS records via `tf-dns-technitium`; **hydrated** |
| `.241` / `.242` / `.243` | `pve1-amt` / `pve2-amt` / `pve3-amt` | Out-of-band management (Intel AMT) | out of band; DNS records via `tf-dns-technitium`; **hydrated** |
| `192.168.15.10` | `truenas-cns1` | Remote TrueNAS, reachable via site-to-site VPN | out of band; different subnet, not hydrated (no prefix modeled for it) |

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

- **Priority 1: migrate steve's site** to the target scheme: default `172.16.0.0/24` →
  `172.16.14.0/24`, iot `172.16.2.0/24` → `192.168.14.0/24`, guest `172.16.199.0/24` →
  `192.168.199.0/24` (shared), retire the unused `management` VLAN, add a `camera` network
  (`10.0.14.0/24`) if/when cameras are added. Hard prerequisite for the IPv6 addendum's rollout below -
  the v6 subnet IDs are derived from these v4-target VLAN IDs.
- **Priority 2: apply the IoT default-deny-outbound firewall policy** (v4 first) - see the IPv6
  addendum's "Firewall" and "Rollout order" sections above for the full policy and why it's sequenced
  before any v6 exposure.
- **Priority 3: enable IPv6, local-only first** (ULA via SLAAC, no WAN prefix delegation/GUA yet) - see
  the IPv6 addendum above for the full scheme; WAN v6 (PD + GUA) comes only after steps 1-2 are proven
  and open item 4 (whether IoT needs a GUA at all) is decided.
- **Build out `mum-and-dad` (15) and `dan` (16)** in NetBox - sites, plus their `default`/`iot`/`camera`
  prefixes and the shared `guest` prefix.
- **Decide on UniFi VLAN retagging** - whether to actually apply the `<id>`/`100+<id>`/`200+<id>`/`199`
  formula in UniFi, or leave VLAN IDs arbitrary and only use the formula as NetBox documentation.
- **Confirm the DHCP-pool overlap** (`.111`, `.112`, `.184`, and `mc` at `.101`) - check the router/DHCP
  server for static reservations or exclusions before treating it as safe.
- ~~Retrofit `docker-green` and `packer-builder` with their own "IPAM section"~~ - done for both: a plain
  `netbox_ip_address` for each existing fixed address, not `netbox_available_ip_address` (that path is for
  a host with no address planned yet, like `mcp-agents` was). `packer-builder` needed a brand-new Infisical
  identity (`tf-pve-packer-reader`, `/shared` read-only) since that module had never used Infisical before;
  `docker-green` reused its existing `tf-pve-docker-green-technitium-reader` identity with an added grant.
- ~~Resolve the `records.tf`/`hydration.tf` commit policy~~ - done: both are now symlinks into
  `homelab-pipeline-config` (private), with the real content committed there - `records.tf` already worked
  this way and just had a stale comment; `hydration.tf` has now been moved to match. The symlinks
  themselves stay gitignored in the public repo (machine-local wiring, recreated after a fresh clone), same
  as `local.auto.tfvars` everywhere else.
- Consider modeling the site-to-site VPN overlay as a real NetBox `vpn.Tunnel` object later, once the
  actual UniFi encapsulation/topology is confirmed (currently just a text note - see "Multi-site model").
