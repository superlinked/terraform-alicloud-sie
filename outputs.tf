output "alicloud_region" {
  description = "Alibaba Cloud region containing the cluster."
  value       = var.alicloud_region
}

output "cluster_id" {
  description = "ACK cluster ID."
  value       = alicloud_cs_managed_kubernetes.main.id
}

output "cluster_name" {
  description = "ACK cluster name."
  value       = alicloud_cs_managed_kubernetes.main.name
}

output "api_server_endpoint" {
  description = "Sensitive private ACK API server endpoint. This module never creates a public endpoint."
  value       = try(alicloud_cs_managed_kubernetes.main.connections["api_server_intranet"], null)
  sensitive   = true
}

output "kubeconfig_command" {
  description = "Renewable Aliyun CLI command that retrieves kubeconfig when run; Terraform does not materialize kubeconfig credentials."
  value       = "aliyun cs DescribeClusterUserKubeconfig --ClusterId ${alicloud_cs_managed_kubernetes.main.id} --PrivateIpAddress true --TemporaryDurationMinutes 15 --region ${var.alicloud_region} | jq -er '.config'"
}

output "vpc_id" {
  description = "VPC ID."
  value       = alicloud_vpc.main.id
}

output "system_vswitch_ids" {
  description = "System vSwitch IDs keyed by availability zone."
  value       = { for zone, vswitch in alicloud_vswitch.system : zone => vswitch.id }
}

output "gpu_vswitch_ids" {
  description = "GPU vSwitch IDs keyed by availability zone."
  value       = { for zone, vswitch in alicloud_vswitch.gpu : zone => vswitch.id }
}

output "nat_gateway_id" {
  description = "Enhanced Internet NAT gateway ID."
  value       = alicloud_nat_gateway.main.id
}

output "nat_eip_address" {
  description = "Public EIP used for private-node egress."
  value       = alicloud_eip_address.nat.ip_address
}

output "system_node_pool" {
  description = "System node-pool identity and scaling bounds."
  value = {
    id               = alicloud_cs_kubernetes_node_pool.system.node_pool_id
    instance_types   = var.system_node_pool.instance_types
    image_type       = var.system_node_pool.image_type
    min_size         = var.system_node_pool.min_size
    max_size         = var.system_node_pool.max_size
    system_disk_size = var.system_node_pool.system_disk_size
    ram_role_name = (
      var.system_node_ram_role_name != null
      ? var.system_node_ram_role_name
      : alicloud_ram_role.system_node[0].role_name
    )
  }
}

output "gpu_node_pools" {
  description = "GPU node-pool identities, instance types, capacity bounds, and purchasing mode."
  value = {
    for name, pool in alicloud_cs_kubernetes_node_pool.gpu : name => {
      id               = pool.node_pool_id
      instance_types   = var.gpu_node_pools[index(var.gpu_node_pools[*].name, name)].instance_types
      image_type       = var.gpu_node_pools[index(var.gpu_node_pools[*].name, name)].image_type
      min_size         = var.gpu_node_pools[index(var.gpu_node_pools[*].name, name)].min_size
      max_size         = var.gpu_node_pools[index(var.gpu_node_pools[*].name, name)].max_size
      spot             = var.gpu_node_pools[index(var.gpu_node_pools[*].name, name)].spot
      system_disk_size = var.gpu_node_pools[index(var.gpu_node_pools[*].name, name)].system_disk_size
      ram_role_name = (
        var.gpu_node_pools[index(var.gpu_node_pools[*].name, name)].ram_role_name != null
        ? var.gpu_node_pools[index(var.gpu_node_pools[*].name, name)].ram_role_name
        : alicloud_ram_role.gpu_node[name].role_name
      )
    }
  }
}

output "acr_repositories" {
  description = "Optional ACR Enterprise repository IDs and caller-supplied endpoints. Empty when ACR repository creation is disabled."
  value = {
    for name, repository in alicloud_cr_ee_repo.sie : name => {
      id       = repository.repo_id
      endpoint = "${trimsuffix(coalesce(var.acr_registry_domain, "disabled.invalid"), "/")}/${var.acr_namespace}/${name}"
    }
  }
}

