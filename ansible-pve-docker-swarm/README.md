# ansible-pve-docker-swarm

Turns the 3 VMs provisioned by `../tf-pve-docker-swarm` into a working Docker Swarm cluster, then deploys Traefik (reverse proxy/TLS) and Portainer Business Edition behind it.

The swarm bootstrap (Docker install, CephFS mount, swarm init/join) started from `_example/ansible-docker-swarm/` (a copy of [rodrigoegimenez/ansible-docker-swarm-cluster](https://github.com/rodrigoegimenez/ansible-docker-swarm-cluster)), reviewed and adapted - see decisions below for what changed and why. Traefik/Portainer come from a separate repo, [homelab-bg/docker-traefik-portainer](https://github.com/homelab-bg/docker-traefik-portainer) - see Services below.

## Topology

All 3 nodes join as Swarm **managers** - no dedicated worker-only nodes.

- 3-manager Raft quorum tolerates 1 node down with no loss of control-plane function (vs. a single manager, where losing it means no scheduling/management until it's back).
- Managers schedule workloads by default (you'd have to explicitly `docker node update --availability drain` to stop that), so "combo manager+worker" isn't extra config - it's just what happens when you join 3 nodes as managers and drain none of them.
- One node (`docker-worker-3001`) is the **bootstrap** node - not a permanent leader, just whichever one runs `docker swarm init` first. The other two join using the manager token.

| Node | IP | PVE node | vmid |
|---|---|---|---|
| docker-worker-3001 (bootstrap) | 192.168.0.31 | pve1 | 3001 |
| docker-worker-3002 | 192.168.0.32 | pve2 | 3002 |
| docker-worker-3003 | 192.168.0.33 | pve3 | 3003 |

> **Naming note**: VM/hostnames stay `docker-worker-*` - `tf-pve-docker-swarm/local.auto.tfvars`'s `docker_role` is kept as `"worker"` deliberately, since it's just a cosmetic tag (every node is actually a combo manager+worker) and changing it would mean destroying and recreating all 3 VMs for no functional benefit (`name` is the `for_each` key in `main.tf`).

## Services

- **Traefik** - reverse proxy + Let's Encrypt TLS via Route53 DNS-01 challenge. **No auth on its dashboard** - the stack (from [homelab-bg/docker-traefik-portainer](https://github.com/homelab-bg/docker-traefik-portainer)) doesn't have a basicauth middleware, so `traefik_domain` is reachable to anyone who can resolve/reach it, guarded only by TLS. Worth hardening later.
- **Portainer Business Edition** (`portainer_edition: ee`) - 3-node license, used for GitOps stack deployment from a GitHub repo. License activation and GitOps repo/webhook configuration happen through Portainer's own UI/API after first boot - **not automated by this playbook**, that's a follow-up once the cluster is actually up and reachable.
- Both come from a single stack, deployed by `traefik-portainer.yml`: it `rsync`s a local clone of `../docker-traefik-portainer` (kept alongside this repo, own git history/remote - see that repo's README) to the bootstrap node and runs `docker stack deploy -c docker-compose.yml -c docker-compose.swarm.yml traefik-portainer`. The swarm overlay bind-mounts both services' persistent state under the shared CephFS mount instead of node-local volumes, so neither needs a placement constraint - see CephFS below.
- Jenkins from the original example was dropped entirely - not part of the plan.

## Prerequisites

- The 3 VMs already exist and are booted (`tf-pve-docker-swarm` applied, `node_templates` pointing at the built Ubuntu 26.04 template).
- Ansible core (tested against 2.16) + `ansible-galaxy collection install -r requirements.yml` (pulls in `community.docker`, used for swarm init/join).
- A private key that matches one of the GitHub accounts in `tf-pve-docker-swarm`'s `authorized_github_users`, available either via `ssh-agent` or a `Host 192.168.0.3*` block in `~/.ssh/config` - deliberately **no key path is hardcoded** in `hosts.yml`, so this stays portable across whoever's running it.
- Sudo/become access as the `ubuntu` user on each VM.

## Layout

```
hosts.yml.example          inventory template - copy to hosts.yml (gitignored) and fill in real IPs
hosts.yml                  inventory - swarm group (all 3) + bootstrap child group (node 3001 only)
requirements.yml           community.docker collection
extra-vars.example.yml     placeholder vars - copy to extra-vars.yml (gitignored) and fill in
swarm-bootstrap.yml        top-level playbook, imports everything below in order
docker-dependencies.yml    installs Docker on all 3 nodes
cephfs-mount.yml           installs ceph-common, mounts shared CephFS at /mnt/cephfs on all 3 nodes
swarm-init.yml             `docker swarm init` on the bootstrap node
swarm-join.yml             other 2 nodes join as managers
traefik-portainer.yml      rsyncs ../docker-traefik-portainer to the bootstrap node, `docker stack deploy`s it
ssh-keyscan.yml            standalone helper - not part of the bootstrap chain
```

## CephFS

All 3 nodes mount a shared CephFS filesystem at `/mnt/cephfs` (`cephfs-mount.yml`), backed by the same PVE/Ceph cluster the VMs run on - MDS on all 3 PVE nodes (1 active + 2 standby), a dedicated `client.swarm` CephX key scoped read-write to just this filesystem (not `client.admin`). Mounted via the kernel CephFS client directly (`mount -t ceph <mons>:/ /mnt/cephfs -o name=swarm,fs=cephfs`), talking straight to the mons over the existing LAN - no Proxmox storage passthrough involved, and no Terraform changes needed since the VMs and mons are already on the same LAN.

This exists so stacks with node-local state can bind to a path under `/mnt/cephfs` instead of a `local` Docker volume - any node can then run the container without losing data on reschedule, removing the need for `docker node update --label-add` placement pinning. `docker-traefik-portainer`'s `docker-compose.swarm.yml` overlay does exactly this for Traefik's cert volume and Portainer's data volume.

`docker-dependencies.yml` deliberately differs from the original example: it uses `get_url` + `signed-by=` for Docker's apt key instead of the deprecated `apt_key` module, detects the VM's actual Ubuntu codename (`ansible_distribution_release`) instead of a hardcoded `focal`, and installs the current `docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin` package set instead of the EOL standalone `docker-compose`. Also installs `python3-docker` (the Docker SDK for Python) - found missing on the first real run, since `community.docker.*` modules need it on the **managed** node, not just the control node.

`swarm-init.yml`/`swarm-join.yml` use the `community.docker.docker_swarm` / `docker_swarm_info` modules (idempotent) rather than the original's `shell` + string-parsing - re-running `swarm-bootstrap.yml` won't error out on an already-initialized or already-joined node.

## Linting

All playbooks pass `ansible-lint`'s strictest (`production`) profile - `requirements.yml` includes `ansible.posix` (needed for the `synchronize` module) alongside `community.docker`; both are real dependencies, not just dev-time conveniences, so don't drop either even if a looser Ansible install happens to work without them.

If your system's `ansible-core` predates 2.17 (check `ansible --version`), `community.docker` will warn/misbehave - `community.docker` 5.x requires `ansible-core >= 2.17`. Rather than fight apt's older packaged version, use an isolated venv:

```sh
python3 -m venv .venv-ansible && .venv-ansible/bin/pip install ansible-core ansible-lint
source .venv-ansible/bin/activate
ansible-galaxy collection install -r requirements.yml
ansible-lint .
```

(`.venv-ansible/` is a local tooling venv, not part of the playbook content - gitignore it if you create one.)

## One-time setup

```sh
cd ansible-pve-docker-swarm
ansible-galaxy collection install -r requirements.yml
cp hosts.yml.example hosts.yml             # then fill in real node IPs
cp extra-vars.example.yml extra-vars.yml   # then fill in real values below
```

Both `hosts.yml` and `extra-vars.yml` are gitignored - same convention as `local.auto.tfvars` on the Terraform side. `extra-vars.yml` needs: `traefik_email`, `traefik_domain`, `traefik_version`, `portainer_domain`, `portainer_license_key`, `portainer_edition`, `portainer_version`, `portainer_port`, `network_name`, `monitoring_stack`, `route53_access_key_id`, `route53_secret_access_key`, `route53_region`, `route53_hosted_zone_id`, `cephfs_mon_hosts`, `cephfs_name`, `cephfs_client_name`, `cephfs_client_key`. See `extra-vars.example.yml` for defaults/shape - most have sensible defaults baked into `traefik-portainer.yml`, only the Route53 credentials and the two domains are truly required.

This repo also expects `../docker-traefik-portainer` to exist (a separate clone of [homelab-bg/docker-traefik-portainer](https://github.com/homelab-bg/docker-traefik-portainer), own git history/remote) alongside it - `traefik-portainer.yml` rsyncs from there, it's not vendored into this repo.

## Running

```sh
ansible-playbook -i hosts.yml swarm-bootstrap.yml -e @extra-vars.yml
```

Runs, in order: `docker-dependencies.yml` → `cephfs-mount.yml` → `swarm-init.yml` → `swarm-join.yml` → `traefik-portainer.yml`.

Individual playbooks can be run on their own the same way (e.g. `ansible-playbook -i hosts.yml traefik-portainer.yml -e @extra-vars.yml`) if you only need to redeploy the stack - e.g. after pushing a change to `docker-traefik-portainer`.

(Both examples above assume passwordless sudo for the `ubuntu` user, which cloud-init sets up by default - add `--ask-become-pass` back if that's not the case in your setup.)

`ssh-keyscan.yml` is a manual one-off, run once per new/rebuilt node before its first real playbook run, to trust its host key:

```sh
ansible-playbook -i hosts.yml ssh-keyscan.yml
```

## After the first run

- Log into Portainer at `https://<portainer_domain>`, activate the Business Edition license, and configure the GitOps stack pointing at the target GitHub repo (PAT/webhook as needed).
- Confirm `docker node ls` on any node shows all 3 as `Leader`/`Reachable` managers.

## Known assumptions, verified on the first real run (2026-08-08)

- **Docker's apt repo may not have a `resolute` (Ubuntu 26.04) component yet** - `docker-dependencies.yml` would have failed at the `apt_repository`/install step if so. **Confirmed it does** - `swarm-bootstrap.yml` ran clean end to end (`docker-dependencies.yml` → `cephfs-mount.yml` → `swarm-init.yml` → `swarm-join.yml`) against all 3 nodes, zero failures. Docker 29.7.2 installed, `docker node ls` shows all 3 as `Ready`/`Active` (1 `Leader`, 2 `Reachable`), CephFS mounted at `/mnt/cephfs` on all 3 and persisted in `/etc/fstab`. The `ansible-core 2.16.3` / `community.docker` version mismatch (see Linting) produced a warning but no actual failures.
- **Full reboot survived cleanly** - all 3 nodes rebooted simultaneously (nothing deployed yet, so no rolling-reboot concern), CephFS remounted correctly via `_netdev` in `/etc/fstab`, Docker came back active, and the swarm quorum reformed (leadership moved to a different node, as expected for a non-permanent leader).
- **`traefik-portainer.yml` verified working end to end**, including real Let's Encrypt certificates via Route53 DNS-01 for both `traefik_domain` and `portainer_domain` (confirmed via direct TLS handshake with correct SNI, not just HTTP status - a plain `Host:` header on a bare-IP request isn't enough to see the real cert, since TLS cert selection happens at SNI time, before the HTTP layer). Getting there surfaced five real bugs in the upstream `docker-traefik-portainer` repo, all now fixed there (see its commit history): `docker stack deploy`'s compose parser rejects bare YAML booleans in `labels:` (docker compose's is more lenient); Traefik v3 removed `providers.docker.swarmMode` for a separate Swarm Provider; Swarm mode doesn't auto-create missing bind-mount host directories (`docker run`/`docker compose up` do); the Swarm Provider reads `deploy.labels`, not the plain `labels:` the Docker provider uses (the big one - without this, every service was silently filtered out, docker-compose.yml swarm overlay was updated to deploy.labels approach); and the `traefik` service's own dashboard router (`service: api@internal`) still needs an explicit `loadbalancer.server.port` label or the provider errors trying to build its unused default service.

## Not in this pass

- Jenkins
- Dynamic inventory generated from `terraform output instances` (currently static, hand-written `hosts.yml`)
- ansible-vault (using a gitignored vars file instead, matching the rest of the repo)
- GitHub Actions / CI wiring for secrets - the long-term plan is GH Actions secrets for both this and the Terraform side; the gitignored-file approach here is a stepping stone that doesn't need restructuring later (a CI step can just write `extra-vars.yml` from `${{ secrets.* }}` before invoking `ansible-playbook`)

