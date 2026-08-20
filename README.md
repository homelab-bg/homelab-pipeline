# homelab-pipeline

Packer + Terraform + Ansible pipeline for a Proxmox VE homelab cluster (`pve1`/`pve2`/`pve3`).

```
pkr-pve-templates/         Packer: builds golden Ubuntu cloud-init and Talos templates, deploys them to
                             every PVE node
tf-pve-packer/              Terraform: provisions the "packer-builder" VM used to run the above
tf-pve-template-smoketest/  Terraform: single-VM smoke test, clones a template via DHCP
tf-pve-ceph/                Terraform: CephFS (MDS + filesystem) on the PVE cluster itself - own state,
                             deliberately decoupled from the VMs' lifecycle
tf-dns-technitium/          Terraform: manual/static Technitium DNS records - own state
tf-pve-docker-green/        Terraform: the docker-green host (single VM) + its DNS records
ansible-pve-docker-green/   Ansible: installs Docker, mounts CephFS, deploys Traefik + Portainer +
                             dnsweaver onto docker-green
```

`ansible-pve-docker-green` deploys [`docker-traefik-portainer`](https://github.com/homelab-bg/docker-traefik-portainer) - a separate, public repo, not a subdirectory here. It's cloned directly onto the target host at deploy time (unauthenticated HTTPS), not kept as a local sibling checkout - see that repo's own README for the compose stack itself.

See [`SECRETS.md`](SECRETS.md) for how credentials are organised in Infisical (project/folder/identity structure) and the minimal set of secrets that must survive outside it for disaster recovery.

## Prerequisites

- Terraform >= 1.9, Packer with the `hashicorp/proxmox` plugin source available (`packer init` handles this), Ansible with the `community.docker` and `ansible.posix` collections (`ansible-galaxy collection install -r requirements.yml` in `ansible-pve-docker-green`)
- A Proxmox VE cluster (`pve1`, `pve2`, `pve3` by default — see `node_templates` / `pve_nodes` variables) reachable at `https://pve1.<lan_domain>:8006/`
- A Proxmox API token in the form `terraform-prov@pve!tf-bpg=<secret>`, scoped for VM create/clone/destroy
- An S3-compatible state backend (MinIO) reachable at `https://minio.<lan_domain>:30000`, with a bucket matching `bucket = "terraform-state"` in each module's `versions.tf`
- Access-key credentials for that bucket
- Root SSH key access (passwordless, key-based) to `root@<pve_node>.<lan_domain>` for every node listed in a template's `targets` — needed from wherever you run `packer build` (Packer scp's the image and drives `qm` over SSH, it does not use the Proxmox API) **and** from wherever you run `terraform apply`/`destroy` in `tf-pve-ceph` (same reasoning, `remote-exec` provisioners over SSH instead of a provider resource)
- A running Technitium DNS instance with the internal zone(s) already created (zone creation itself is a manual, out-of-band step - see `tf-dns-technitium` and `tf-pve-docker-green` below, neither manages zones, only records within them) and an API token
- GitHub account(s) whose public keys should be injected into provisioned VMs (fetched at plan/build time from `github.com/<user>.keys` — no local key files needed)

## One-time local setup

Every module keeps its internal domain, network, and access-list values out of git. Each real file has a committed `.example` counterpart showing the required shape.