output "model_cache_bucket_name" {
  description = "Managed OSS bucket name for model cache and payloads (null when create_model_cache=false)."
  value       = try(alicloud_oss_bucket.model_cache[0].bucket, null)
}

output "model_cache_bucket_url" {
  description = "Native OSS model-cache URL with the /models prefix."
  value       = try("oss://${alicloud_oss_bucket.model_cache[0].bucket}/models", null)
}

output "payload_store_url" {
  description = "Native OSS payload-store URL with the /payloads prefix."
  value       = try("oss://${alicloud_oss_bucket.model_cache[0].bucket}/payloads", null)
}

output "oss_internal_endpoint" {
  description = "Private Alibaba OSS endpoint for same-region ACK workloads (null when create_model_cache=false)."
  value       = try(alicloud_oss_bucket.model_cache[0].intranet_endpoint, null)
}

output "rrsa_workload_role_name" {
  description = "RAM role name to inject into the Helm ServiceAccount annotation pod-identity.alibabacloud.com/role-name."
  value       = alicloud_ram_role.workload.role_name
}

output "rrsa_workload_role_arn" {
  description = "RRSA workload role ARN for audit and identity verification."
  value       = alicloud_ram_role.workload.arn
}

output "rrsa_oidc_provider_arn" {
  description = "ACK-managed RRSA OIDC provider ARN used by the exact workload trust policy."
  value       = local.rrsa_oidc_provider_arn
}

output "node_ram_role_names" {
  description = "Distinct ECS-trusted RAM role names for system and GPU node pools."
  value = {
    system = (
      var.system_node_ram_role_name != null
      ? var.system_node_ram_role_name
      : alicloud_ram_role.system_node[0].role_name
    )
    gpu = {
      for pool in var.gpu_node_pools : pool.name => (
        pool.ram_role_name != null
        ? pool.ram_role_name
        : alicloud_ram_role.gpu_node[pool.name].role_name
      )
    }
  }
}

output "ack_secret_encryption" {
  description = "ACK Secret envelope-encryption posture and KMS key authority; rotation_interval uses the provider-canonical seconds representation."
  value = {
    enabled             = var.ack_secret_encryption_enabled
    key_id              = local.ack_secret_kms_key_id
    module_created      = var.ack_secret_encryption_enabled && var.create_ack_secret_kms_key
    deletion_protection = var.create_ack_secret_kms_key ? var.ack_secret_kms_deletion_protection : null
    automatic_rotation  = var.ack_secret_encryption_enabled ? (var.create_ack_secret_kms_key ? var.ack_secret_kms_automatic_rotation_enabled : true) : null
    rotation_interval   = var.ack_secret_encryption_enabled ? (var.create_ack_secret_kms_key ? try(alicloud_kms_key.ack_secrets[0].rotation_interval, null) : try(data.alicloud_kms_keys.ack_secrets_existing[0].keys[0].rotation_interval, null)) : null
    kms_instance_id     = var.create_ack_secret_kms_key ? var.ack_secret_kms_instance_id : null
  }
}

output "audit_logging" {
  description = "ACK API audit and control-plane component logging posture."
  value = {
    enabled    = var.audit_logging_enabled
    project    = try(alicloud_log_project.ack[0].project_name, null)
    ttl_days   = var.audit_logging_enabled ? var.audit_log_retention_days : null
    components = var.audit_logging_enabled ? ["apiserver", "kcm", "scheduler", "ccm", "controlplane-events"] : []
  }
}

output "bastion_connection" {
  description = "Minimum connection facts for the optional SSH SOCKS bastion; null when disabled."
  value = var.bastion_enabled ? {
    public_ip = alicloud_eip_address.bastion[0].ip_address
    user      = "root"
    key_name  = var.ecs_key_name
  } : null
  sensitive = true
}
