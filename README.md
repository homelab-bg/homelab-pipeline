# homelab-pipeline

Packer + Terraform pipeline for a Proxmox VE homelab cluster (`pve1`/`pve2`/`pve3`).

```
pkr-pve-templates/    Packer: builds golden Ubuntu cloud-init templates, deploys them to every PVE node
tf-pve-packer/         Terraform: provisions the "packer-builder" VM used to run the above
tf-pve-template-smoketest/           Terraform: single-VM smoke test, clones a template via DHCP
tf-pve-docker-swarm/   Terraform: the real docker swarm cluster, clones templates across all 3 nodes
tf-pve-ceph/           Terraform: CephFS (MDS + filesystem) on the PVE cluster itself - own state,
                       deliberately decoupled from the VMs' lifecycle
```

## Prerequisites

- Terraform >= 1.9, Packer with the `hashicorp/proxmox` plugin source available (`packer init` handles this)
- A Proxmox VE cluster (`pve1`, `pve2`, `pve3` by default — see `node_templates` / `pve_nodes` variables) reachable at `https://pve1.<lan_domain>:8006/`
- A Proxmox API token in the form `terraform-prov@pve!tf-bpg=<secret>`, scoped for VM create/clone/destroy
- An S3-compatible state backend (MinIO) reachable at `https://minio.<lan_domain>:30000`, with a bucket matching `bucket = "terraform-state"` in each module's `versions.tf`
- Access-key credentials for that bucket
- Root SSH key access (passwordless, key-based) to `root@<pve_node>.<lan_domain>` for every node listed in a template's `targets` — needed from wherever you run `packer build` (Packer scp's the image and drives `qm` over SSH, it does not use the Proxmox API) **and** from wherever you run `terraform apply`/`destroy` in `tf-pve-ceph` (same reasoning, `remote-exec` provisioners over SSH instead of a provider resource)
- GitHub account(s) whose public keys should be injected into provisioned VMs (fetched at plan/build time from `github.com/<user>.keys` — no local key files needed)

## One-time local setup

Every module keeps its internal domain, network, and access-list values out of git. Each real file has a committed `.example` counterpart showing the required shape — on a fresh clone (or if a file is missing), copy and fill in the real values:

```sh
cp local.auto.tfvars.example      local.auto.tfvars      # each tf-pve-* module
cp backend.local.hcl.example      backend.local.hcl      # each tf-pve-* module
cp local.auto.pkrvars.hcl.example local.auto.pkrvars.hcl # pkr-pve-templates
```

All of these real filenames are gitignored — `git status` should never show them as untracked-and-stageable.

## Environment variables (every `tf-pve-*` module)

```sh
export PROXMOX_VE_API_TOKEN='terraform-prov@pve!tf-bpg=<secret from Bitwarden>'
export AWS_ACCESS_KEY_ID='<minio access key>'
export AWS_SECRET_ACCESS_KEY='<minio secret key>'
```

The S3 backend reads the AWS_* vars automatically; nothing credential-related lives in any `.tf` file.

## Recommended order

1. **`tf-pve-packer`** — provision the dedicated `packer-builder` VM (needs nested virtualization enabled on its Proxmox node for libguestfs).
2. Install Packer + `libguestfs-tools` (`virt-customize`) on that VM (or any other host with nested virt and SSH access to the PVE nodes) — not managed by this repo.
3. **`pkr-pve-templates`** — from that host, build the golden template(s) and deploy to every target node.
4. **`tf-pve-template-smoketest`** — optional smoke test: clone a template, confirm cloud-init/guest-agent/SSH-key injection all work.
5. **`tf-pve-docker-swarm`** — provision the real cluster.

**`tf-pve-ceph`** doesn't fit this sequence - it targets the PVE cluster itself, not a VM, so it has no dependency on any of the above and can be applied any time. It does need to run before the Ansible CephFS-mount step in `ansible-pve-docker-swarm`, which reads its outputs.

---

## `tf-pve-packer`

Provisions one VM (`packer-builder`, vm_id `112`, on `pve1`) cloned from the `node_templates["pve1"]` template.

```sh
cd tf-pve-packer
terraform init -backend-config=backend.local.hcl
terraform plan  -out=tfplan
terraform apply tfplan
```

`local.auto.tfvars` must supply: `lan_domain`, `searchdomain`, `nameservers`, `gateway`, `ipaddr_network`, `authorized_github_users`. The VM gets a static IP at `<ipaddr_network>.112/<cidr>` (default `cidr = 24`).

Destroy with `terraform destroy` when you no longer need a dedicated build host.

