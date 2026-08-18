# TODO

Deliberately deferred items - not forgotten, just not blocking whatever's in
progress when they came up.

- **Refresh the root README.** Still describes `tf-pve-docker-swarm` as "the
  real docker swarm cluster" (retired) and doesn't mention
  `tf-pve-docker-green`, `tf-dns-technitium`, `ansible-pve-docker-green`, or
  dnsweaver anywhere.
- **Consider release-tagging `docker-traefik-portainer`.** Ansible currently
  pulls `main` directly - inconsistent with everything *it* deploys being
  version-pinned (`TRAEFIK_VER`/`PORTAINER_VER`/`DNSWEAVER_VER`). Worth
  revisiting once the repo's release cadence settles down; tagging adds
  process overhead that isn't worth it while iterating fast.
