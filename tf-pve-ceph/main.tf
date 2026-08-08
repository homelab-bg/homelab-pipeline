# MDS daemons - foundational/shared, created once, then reused by whichever
# filesystem(s) get created against them (both cephfs-test and, eventually, cephfs).
# No test/prod naming split needed here, and no destroy-time provisioner: destroying
# this resource removes it from Terraform state without touching the real MDS
# daemons, since they're meant to persist across whatever filesystems get created
# and destroyed against them during testing.
resource "terraform_data" "ceph_mds" {
  for_each = toset(var.pve_nodes)

  connection {
    type        = "ssh"
    host        = "${each.value}.${var.lan_domain}"
    user        = "root"
    private_key = file(var.ssh_private_key_path)
  }

  provisioner "remote-exec" {
    # Idempotency guard - safe to re-run against an MDS that already exists.
    inline = [
      "systemctl is-active --quiet ceph-mds@${each.value} || pveceph mds create"
    ]
  }
}

# CephFS filesystem. fs_name is a variable, not hardcoded, specifically so this
# can be pointed at a throwaway "cephfs-test" identity while iterating and only
# at the real "cephfs" once, deliberately - see README.
resource "terraform_data" "ceph_fs" {
  # pve_node and lan_domain live here (not just referenced from var.* directly)
  # because destroy-time provisioners and their connection blocks may only
  # reference the resource's own attributes via `self` - not arbitrary variables.
  triggers_replace = {
    fs_name              = var.fs_name
    pve_node             = var.pve_nodes[0]
    lan_domain           = var.lan_domain
    ssh_private_key_path = var.ssh_private_key_path
  }

  depends_on = [terraform_data.ceph_mds]

  connection {
    type        = "ssh"
    host        = "${self.triggers_replace.pve_node}.${self.triggers_replace.lan_domain}"
    user        = "root"
    private_key = file(self.triggers_replace.ssh_private_key_path)
  }

  provisioner "remote-exec" {
    # Idempotency guard - anchored on "name: <fs_name>," so fs_name="cephfs"
    # can't false-positive-match an existing "cephfs-test" entry (plain
    # substring grep would, since "cephfs" is a substring of "cephfs-test").
    inline = [
      "ceph fs ls | grep -q 'name: ${var.fs_name},' || pveceph fs create --name ${var.fs_name} --pg_num 32"
    ]
  }

  provisioner "remote-exec" {
    when = destroy
    # ceph fs fail is required first - pveceph fs destroy refuses ("all MDS
    # daemons must be inactive/failed") while the fs is still joinable.
    # --remove-pools is required for a real teardown - pveceph fs destroy alone
    # only disables/unlinks the filesystem and leaves the <fs_name>_data /
    # <fs_name>_metadata pools behind. --remove-storages is a no-op for us (we
    # never used --add-storage, so there's no pveceph-managed PVE storage entry
    # to remove) but harmless to keep for symmetry with the create step's intent.
    # Final grep assertion is required because pveceph fs destroy has been
    # observed to print an error and exit 0 (e.g. when ceph fs fail didn't
    # take effect in time) - without it Terraform would report a successful
    # destroy and drop the resource from state while the fs is still real.
    inline = [
      "ceph fs fail ${self.triggers_replace.fs_name} && pveceph fs destroy ${self.triggers_replace.fs_name} --remove-storages --remove-pools && ! ceph fs ls | grep -q 'name: ${self.triggers_replace.fs_name},'"
    ]
  }

  lifecycle {
    # Testing is done and this is pointed at the real "cephfs" (see README -
    # Testing vs. production) - any plan that would destroy this resource now
    # hard-errors instead of running the destroy-time provisioner above.
    prevent_destroy = true
  }
}
