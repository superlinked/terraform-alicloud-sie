locals {
  names = {
    vpc              = "${var.cluster_name}-vpc"
    nat_gateway      = "${var.cluster_name}-nat"
    nat_eip          = "${var.cluster_name}-nat-eip"
    system_pool      = "${var.cluster_name}-system"
    system_node_role = "${substr(var.cluster_name, 0, 44)}-system-node"
    workload_role    = "${substr(var.cluster_name, 0, 48)}-workload"
    workload_policy  = "${substr(var.cluster_name, 0, 46)}-oss-access"
    bastion          = "${substr(var.cluster_name, 0, 47)}-bastion"
    bastion_eip      = "${substr(var.cluster_name, 0, 43)}-bastion-eip"
    bastion_sg       = "${substr(var.cluster_name, 0, 46)}-bastion-sg"
    acr_namespace    = var.acr_namespace
  }

  # Keep the human-readable cluster/pool prefixes while hashing the complete
  # pair. Without the hash, distinct long names with shared truncated prefixes
  # could produce the same account-global RAM role name.
  gpu_node_role_names = {
    for pool in var.gpu_node_pools : pool.name => "${substr(var.cluster_name, 0, 24)}-${substr(pool.name, 0, 16)}-${substr(sha256("${var.cluster_name}/${pool.name}"), 0, 16)}-node"
  }

  model_cache_bucket_name = var.model_cache_bucket_name != null ? trimspace(var.model_cache_bucket_name) : "${substr(var.cluster_name, 0, 40)}-cache-${random_id.storage_suffix.hex}"
  audit_log_project_name  = var.audit_log_project_name != null ? trimspace(var.audit_log_project_name) : "${substr(var.cluster_name, 0, 40)}-audit-${random_id.storage_suffix.hex}"
}