The real values themselves live in the private [`homelab-pipeline-config`](https://github.com/homelab-bg/homelab-pipeline-config) repo (see its README for the full public/private pairing reasoning). Clone it as a sibling of this repo, then symlink each module's real files into place:

```sh
cd ~/homelab-pipeline
ln -s ../../homelab-pipeline-config/tf-dns-technitium/records.tf         tf-dns-technitium/records.tf
ln -s ../../homelab-pipeline-config/tf-dns-technitium/local.auto.tfvars  tf-dns-technitium/local.auto.tfvars
ln -s ../../homelab-pipeline-config/tf-dns-technitium/backend.local.hcl  tf-dns-technitium/backend.local.hcl
# ... same pattern per module - see homelab-pipeline-config/README.md's Contents section for the full list
```

Setting up a genuinely new module for the first time (nothing in `homelab-pipeline-config` yet)? Copy the `.example` file into `homelab-pipeline-config`'s matching directory, fill in real values, then symlink it back as above:

```sh
cp tf-dns-technitium/local.auto.tfvars.example ../homelab-pipeline-config/tf-dns-technitium/local.auto.tfvars
```

All of these real filenames are gitignored here — `git status` in this repo should never show them as untracked-and-stageable, whether or not the symlink exists yet.

## Environment variables (every `tf-pve-*`/`tf-dns-*` module)

```sh
export PROXMOX_VE_API_TOKEN='terraform-prov@pve!tf-bpg=<secret from Bitwarden>'
export AWS_ACCESS_KEY_ID='<minio access key>'
export AWS_SECRET_ACCESS_KEY='<minio secret key>'
```

The S3 backend reads the AWS_* vars automatically; nothing credential-related lives in any `.tf` file. `PROXMOX_VE_API_TOKEN` is unused by `tf-dns-technitium` (it only talks to Technitium) but harmless to leave exported.

## Recommended order

1. **`tf-pve-packer`** — provision the dedicated `packer-builder` VM (needs nested virtualization enabled on its Proxmox node for libguestfs).
2. Install Packer + `libguestfs-tools` (`virt-customize`) on that VM (or any other host with nested virt and SSH access to the PVE nodes) — not managed by this repo.
3. **`pkr-pve-templates`** — from that host, build the golden template(s) and deploy to every target node.
4. **`tf-pve-template-smoketest`** — optional: clone a template, confirm cloud-init/guest-agent/SSH-key injection all work before trusting it for anything real.
5. **`tf-pve-docker-green`** — provision the `docker-green` host + its DNS records.
6. **`ansible-pve-docker-green`** — `bootstrap.yml` chains Docker install → CephFS mount → Traefik/Portainer/dnsweaver deploy.

**`tf-pve-ceph`** and **`tf-dns-technitium`** don't fit this sequence - neither targets a VM, so neither depends on anything above and both can be applied any time. `tf-pve-ceph` does need to run before `ansible-pve-docker-green`'s CephFS-mount step, which reads its outputs. `tf-dns-technitium` manages records unrelated to `docker-green` entirely (see its own section below) - nothing else in this repo depends on it.

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
packer build -only='null.ubuntu_template' -var-file=noble.pkrvars.hcl .      # Ubuntu 24.04 LTS -> vmids 924041/924042/924043
packer build -only='null.ubuntu_template' -var-file=resolute.pkrvars.hcl .   # Ubuntu 26.04     -> vmids 926041/926042/926043
packer build -only='null.talos_template'  -var-file=talos.pkrvars.hcl .      # Talos v1.13.9    -> vmids 913041/913042/913043
```

**`-only` is required, not cosmetic.** `ubuntu_codename`/`ubuntu_version`/`talos_version`/`talos_schematic_id` all carry defaults (see below) specifically so a single-flavor `-var-file` still validates, but without `-only` scoping which *build* actually runs, `packer build` runs every source in the combined directory - a Talos-only invocation would silently also rebuild the real Ubuntu templates using whatever defaults happen to be set, and vice versa. Confirmed live: an unscoped `packer build -var-file=talos.pkrvars.hcl .` run from an environment without nested virtualization triggered both, and the Ubuntu one failed (safely, at the `virt-customize` stage, before touching any real PVE node - but still not what was intended).

`local.auto.pkrvars.hcl` (auto-loaded, gitignored) supplies just `lan_domain` — everything else (codename, version, template name, per-node `targets`) is versioned in `noble.pkrvars.hcl` / `resolute.pkrvars.hcl` / `talos.pkrvars.hcl` since it carries no internal domain/network info.

Each node is independent — one node failing (SSH/scp error, `qm` refusing to touch a non-template VM at that vmid) doesn't stop the others; failures are summarized at the end and the build exits non-zero if any node failed.

If you build the `resolute` (26.04) template, note the `tf-pve-*` modules' `node_templates` variable still defaults to the `924041`/`924042`/`924043` (`noble`) vmids — override it via tfvars if you want new clones to come from the 26.04 template instead.

**The Talos build is structurally different**, not just a third flavor of the same thing: no `virt-customize` step (`qemu-guest-agent` is baked in via a pinned [Image Factory](https://factory.talos.dev) schematic instead - see `talos-variables.pkr.hcl` for how that schematic ID was derived), no cloud-init drive (Talos has no SSH/user-account surface at all - config is applied post-boot via `talosctl apply-config`, not cloud-init), and a couple of hardware settings Talos's own docs call out as required (`cache=writethrough` on the disk import, ballooning explicitly disabled) that the Ubuntu build doesn't need. `ubuntu_codename`/`ubuntu_version`/`talos_version`/`talos_schematic_id` all carry defaults matching their current pinned value specifically so a single-flavor `-var-file` still validates cleanly - Packer checks every declared variable across the whole directory regardless of `-only`/`-var-file` scoping, so an unset variable belonging to a different flavor would otherwise block *every* build, not just its own. No `tf-pve-*` module consumes the Talos template yet - that arrives with the future k8s cluster work.

---

## `tf-pve-template-smoketest`

Single VM (`tf-test-01`, vm_id `100115`, DHCP) cloned from the `924041` (noble) template on `pve1` — a quick way to confirm templates/keys/guest-agent are working before touching anything real. Run this after any Packer template rebuild; it's the fast, disposable way to catch a broken template before it costs you a real VM's worth of debugging.

```sh
cd tf-pve-template-smoketest
terraform init -backend-config=backend.local.hcl
terraform plan  -out=tfplan
terraform apply tfplan
terraform output test_vm_ipv4   # populates once qemu-guest-agent checks in
```

`local.auto.tfvars` must supply: `lan_domain`, `authorized_github_users`.

---

## `tf-pve-ceph`

Creates MDS daemons (one per `pve_nodes` entry) and a CephFS filesystem on the PVE cluster, via `terraform_data` + `remote-exec` provisioners (SSH as root to the PVE nodes) rather than a Terraform provider resource — as of `bpg/proxmox` `0.111.1` (the latest release), no provider exposes MDS creation, CephFS filesystem creation, or CephX client/auth key management; only `proxmox_ceph_pool` (raw RADOS pools) and the read-only `proxmox_ceph_status` data source exist. Same shape as `pkr-pve-templates/build.pkr.hcl` wrapping `qm` over SSH, for the same reason: the official CLI already does the job, there's no clean provider-native path.

```sh
cd tf-pve-ceph
terraform init -backend-config=backend.local.hcl
terraform plan  -out=tfplan
terraform apply tfplan
```

`local.auto.tfvars` must supply: `lan_domain`, `mon_hosts`, `fsid`, `fs_name`, `ssh_private_key_path`. CephX client auth keys are **not** managed here — `remote-exec` provisioners can't capture a remote command's printed output back into Terraform state, and more importantly this matches how every other secret in this pipeline works (created out-of-band via `ceph fs authorize cephfs client.<name> / rw` on the PVE cluster, only ever referenced via a variable, never generated by Terraform). Each consumer gets its own key (e.g. `client.green` for `ansible-pve-docker-green`) rather than sharing one - same least-privilege-per-consumer pattern as every other credential in this pipeline - supplied directly to that consumer's own `extra-vars.yml`.

**`ssh_private_key_path` is required, unlike everywhere else in this pipeline** - `remote-exec`'s connection is Terraform's own SSH client, not the OpenSSH CLI. It doesn't read `~/.ssh/config` (so the `Host pve*.<lan_domain>` block that makes plain `ssh pve1.<lan_domain>` "just work" doesn't apply here) and didn't reliably pick up a running ssh-agent in testing either (`SSH Agent: false` in the provisioner's own connection log, even with `SSH_AUTH_SOCK` set) - it just retried with no auth method until timing out. Point this at the actual key file explicitly.

### Deliberately separate state

Own backend `key` (`homelab/ceph/terraform.tfstate`), independent from every other module's state. This is what actually decouples Ceph's lifecycle from any VM module's — not a convention to remember, a structural guarantee: Terraform can only ever destroy what's in *its own* state file, so nothing in another module (including a full `terraform destroy` there) can reach these resources, even by mistake. Consumers only *read* this module's outputs (`mon_hosts`, `fs_name`, `fsid`) via a read-only `terraform_remote_state` data source, which never participates in another config's destroy plan.

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

## `tf-dns-technitium`

Manages standalone Technitium DNS records that don't belong to any other module - `kevynb/technitium` manages records only, not zones, so zone creation itself is a one-time manual step via the Technitium admin console/API. The actual record data lives in `records.tf`, which is gitignored and not templated via a `.example` file (unlike every other module's `local.auto.tfvars` pattern) - there's no good way to genericize real internal DNS topology without defeating the point of having it in Terraform.

```sh
cd tf-dns-technitium
terraform init -backend-config=backend.local.hcl
terraform plan  -out=tfplan
terraform apply tfplan
```

`local.auto.tfvars` must supply: `technitium_url`, `technitium_token`.

---

## `tf-pve-docker-green`

Provisions `docker-green` (vm_id `4001`, hostname `docker1`) - a single, fixed-placement host, not a scalable group, so this skips the round-robin/`for_each` machinery a multi-node module would need. Also creates its DNS records: an A record for the host itself, a direct A record for the Traefik dashboard (not a CNAME - so dnsweaver's dynamically-created per-app CNAMEs resolve in one hop, not two), and a CNAME for Portainer onto the Traefik record (reflecting the actual request path: client → Traefik → Portainer container).

```sh
cd tf-pve-docker-green
terraform init -backend-config=backend.local.hcl
terraform plan  -out=tfplan
terraform apply tfplan
terraform output instance   # ip/node/vm_id - feed into ansible-pve-docker-green's hosts.yml
```

`local.auto.tfvars` must supply: `lan_domain`, `searchdomain`, `nameservers`, `gateway`, `minio_s3_endpoint`, `vm` (an object: `vmid`/`name`/`ipaddr`/`node`/`template`/`sockets`/`cores`/`memory`/`disks`), `technitium_url`, `technitium_token`, `docker_domain`, `traefik_domain`, `portainer_domain`, `authorized_github_users`.

No Failover/Weighted Round Robin Technitium APP record here - that mechanism exists to solve the multi-A-record "fast flux" problem (multiple A records for one hostname can trip Chrome Safe Browsing's heuristics), which doesn't arise with a single host. Reads `tf-pve-ceph`'s outputs the same way any consumer would - a read-only `terraform_remote_state` data source, never participating in this module's own destroy plan.

---

## `ansible-pve-docker-green`

```sh
cd ansible-pve-docker-green
ansible-galaxy collection install -r requirements.yml
ansible-playbook -i hosts.yml bootstrap.yml --ask-become-pass -e @extra-vars.yml
```

`bootstrap.yml` chains three playbooks:

1. **`docker-dependencies.yml`** — installs Docker CE + Compose plugin from Docker's own apt repo, plus `git` (needed by the next playbook's clone step).
2. **`cephfs-mount.yml`** — mounts the shared CephFS filesystem at `/mnt/cephfs`, using its own `client.green` CephX key (see `tf-pve-ceph` above).
3. **`traefik-portainer.yml`** — clones [`docker-traefik-portainer`](https://github.com/homelab-bg/docker-traefik-portainer) directly from GitHub (public, unauthenticated HTTPS - no credentials needed on the target host) and deploys it via `docker compose up -d`. Writes two file-based secrets first (`secrets/aws_credentials` for Traefik's Route53 DNS-01 challenge, `secrets/technitium_token` for dnsweaver) rather than passing them as plain environment variables. Persistent data (Portainer's DB, Traefik's issued certs) bind-mounts onto the CephFS mount from step 2, so a VM rebuild doesn't take them with it.

`hosts.yml` needs a `green` group with `docker1`'s IP. `extra-vars.yml` must supply: `traefik_email`/`traefik_version`/`traefik_domain`, `portainer_domain`/`portainer_version`/`portainer_port`, `network_name`, `technitium_url`, `dnsweaver_version`/`dnsweaver_zone`/`dnsweaver_domains`/`dnsweaver_technitium_token` (a token scoped to just that one zone - Technitium's permission model supports per-zone ACLs, use a dedicated user, not the admin account), `route53_green_access_key_id`/`route53_green_secret_access_key`/`route53_green_region`/`route53_green_hosted_zone_id` (scoped to the *public* hosted zone used only for the ACME DNS-01 challenge - separate from the internal Technitium zone), and `cephfs_mon_hosts`/`cephfs_name`/`cephfs_client_name`/`cephfs_client_key`.

`traefik-portainer.yml` can also be run on its own (without the full `bootstrap.yml` chain) once Docker and the CephFS mount are already in place - e.g. to pick up a new `docker-traefik-portainer` commit, or to redeploy after a var change.

---

## Gotchas

- **Changed `backend.local.hcl` or the committed backend block** → Terraform will refuse to plan/apply with "Backend initialization required"; re-run `terraform init -reconfigure -backend-config=backend.local.hcl`.
- **`node_templates` vmids must exist** on their matching Proxmox node before any `tf-pve-*` module can clone from them — run the packer build first.
- **`vm_id` collisions**: `tf-pve-packer` uses `112`, `tf-pve-template-smoketest` uses `100115`, `tf-pve-docker-green` uses `4001` — check your range doesn't overlap existing VMs.
- All of the above assumes the state bucket (`terraform-state` in MinIO) already exists — Terraform's S3 backend doesn't create it for you.
- **`tf-pve-ceph`'s `fs_name`**: double-check `local.auto.tfvars` before every `apply`/`destroy` while iterating — it's the only thing standing between a `cephfs-test` cycle and the real `cephfs` filesystem until `prevent_destroy` is added (see `tf-pve-ceph` section above).
- **`ansible-pve-docker-green`'s `traefik-portainer.yml`** deploys a pinned release tag of `docker-traefik-portainer` (`docker_traefik_portainer_version`, default set in the playbook) - bump it deliberately in `extra-vars.yml` to move forward, it won't happen on its own.
