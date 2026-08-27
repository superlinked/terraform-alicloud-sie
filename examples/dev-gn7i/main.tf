terraform {
  required_version = ">= 1.14"

  required_providers {
    alicloud = {
      source  = "aliyun/alicloud"
      version = "~> 1.289.0"
    }
  }
}

provider "alicloud" {
  region = var.alicloud_region

  sign_version {
    oss = "v4"
    sls = "v4"
  }
}

variable "alicloud_region" {
  description = "Alibaba Cloud region for the example cluster."
  type        = string
  default     = "eu-central-1"
}

variable "cluster_name" {
  description = "ACK cluster name."
  type        = string
  default     = "sie-dev-gn7i"
}

variable "ecs_key_name" {
  description = "Optional caller-owned ECS key-pair name for node access."
  type        = string
  default     = null
  nullable    = true
}

variable "system_node_ram_role_name" {
  description = "Optional caller-owned ECS-trusted RAM role name for the system node pool."
  type        = string
  default     = null
  nullable    = true
}

variable "system_node_image_type" {
  description = "ACK-resolved cgroup-v2 and IMDSv2 image family for the system node pool."
  type        = string
  default     = "AliyunLinux3ContainerOptimized"

  validation {
    condition     = contains(["AliyunLinux3ContainerOptimized"], var.system_node_image_type)
    error_message = "system_node_image_type must use the reviewed cgroup-v2 family AliyunLinux3ContainerOptimized."
  }
}

variable "gpu_node_image_type" {
  description = "ACK-resolved cgroup-v2 and IMDSv2 image family for the default A10 node pool."
  type        = string
  default     = "AliyunLinux3ContainerOptimized"

  validation {
    condition     = contains(["AliyunLinux3ContainerOptimized"], var.gpu_node_image_type)
    error_message = "gpu_node_image_type must use the reviewed cgroup-v2 family AliyunLinux3ContainerOptimized."
  }
}

variable "create_ack_secret_kms_key" {
  description = "Create the ACK Secret key in this module. Set false only when ack_secret_kms_key_id identifies a caller-owned rotating key."
  type        = bool
  default     = true
}

variable "ack_secret_kms_key_id" {
  description = "Optional caller-owned, same-region, enabled and automatically rotating Aliyun_AES_256 KMS key ID."
  type        = string
  default     = null
  nullable    = true
}

variable "ack_secret_kms_instance_id" {
  description = "Optional caller-owned software KMS instance ID for a module-created rotating key."
  type        = string
  default     = null
  nullable    = true
}

variable "ack_secret_kms_default_rotation_entitled" {
  description = "Attest that the paid regional Default Key Rotation entitlement is already effective. This example cannot purchase or renew it."
  type        = bool
  default     = false

  validation {
    condition = (
      var.create_ack_secret_kms_key
      ? (
        var.ack_secret_kms_key_id == null
        && ((var.ack_secret_kms_instance_id != null) != var.ack_secret_kms_default_rotation_entitled)
      )
      : (
        var.ack_secret_kms_key_id != null
        && var.ack_secret_kms_instance_id == null
        && !var.ack_secret_kms_default_rotation_entitled
      )
    )
    error_message = "Select exactly one KMS authority: an existing rotating key, a caller-owned software KMS instance, or an already-effective Default Key Rotation entitlement."
  }
}

variable "ack_secret_kms_rotation_interval_days" {
  description = "Integral 7-365 day interval for a software KMS instance key; the Default Key Rotation entitlement path is fixed at 365."
  type        = number
  default     = 365
}

variable "enable_acr_repositories" {
  description = "Create private repositories in a caller-owned ACR Enterprise Edition instance."
  type        = bool
  default     = false
}

variable "acr_enterprise_instance_id" {
  description = "Optional caller-owned ACR Enterprise Edition instance ID."
  type        = string
  default     = null
  nullable    = true
}

variable "acr_registry_domain" {
  description = "Optional caller-owned ACR Enterprise registry hostname without scheme, port, path, or trailing slash."
  type        = string
  default     = null
  nullable    = true
}

module "sie_ack" {
  source  = "superlinked/sie/alicloud"
  version = "0.7.2"

  alicloud_region           = var.alicloud_region
  cluster_name              = var.cluster_name
  ecs_key_name              = var.ecs_key_name
  system_node_ram_role_name = var.system_node_ram_role_name
  system_node_pool = {
    image_type = var.system_node_image_type
  }
  gpu_node_pools = [{
    name       = "a10"
    image_type = var.gpu_node_image_type
  }]
  create_ack_secret_kms_key                = var.create_ack_secret_kms_key
  ack_secret_kms_key_id                    = var.ack_secret_kms_key_id
  ack_secret_kms_instance_id               = var.ack_secret_kms_instance_id
  ack_secret_kms_default_rotation_entitled = var.ack_secret_kms_default_rotation_entitled
  ack_secret_kms_rotation_interval_days    = var.ack_secret_kms_rotation_interval_days
  enable_acr_repositories                  = var.enable_acr_repositories
  acr_enterprise_instance_id               = var.acr_enterprise_instance_id
  acr_registry_domain                      = var.acr_registry_domain
}

output "cluster_id" {
  description = "ACK cluster ID."
  value       = module.sie_ack.cluster_id
}

output "kubeconfig_command" {
  description = "Renewable Aliyun CLI kubeconfig retrieval command."
  value       = module.sie_ack.kubeconfig_command
}

output "model_cache_bucket_url" {
  description = "Native OSS model-cache URL for workers.common.clusterCache.url."
  value       = module.sie_ack.model_cache_bucket_url
}

output "payload_store_url" {
  description = "Native OSS payload-store URL for payloadStore.url."
  value       = module.sie_ack.payload_store_url
}

output "rrsa_workload_role_name" {
  description = "Role name for the ACK pod-identity ServiceAccount annotation."
  value       = module.sie_ack.rrsa_workload_role_name
}

output "gpu_node_pools" {
  description = "GPU node-pool identities and capacity facts."
  value       = module.sie_ack.gpu_node_pools
}

output "acr_repositories" {
  description = "Optional ACR repository IDs and caller-supplied endpoints."
  value       = module.sie_ack.acr_repositories
}
