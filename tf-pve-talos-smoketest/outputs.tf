output "kubeconfig" {
  value       = talos_cluster_kubeconfig.this.kubeconfig_raw
  description = "kubeconfig for the smoketest cluster - write to a file and `kubectl --kubeconfig=<file> get nodes` to confirm it's actually working"
  sensitive   = true
}

output "node_ip" {
  value       = "172.16.0.250"
  description = "Static IP the control-plane node was configured with"
}
