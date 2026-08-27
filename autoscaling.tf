resource "alicloud_cs_autoscaling_config" "main" {
  cluster_id                    = alicloud_cs_managed_kubernetes.main.id
  cool_down_duration            = var.autoscaling_config.cool_down_duration
  unneeded_duration             = var.autoscaling_config.unneeded_duration
  utilization_threshold         = var.autoscaling_config.utilization_threshold
  gpu_utilization_threshold     = var.autoscaling_config.gpu_utilization_threshold
  scan_interval                 = var.autoscaling_config.scan_interval
  scale_down_enabled            = true
  expander                      = "least-waste"
  skip_nodes_with_system_pods   = var.autoscaling_config.skip_nodes_with_system_pods
  skip_nodes_with_local_storage = var.autoscaling_config.skip_nodes_with_local_storage
  daemonset_eviction_for_nodes  = false
  max_graceful_termination_sec  = 14400
  min_replica_count             = 0
  recycle_node_deletion_enabled = false
  scale_up_from_zero            = true
  scaler_type                   = "cluster-autoscaler"

  depends_on = [
    alicloud_cs_kubernetes_node_pool.system,
    alicloud_cs_kubernetes_node_pool.gpu,
  ]
}