---

## `pkr-pve-templates`

Downloads an Ubuntu cloud image, customizes it offline (`qemu-guest-agent`, machine-id reset) with `virt-customize`, then uploads + converts it to a Proxmox template on every node in `targets`.

```sh
cd pkr-pve-templates
packer init .
packer build -var-file=noble.pkrvars.hcl .      # Ubuntu 24.04 LTS -> vmids 924041/924042/924043
packer build -var-file=resolute.pkrvars.hcl .   # Ubuntu 26.04     -> vmids 926041/926042/926043
```

`local.auto.pkrvars.hcl` (auto-loaded, gitignored) supplies just `lan_domain` — everything else (codename, version, template name, per-node `targets`) is versioned in `noble.pkrvars.hcl` / `resolute.pkrvars.hcl` since it carries no internal domain/network info.

Each node is independent — one node failing (SSH/scp error, `qm` refusing to touch a non-template VM at that vmid) doesn't stop the others; failures are summarized at the end and the build exits non-zero if any node failed.

If you build the `resolute` (26.04) template, note the `tf-pve-*` modules' `node_templates` variable still defaults to the `924041`/`924042`/`924043` (`noble`) vmids — override it via tfvars if you want new clones to come from the 26.04 template instead.

---

## `tf-pve-template-smoketest`

Single VM (`tf-test-01`, vm_id `100115`, DHCP) cloned from the `924041` (noble) template on `pve1` — a quick way to confirm templates/keys/guest-agent are working before touching the full cluster.

```sh
cd tf-pve-template-smoketest
terraform init -backend-config=backend.local.hcl
terraform plan  -out=tfplan
terraform apply tfplan
terraform output test_vm_ipv4   # populates once qemu-guest-agent checks in
```

`local.auto.tfvars` must supply: `lan_domain`, `authorized_github_users`.

---

## `tf-pve-docker-swarm`

Provisions every node group in `var.configuration`, round-robining across `var.pve_nodes`, each VM getting a static IP at `<ipaddr_network>.<ipaddr_id + n>`.

```sh
cd tf-pve-docker-swarm
terraform init -backend-config=backend.local.hcl
terraform plan  -out=tfplan
terraform apply tfplan
terraform output instances   # name/ip/node/vm_id per VM - feed into an Ansible inventory
```

`local.auto.tfvars` must supply: `lan_domain`, `searchdomain`, `nameservers`, `gateway`, `ipaddr_network`, `authorized_github_users`, and `configuration` (the list of node groups — vmid base, disks, sizing, `docker_role`, `node_count`). See `local.auto.tfvars.example` for the shape.

---

## `tf-pve-ceph`

Creates MDS daemons (one per `pve_nodes` entry) and a CephFS filesystem on the PVE cluster, via `terraform_data` + `remote-exec` provisioners (SSH as root to the PVE nodes) rather than a Terraform provider resource — as of `bpg/proxmox` `0.111.1` (the latest release), no provider exposes MDS creation, CephFS filesystem creation, or CephX client/auth key management; only `proxmox_ceph_pool` (raw RADOS pools) and the read-only `proxmox_ceph_status` data source exist. Same shape as `pkr-pve-templates/build.pkr.hcl` wrapping `qm` over SSH, for the same reason: the official CLI already does the job, there's no clean provider-native path.

```sh
cd tf-pve-ceph
terraform init -backend-config=backend.local.hcl
terraform plan  -out=tfplan
terraform apply tfplan
```

`local.auto.tfvars` must supply: `lan_domain`, `mon_hosts`, `fsid`, `fs_name`, `ssh_private_key_path`. The `client.swarm` CephX auth key is **not** managed here — `remote-exec` provisioners can't capture a remote command's printed output back into Terraform state, and more importantly this matches how every other secret in this pipeline works (created out-of-band, only ever referenced via a variable, never generated by Terraform). It's supplied directly to `ansible-pve-docker-swarm`'s `extra-vars.yml`.

**`ssh_private_key_path` is required, unlike everywhere else in this pipeline** - `remote-exec`'s connection is Terraform's own SSH client, not the OpenSSH CLI. It doesn't read `~/.ssh/config` (so the `Host pve*.<lan_domain>` block that makes plain `ssh pve1.<lan_domain>` "just work" doesn't apply here) and didn't reliably pick up a running ssh-agent in testing either (`SSH Agent: false` in the provisioner's own connection log, even with `SSH_AUTH_SOCK` set) - it just retried with no auth method until timing out. Point this at the actual key file explicitly.

