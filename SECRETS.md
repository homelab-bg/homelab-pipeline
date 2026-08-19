# Secrets management

How credentials are organised in [Infisical](https://infisical.com) (self-hosted at
`secrets.lan.example.com`, see [`docker-infisical`](https://github.com/homelab-bg/docker-infisical)),
and - separately - the minimal set of secrets that has to survive *outside* Infisical for the whole
pipeline to be recoverable from nothing.

## Infisical structure

**One project (`homelab-pipeline`), not one per repo.** Every module/repo in this pipeline is a folder
inside a single project, not a separate project. Infisical's project/folder access model already gives
per-consumer least privilege via folder-scoped permissions - a second project would only buy isolation
this pipeline doesn't need (it's all one operator, one org), at the cost of managing N sets of
environments/roles instead of one.

**One environment (`prod`), not the default `dev`/`staging`/`prod` trio.** Nothing here actually runs a
dev/staging split - there's one homelab, one set of real infra. Keeping the default three would just
mean two permanently-empty environments to remember to ignore.

**One folder per consumer, not per secret or per source system.** E.g. `/ansible-pve-docker-green`
holds every secret that playbook needs (Route53 creds, dnsweaver's Technitium token, the CephFS client
key), even though those came from different systems. The folder boundary matches the access boundary
you actually want to draw (least privilege = "what does *this* consumer need"), not how the secrets
happen to be organised elsewhere.

**One scoped machine identity per consumer**, each with:
- Universal Auth (client ID/secret)
- Project role `no-access` (the default/base role grants nothing)
- An **identity-specific additional privilege** (`POST /api/v2/identity-project-additional-privilege`)
  granting `secrets:read` scoped to `environment=prod`, `secretPath=/<that-folder>` only

This project's self-hosted Infisical instance is on the free/open-source tier, which rejects custom
project roles with a folder-scoped `secrets:read` permission (`Failed to create custom role due to plan
RBAC restriction` - confirmed live). Identity-specific additional privileges aren't gated the same way
and achieve the identical scoping, so that's the mechanism used throughout instead of custom roles.
Verified live: a scoped identity can read its own folder and gets nothing back for any other folder.

**Naming convention**: identity `<module>-reader` (or `<module>-<purpose>-reader` if a module has more
than one), secret keys `UPPER_SNAKE_CASE` matching what they'd be as env vars.

## Current inventory

| Folder | Secrets | Consumer(s) | Reader identity |
|---|---|---|---|
| `/tf-dns-technitium` | `TECHNITIUM_URL`, `TECHNITIUM_TOKEN` | `tf-dns-technitium` (owner) | `tf-dns-technitium-reader` |
| | | `tf-dns-secrets` | `tf-dns-secrets-technitium-reader` |
| | | `tf-pve-docker-green` | `tf-pve-docker-green-technitium-reader` |
| | | `homelab-ci`'s `terraform-plan-dns-technitium.yml` | `ci-tf-dns-technitium-reader` |
| `/ansible-pve-docker-green` | `ROUTE53_GREEN_ACCESS_KEY_ID`, `ROUTE53_GREEN_SECRET_ACCESS_KEY`, `ROUTE53_GREEN_REGION`, `ROUTE53_GREEN_HOSTED_ZONE_ID`, `DNSWEAVER_TECHNITIUM_TOKEN`, `CEPHFS_CLIENT_KEY` | `ansible-pve-docker-green` (both `traefik-portainer.yml` and `cephfs-mount.yml`) | `ansible-pve-docker-green-reader` |
| `/shared` | `MINIO_ACCESS_KEY_ID`, `MINIO_SECRET_ACCESS_KEY`, `MINIO_S3_ENDPOINT` | human reference; also read by `homelab-ci`'s `terraform-plan-dns-technitium.yml` via the CLI (backend creds can't come from the native provider - see below) | `ci-tf-dns-technitium-reader` |

Reserved, currently-empty folders (created up front per the one-folder-per-consumer convention, populate
as each module accumulates real secrets): `/ansible-pve-secrets`, `/pkr-pve-templates`,
`/tf-dns-secrets`-owned secrets (none yet - it only *reads* `/tf-dns-technitium`), `/tf-pve-ceph`,
`/tf-pve-docker-green`-owned secrets (same - only reads `/tf-dns-technitium`), `/tf-pve-packer`,
`/tf-pve-template-smoketest`.