### Deliberately separate state

Own backend `key` (`homelab/ceph/terraform.tfstate`), independent from every other module's state. This is what actually decouples Ceph's lifecycle from the VMs' — not a convention to remember, a structural guarantee: Terraform can only ever destroy what's in *its own* state file, so nothing in `tf-pve-docker-swarm` (including a full `terraform destroy`) can reach these resources, even by mistake. `tf-pve-docker-swarm` only *reads* this module's outputs (`mon_hosts`, `fs_name`, `fsid`) via a read-only `terraform_remote_state` data source, which never participates in another config's destroy plan.

### Testing vs. production: `fs_name`

`lifecycle.prevent_destroy` can't be driven by a variable (must be a literal, evaluated before any expressions) — so the safety mechanism here is a distinct resource identity, not a toggle. Test repeatedly against `fs_name = "cephfs-test"`; only point this at the real `fs_name = "cephfs"` once, deliberately, when testing is done. Pool names follow the fs name (`<fs_name>_data`/`<fs_name>_metadata`), so a test run can never collide with the real filesystem's pools.

**Cutover, once satisfied:**
1. Change `fs_name` to `"cephfs"` in `local.auto.tfvars`, apply.
2. Add `lifecycle { prevent_destroy = true }` to the `ceph_fs` resource in `main.tf` (already present, commented out) as its own small, visible commit. From then on, any plan that would destroy this resource hard-errors.
3. The rare genuine need to tear it down later: remove the `lifecycle` block, `apply` first (lands the protection change as its own step), *then* `destroy`.

> Done 2026-08-08: full `cephfs-test` apply/destroy cycle validated against the live cluster (destroy-provisioner bug found and fixed - see below), then the manually-created `cephfs`/MDS from before this module existed were deleted and recreated fresh under `fs_name = "cephfs"` via `terraform apply`, so the real filesystem is genuinely IaC-created, not just adopted. `prevent_destroy` is now set - `ceph_fs` is protected.

`ceph_mds` has no destroy-time provisioner at all — `terraform destroy` removes it from state without touching the real MDS daemons, since they're meant to persist across whatever filesystem(s) get created and destroyed against them during testing.

### Known issues found during testing

- **`pveceph fs destroy` can exit 0 on failure.** It refuses to actually remove a filesystem whose MDS is still joinable ("all MDS daemons must be inactive/failed"), but printed that as a plain error and returned success anyway rather than a non-zero exit code - Terraform reported a clean destroy while the real filesystem and pools were still sitting there. Fixed by running `ceph fs fail <name>` first and chaining a post-destroy `ceph fs ls` grep assertion (`&&`-chained, so any step failing - including the assertion - makes the whole provisioner fail loudly). Both are now baked into `ceph_fs`'s destroy-time provisioner.
- **Concurrent `pveceph mds create` across nodes can race.** With all 3 `ceph_mds` `for_each` instances applying in parallel (no ordering between them), one node failed with `rados_conf_read_file failed - Invalid argument` while the other two succeeded - most likely a transient conflict writing to the shared, pmxcfs-backed cluster config from multiple nodes at once. Re-running `pveceph mds create` on the failed node in isolation succeeded immediately, confirming it wasn't a config problem. Not fixed with serialization logic (would add real complexity for a one-time bootstrap operation) - the create step's idempotency guard already makes this self-healing: if `apply` reports a `remote-exec` error on one `ceph_mds` instance, just re-run `apply` (or `pveceph mds create` directly on the affected node, then `apply` to let Terraform adopt it).

---

## Gotchas

- **Changed `backend.local.hcl` or the committed backend block** → Terraform will refuse to plan/apply with "Backend initialization required"; re-run `terraform init -reconfigure -backend-config=backend.local.hcl`.
- **`node_templates` vmids must exist** on their matching Proxmox node before any `tf-pve-*` module can clone from them — run the packer build first.
- **`vm_id` collisions**: `tf-pve-packer` uses `112`, `tf-pve-template-smoketest` uses `100115`, `tf-pve-docker-swarm` computes `vmid + n` per `configuration` entry — check your range doesn't overlap existing VMs.
- All of the above assumes the state bucket (`terraform-state` in MinIO) already exists — Terraform's S3 backend doesn't create it for you.
- **`tf-pve-ceph`'s `fs_name`**: double-check `local.auto.tfvars` before every `apply`/`destroy` while iterating — it's the only thing standing between a `cephfs-test` cycle and the real `cephfs` filesystem until `prevent_destroy` is added (see `tf-pve-ceph` section above).