Each Terraform module reads via the official `infisical/infisical` provider's `infisical_secrets` data
source; each Ansible playbook reads via the `infisical.vault` collection's `read_secrets` lookup
(`ansible-galaxy collection install infisical.vault` + `pip install infisicalsdk`). Both are native
integrations, not a CLI-wrapper/shell-out - matches this pipeline's existing preference for
provider-native resources over shelling out (see `tf-pve-ceph`'s README section for the one place that
genuinely has no provider-native option).

## Root-of-trust secrets (deliberately outside Infisical)

A secrets manager can't be the root of trust for its own bootstrap credentials - if the values needed to
stand Infisical back up only existed *inside* Infisical, losing the Infisical host would mean losing the
ability to recover it. Same reasoning as a Vault unseal key or a safe combination: it has to live
somewhere the safe itself doesn't gate.

**This is the complete list of what has to survive independently of Infisical** to rebuild the whole
pipeline, including Infisical itself, from nothing:

- **MinIO (Terraform state backend) credentials** - for interactive use, `AWS_ACCESS_KEY_ID`/
  `AWS_SECRET_ACCESS_KEY` are exported manually before any `terraform init`/`plan`/`apply` (see root
  README) - root of trust for every module's state, including `tf-dns-secrets` and
  `tf-pve-docker-green` which otherwise pull their Technitium token from Infisical. A copy (plus
  `MINIO_S3_ENDPOINT`) is stored in Infisical's `/shared` folder too. A Terraform `backend "s3"` block
  is evaluated before any provider or data source can run, so it structurally cannot be sourced from a
  `data "infisical_secrets"` block the way the Technitium token is - but in CI (`homelab-ci`), unlike an
  interactive shell, there's no human to run an `export` first, so the workflow shells out to the
  Infisical CLI as a step before `terraform init` instead. Either way, the underlying MinIO credential
  itself still has to exist somewhere outside Infisical originally - it's the CI job's own Infisical
  identity credentials, not the MinIO creds, that are the thing GitHub Actions actually holds as secrets.
- **Proxmox API token** (`PROXMOX_VE_API_TOKEN`) - needed by every `tf-pve-*` module and Packer.
- **SSH private keys** - `tf-pve-ceph`'s `remote-exec` provisioners and Packer's `qm`-over-SSH both need
  direct key access, independent of Infisical.
- **`ansible-pve-secrets/extra-vars.yml`** in full - this is the actual bootstrap for `docker-infisical`
  itself: `infisical_postgres_user`/`infisical_postgres_password`/`infisical_postgres_db`,
  `infisical_encryption_key`, `infisical_auth_secret`, and the `route53_secrets_*` credentials Caddy
  uses for `secrets.lan.example.com`'s own certificate. None of these can be migrated into Infisical -
  they're what brings Infisical into existence in the first place.
- **Each module's own Infisical machine-identity `client_id`/`client_secret`** (in that module's own
  `local.auto.tfvars`/`extra-vars.yml`) - the credential that authenticates *to* Infisical obviously
  can't be stored *in* Infisical.

### Recovery order

Rebuilding Infisical itself only depends on the list above, plus base infra (Proxmox, Ceph RBD storage,
network reachability to the LXC's static IP) - it does **not** depend on Technitium DNS
already working. `docker-infisical` is reachable by IP before any DNS record or certificate exists, so
`ansible-pve-secrets` can bring it back up even if Technitium/DNS were wiped at the same time.

Only *after* Infisical is confirmed healthy should you re-run `tf-dns-technitium`/`tf-dns-secrets`/
`tf-pve-docker-green` - at that point pulling the Technitium token back out of Infisical (even though
`tf-dns-secrets` manages Infisical's *own* DNS record) is no longer circular, because Infisical is
already up.

### Keep this durable

`ansible-pve-secrets/extra-vars.yml` is now effectively the master recovery key for the entire secrets
system - back it up somewhere durable outside this host (password manager, etc.), not just as a local
gitignored file. Losing it without a backup means losing the ability to recover Infisical at all.
