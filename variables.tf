variable "alicloud_region" {
  description = "Alibaba Cloud region for all resources."
  type        = string
  default     = "eu-central-1"

  validation {
    condition     = can(regex("^[a-z0-9]+(?:-[a-z0-9]+)+$", var.alicloud_region))
    error_message = "alicloud_region must be a valid Alibaba Cloud region ID such as eu-central-1."
  }
}

variable "zones" {
  description = "Availability zones used for the ACK control plane and node pools."
  type        = list(string)
  default     = ["eu-central-1a", "eu-central-1c"]

  validation {
    condition = (
      length(var.zones) >= 2
      && length(var.zones) == length(distinct(var.zones))
      && alltrue([for zone in var.zones : startswith(zone, var.alicloud_region)])
    )
    error_message = "zones must contain at least two unique zones in alicloud_region."
  }
}

variable "cluster_name" {
  description = "ACK cluster name and resource-name prefix. Limited to 56 characters so the composed system node-pool name remains within ACK's 63-character limit."
  type        = string
  default     = "sie-ack"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,54}[a-z0-9]$", var.cluster_name))
    error_message = "cluster_name must be 3-56 lowercase letters, digits, or hyphens, starting with a letter and ending with a letter or digit."
  }
}

variable "kubernetes_version" {
  description = "ACK Kubernetes version 1.32 or newer, required for managed ack-nvidia-device-plugin lifecycle. Null selects the current ACK default and does not opt into automatic upgrades."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition = var.kubernetes_version == null || try(
      can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+(?:-aliyun\\.[0-9]+)?$", var.kubernetes_version))
      && (
        tonumber(split(".", var.kubernetes_version)[0]) > 1
        || (
          tonumber(split(".", var.kubernetes_version)[0]) == 1
          && tonumber(split(".", var.kubernetes_version)[1]) >= 32
        )
      ),
      false,
    )
    error_message = "kubernetes_version must be null or an ACK version at Kubernetes 1.32 or newer, such as 1.35.7-aliyun.1."
  }
}

variable "deletion_protection" {
  description = "Enable ACK cluster deletion protection. Disable only for intentionally ephemeral clusters."
  type        = bool
  default     = true
}

variable "vpc_cidr" {
  description = "IPv4 CIDR for the VPC."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition = try(
      can(cidrhost(var.vpc_cidr, 0))
      && length(split(".", cidrhost(var.vpc_cidr, 0))) == 4
      && split("/", var.vpc_cidr)[0] == cidrhost(var.vpc_cidr, 0)
      && tonumber(split("/", var.vpc_cidr)[1]) >= 8
      && tonumber(split("/", var.vpc_cidr)[1]) <= 24
      && (
        split(".", cidrhost(var.vpc_cidr, 0))[0] == "10"
        || (split(".", cidrhost(var.vpc_cidr, 0))[0] == "172" && tonumber(split(".", cidrhost(var.vpc_cidr, 0))[1]) >= 16 && tonumber(split(".", cidrhost(var.vpc_cidr, 0))[1]) <= 31)
        || (split(".", cidrhost(var.vpc_cidr, 0))[0] == "192" && split(".", cidrhost(var.vpc_cidr, 0))[1] == "168")
      ),
      false,
    )
    error_message = "vpc_cidr must be a canonical private RFC1918 IPv4 network with a /8 through /24 prefix."
  }
}

variable "system_vswitch_cidrs" {
  description = "One IPv4 CIDR per zone for ACK control-plane and system-node vSwitches."
  type        = list(string)
  default     = ["10.0.0.0/20", "10.0.16.0/20"]

  validation {
    condition = (
      length(var.system_vswitch_cidrs) == length(var.zones)
      && alltrue([
        for cidr in var.system_vswitch_cidrs : try(
          can(cidrhost(cidr, 0))
          && length(split(".", cidrhost(cidr, 0))) == 4
          && split("/", cidr)[0] == cidrhost(cidr, 0)
          && tonumber(split("/", cidr)[1]) >= 16
          && tonumber(split("/", cidr)[1]) <= 29
          && (
            split(".", cidrhost(cidr, 0))[0] == "10"
            || (split(".", cidrhost(cidr, 0))[0] == "172" && tonumber(split(".", cidrhost(cidr, 0))[1]) >= 16 && tonumber(split(".", cidrhost(cidr, 0))[1]) <= 31)
            || (split(".", cidrhost(cidr, 0))[0] == "192" && split(".", cidrhost(cidr, 0))[1] == "168")
          ),
          false,
        )
      ])
    )
    error_message = "system_vswitch_cidrs must contain one canonical private RFC1918 IPv4 /16 through /29 network per zone."
  }
}

variable "gpu_vswitch_cidrs" {
  description = "One IPv4 CIDR per zone for GPU-node vSwitches."
  type        = list(string)
  default     = ["10.0.32.0/20", "10.0.48.0/20"]

  validation {
    condition = (
      length(var.gpu_vswitch_cidrs) == length(var.zones)
      && alltrue([
        for cidr in var.gpu_vswitch_cidrs : try(
          can(cidrhost(cidr, 0))
          && length(split(".", cidrhost(cidr, 0))) == 4
          && split("/", cidr)[0] == cidrhost(cidr, 0)
          && tonumber(split("/", cidr)[1]) >= 16
          && tonumber(split("/", cidr)[1]) <= 29
          && (
            split(".", cidrhost(cidr, 0))[0] == "10"
            || (split(".", cidrhost(cidr, 0))[0] == "172" && tonumber(split(".", cidrhost(cidr, 0))[1]) >= 16 && tonumber(split(".", cidrhost(cidr, 0))[1]) <= 31)
            || (split(".", cidrhost(cidr, 0))[0] == "192" && split(".", cidrhost(cidr, 0))[1] == "168")
          ),
          false,
        )
      ])
    )
    error_message = "gpu_vswitch_cidrs must contain one canonical private RFC1918 IPv4 /16 through /29 network per zone."
  }
}

variable "pod_cidr" {
  description = "Flannel pod IPv4 CIDR. It must not overlap the VPC, vSwitch, or service CIDRs."
  type        = string
  default     = "10.1.0.0/16"

  validation {
    condition = try(
      can(cidrhost(var.pod_cidr, 0))
      && length(split(".", cidrhost(var.pod_cidr, 0))) == 4
      && split("/", var.pod_cidr)[0] == cidrhost(var.pod_cidr, 0)
      && tonumber(split("/", var.pod_cidr)[1]) >= 16
      && tonumber(split("/", var.pod_cidr)[1]) <= 24
      && (
        split(".", cidrhost(var.pod_cidr, 0))[0] == "10"
        || (
          split(".", cidrhost(var.pod_cidr, 0))[0] == "172"
          && tonumber(split(".", cidrhost(var.pod_cidr, 0))[1]) >= 16
          && tonumber(split(".", cidrhost(var.pod_cidr, 0))[1]) <= 31
        )
        || (
          split(".", cidrhost(var.pod_cidr, 0))[0] == "192"
          && split(".", cidrhost(var.pod_cidr, 0))[1] == "168"
        )
      ),
      false,
    )
    error_message = "pod_cidr must be a canonical private RFC1918 IPv4 network with a /16 through /24 prefix."
  }
}

variable "service_cidr" {
  description = "Kubernetes service IPv4 CIDR. It must not overlap the VPC, vSwitch, or pod CIDRs."
  type        = string
  default     = "172.20.0.0/16"

  validation {
    condition = try(
      can(cidrhost(var.service_cidr, 0))
      && length(split(".", cidrhost(var.service_cidr, 0))) == 4
      && split("/", var.service_cidr)[0] == cidrhost(var.service_cidr, 0)
      && tonumber(split("/", var.service_cidr)[1]) >= 16
      && tonumber(split("/", var.service_cidr)[1]) <= 24
      && (
        split(".", cidrhost(var.service_cidr, 0))[0] == "10"
        || (
          split(".", cidrhost(var.service_cidr, 0))[0] == "172"
          && tonumber(split(".", cidrhost(var.service_cidr, 0))[1]) >= 16
          && tonumber(split(".", cidrhost(var.service_cidr, 0))[1]) <= 31
        )
        || (
          split(".", cidrhost(var.service_cidr, 0))[0] == "192"
          && split(".", cidrhost(var.service_cidr, 0))[1] == "168"
        )
      ),
      false,
    )
    error_message = "service_cidr must be a canonical private RFC1918 IPv4 network with a /16 through /24 prefix."
  }
}

variable "nat_eip_bandwidth_mbps" {
  description = "Maximum bandwidth in Mbit/s for the pay-as-you-go NAT EIP."
  type        = number
  default     = 100

  validation {
    condition     = floor(var.nat_eip_bandwidth_mbps) == var.nat_eip_bandwidth_mbps && var.nat_eip_bandwidth_mbps >= 1 && var.nat_eip_bandwidth_mbps <= 200
    error_message = "nat_eip_bandwidth_mbps must be an integer from 1 through 200."
  }
}

variable "ecs_key_name" {
  description = "Optional existing ECS key-pair name for node access. Null leaves node SSH access unconfigured."
  type        = string
  default     = null
  nullable    = true
}

variable "system_node_ram_role_name" {
  description = "Optional existing ECS-trusted RAM role for the system node pool. Null creates a dedicated empty least-privilege role."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.system_node_ram_role_name == null || try(can(regex("^[A-Za-z0-9.@_-]{1,64}$", var.system_node_ram_role_name)), false)
    error_message = "system_node_ram_role_name must be null or a valid 1-64 character RAM role name."
  }
}

variable "system_node_pool" {
  description = "ACK system node-pool configuration."
  type = object({
    instance_types   = optional(list(string), ["ecs.g7.xlarge"])
    image_type       = optional(string, "AliyunLinux3ContainerOptimized")
    min_size         = optional(number, 1)
    max_size         = optional(number, 5)
    system_disk_size = optional(number, 100)
  })
  default = {}

  validation {
    condition = (
      length(var.system_node_pool.instance_types) > 0
      && contains(["AliyunLinux3ContainerOptimized"], var.system_node_pool.image_type)
      && floor(var.system_node_pool.min_size) == var.system_node_pool.min_size
      && floor(var.system_node_pool.max_size) == var.system_node_pool.max_size
      && floor(var.system_node_pool.system_disk_size) == var.system_node_pool.system_disk_size
      && var.system_node_pool.min_size >= 1
      && var.system_node_pool.max_size > var.system_node_pool.min_size
      && var.system_node_pool.system_disk_size >= 40
    )
    error_message = "system_node_pool requires at least one instance type, the supported cgroup-v2 image_type AliyunLinux3ContainerOptimized, integral min_size >= 1, max_size > min_size, and system_disk_size >= 40."
  }
}

variable "gpu_node_pools" {
  description = "ACK GPU node pools. Defaults to an on-demand A10 24 GiB pool that scales from zero."
  type = list(object({
    name                                = string
    instance_types                      = optional(list(string), ["ecs.gn7i-c8g1.2xlarge"])
    image_type                          = optional(string, "AliyunLinux3ContainerOptimized")
    gpu_type                            = optional(string, "a10")
    min_size                            = optional(number, 0)
    max_size                            = optional(number, 10)
    system_disk_size                    = optional(number, 500)
    spot                                = optional(bool, false)
    compensate_with_on_demand           = optional(bool, true)
    on_demand_base_capacity             = optional(number, 0)
    on_demand_percentage_above_capacity = optional(number, 0)
    ram_role_name                       = optional(string)
    labels                              = optional(map(string), {})
  }))
  default = [{ name = "a10" }]

  validation {
    condition     = length(var.gpu_node_pools) == length(distinct([for pool in var.gpu_node_pools : pool.name]))
    error_message = "gpu_node_pools names must be unique."
  }

  validation {
    condition = alltrue([
      for pool in var.gpu_node_pools : (
        can(regex("^[a-z](?:[a-z0-9-]{0,30}[a-z0-9])?$", pool.name))
        && length("${var.cluster_name}-${pool.name}") <= 63
        && length(pool.instance_types) > 0
        && contains(["AliyunLinux3ContainerOptimized"], pool.image_type)
        && floor(pool.min_size) == pool.min_size
        && floor(pool.max_size) == pool.max_size
        && floor(pool.system_disk_size) == pool.system_disk_size
        && floor(pool.on_demand_base_capacity) == pool.on_demand_base_capacity
        && floor(pool.on_demand_percentage_above_capacity) == pool.on_demand_percentage_above_capacity
        && pool.min_size >= 0
        && pool.max_size > pool.min_size
        && pool.system_disk_size >= 40
        && (!pool.spot || pool.compensate_with_on_demand)
        && pool.on_demand_base_capacity >= 0
        && pool.on_demand_percentage_above_capacity >= 0
        && pool.on_demand_percentage_above_capacity <= 100
        && (pool.ram_role_name == null || try(can(regex("^[A-Za-z0-9.@_-]{1,64}$", pool.ram_role_name)), false))
      )
    ])
    error_message = "Each GPU pool needs a valid name and optional RAM role, an instance type, the supported cgroup-v2 image_type AliyunLinux3ContainerOptimized, integral max_size > min_size >= 0, an integral disk >= 40 GiB, integral spot capacity percentages, and spot pools must enable on-demand compensation."
  }
}

variable "autoscaling_config" {
  description = "ACK cluster-autoscaler tuning."
  type = object({
    cool_down_duration            = optional(string, "10m")
    unneeded_duration             = optional(string, "10m")
    utilization_threshold         = optional(string, "0.5")
    gpu_utilization_threshold     = optional(string, "0.5")
    scan_interval                 = optional(string, "30s")
    skip_nodes_with_system_pods   = optional(bool, true)
    skip_nodes_with_local_storage = optional(bool, false)
  })
  default = {}
}

variable "sie_namespace" {
  description = "Kubernetes namespace bound into the ACK RRSA workload-role trust policy."
  type        = string
  default     = "sie"

  validation {
    condition     = can(regex("^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$", var.sie_namespace))
    error_message = "sie_namespace must be a valid lowercase Kubernetes DNS label."
  }
}

variable "sie_service_account_name" {
  description = "Kubernetes ServiceAccount bound into the ACK RRSA workload-role trust policy."
  type        = string
  default     = "sie-server"

  validation {
    condition     = can(regex("^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$", var.sie_service_account_name))
    error_message = "sie_service_account_name must be a valid lowercase Kubernetes DNS label."
  }
}

variable "create_model_cache" {
  description = "Create the shared OSS model-cache and payload-store bucket."
  type        = bool
  default     = true
}

variable "model_cache_bucket_name" {
  description = "Optional globally unique OSS bucket name. Null derives a bounded random-suffixed name."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition = var.model_cache_bucket_name == null || try(
      can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", trimspace(var.model_cache_bucket_name)))
      && !can(regex("^[0-9]+(?:\\.[0-9]+){3}$", trimspace(var.model_cache_bucket_name))),
      false,
    )
    error_message = "model_cache_bucket_name must be null or a valid 3-63 character lowercase OSS bucket name, not an IPv4 address."
  }
}

variable "model_cache_force_destroy" {
  description = "Delete all OSS object versions when destroying the bucket. Enable only for an explicitly ephemeral cluster with deletion protection disabled."
  type        = bool
  default     = false
}

variable "model_cache_versioning_enabled" {
  description = "Enable versioning on the shared OSS bucket."
  type        = bool
  default     = true
}

variable "payload_expiration_days" {
  description = "Days before current and noncurrent payload objects are removed by OSS lifecycle."
  type        = number
  default     = 1

  validation {
    condition     = floor(var.payload_expiration_days) == var.payload_expiration_days && var.payload_expiration_days >= 1 && var.payload_expiration_days <= 30
    error_message = "payload_expiration_days must be an integer from 1 through 30."
  }
}

variable "incomplete_multipart_expiration_days" {
  description = "Days before incomplete OSS multipart uploads are aborted."
  type        = number
  default     = 7

  validation {
    condition     = floor(var.incomplete_multipart_expiration_days) == var.incomplete_multipart_expiration_days && var.incomplete_multipart_expiration_days >= 1 && var.incomplete_multipart_expiration_days <= 30
    error_message = "incomplete_multipart_expiration_days must be an integer from 1 through 30."
  }
}

variable "ack_secret_encryption_enabled" {
  description = "Encrypt Kubernetes Secrets in the ACK control plane with KMS."
  type        = bool
  default     = true
}

variable "create_ack_secret_kms_key" {
  description = "Create a same-region Aliyun_AES_256 KMS key for ACK Secret envelope encryption. Set false only with ack_secret_kms_key_id."
  type        = bool
  default     = true
}

variable "ack_secret_kms_key_id" {
  description = "Existing same-region KMS key ID for ACK Secret encryption when create_ack_secret_kms_key=false."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.ack_secret_kms_key_id == null || try(trimspace(var.ack_secret_kms_key_id) != "", false)
    error_message = "ack_secret_kms_key_id must be null or a non-empty KMS key ID."
  }
}

variable "ack_secret_kms_automatic_rotation_enabled" {
  description = "Enable automatic rotation for a module-created ACK Secret key. Disabling rotation preserves envelope encryption but requires the key rotation policy to be managed separately."
  type        = bool
  default     = true
}

variable "ack_secret_kms_default_rotation_entitled" {
  description = "Set true only when the paid Default Key Rotation entitlement is already active in this account and region. The module does not purchase or renew the entitlement."
  type        = bool
  default     = false
}

variable "ack_secret_kms_instance_id" {
  description = "Optional existing software KMS instance ID for a module-created ACK Secret key. Null uses the account/region default-key path and requires the separate rotation entitlement when rotation is enabled."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.ack_secret_kms_instance_id == null || try(trimspace(var.ack_secret_kms_instance_id) != "", false)
    error_message = "ack_secret_kms_instance_id must be null or a non-empty existing KMS instance ID."
  }
}

variable "ack_secret_kms_rotation_interval_days" {
  description = "Automatic-rotation interval in days for a module-created KMS instance key. The default-key entitlement path is fixed at 365 days."
  type        = number
  default     = 365

  validation {
    condition     = floor(var.ack_secret_kms_rotation_interval_days) == var.ack_secret_kms_rotation_interval_days && var.ack_secret_kms_rotation_interval_days >= 7 && var.ack_secret_kms_rotation_interval_days <= 365
    error_message = "ack_secret_kms_rotation_interval_days must be an integer from 7 through 365."
  }
}

variable "ack_secret_kms_deletion_protection" {
  description = "Enable deletion protection on a module-created ACK Secret KMS key. Disable only for an ephemeral run after cluster deletion protection is disabled."
  type        = bool
  default     = true
}

variable "ack_secret_kms_pending_window_days" {
  description = "Pending-deletion window for a module-created ACK Secret KMS key."
  type        = number
  default     = 30

  validation {
    condition     = floor(var.ack_secret_kms_pending_window_days) == var.ack_secret_kms_pending_window_days && var.ack_secret_kms_pending_window_days >= 7 && var.ack_secret_kms_pending_window_days <= 30
    error_message = "ack_secret_kms_pending_window_days must be an integer from 7 through 30."
  }
}

variable "audit_logging_enabled" {
  description = "Send ACK API audit and control-plane component logs to a Terraform-owned SLS project."
  type        = bool
  default     = true
}

variable "audit_log_project_name" {
  description = "Optional globally unique SLS project name. Null derives a bounded random-suffixed name."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.audit_log_project_name == null || try(can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", trimspace(var.audit_log_project_name))), false)
    error_message = "audit_log_project_name must be null or a valid 3-63 character lowercase SLS project name."
  }
}

variable "audit_log_retention_days" {
  description = "Retention in days for ACK Pro control-plane component logs."
  type        = number
  default     = 30

  validation {
    condition     = floor(var.audit_log_retention_days) == var.audit_log_retention_days && var.audit_log_retention_days >= 1 && var.audit_log_retention_days <= 3650
    error_message = "audit_log_retention_days must be an integer from 1 through 3650."
  }
}

variable "bastion_enabled" {
  description = "Create an ephemeral public SSH bastion for SOCKS access to the private ACK API."
  type        = bool
  default     = false
}

variable "bastion_allowed_ssh_cidr" {
  description = "Exact canonical globally routable operator IPv4 /32 allowed to SSH to the bastion. Required when bastion_enabled=true."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition = var.bastion_allowed_ssh_cidr == null || try(
      can(cidrhost(var.bastion_allowed_ssh_cidr, 0))
      && length(split(".", cidrhost(var.bastion_allowed_ssh_cidr, 0))) == 4
      && tonumber(split("/", var.bastion_allowed_ssh_cidr)[1]) == 32
      && split("/", var.bastion_allowed_ssh_cidr)[0] == cidrhost(var.bastion_allowed_ssh_cidr, 0)
      && tonumber(split(".", cidrhost(var.bastion_allowed_ssh_cidr, 0))[0]) > 0
      && tonumber(split(".", cidrhost(var.bastion_allowed_ssh_cidr, 0))[0]) < 224
      && !contains(["10", "127"], split(".", cidrhost(var.bastion_allowed_ssh_cidr, 0))[0])
      && !(split(".", cidrhost(var.bastion_allowed_ssh_cidr, 0))[0] == "172" && tonumber(split(".", cidrhost(var.bastion_allowed_ssh_cidr, 0))[1]) >= 16 && tonumber(split(".", cidrhost(var.bastion_allowed_ssh_cidr, 0))[1]) <= 31)
      && !(split(".", cidrhost(var.bastion_allowed_ssh_cidr, 0))[0] == "169" && split(".", cidrhost(var.bastion_allowed_ssh_cidr, 0))[1] == "254")
      && !(split(".", cidrhost(var.bastion_allowed_ssh_cidr, 0))[0] == "100" && tonumber(split(".", cidrhost(var.bastion_allowed_ssh_cidr, 0))[1]) >= 64 && tonumber(split(".", cidrhost(var.bastion_allowed_ssh_cidr, 0))[1]) <= 127)
      && !(
        split(".", cidrhost(var.bastion_allowed_ssh_cidr, 0))[0] == "192"
        && (
          split(".", cidrhost(var.bastion_allowed_ssh_cidr, 0))[1] == "168"
          || (split(".", cidrhost(var.bastion_allowed_ssh_cidr, 0))[1] == "0" && contains(["0", "2"], split(".", cidrhost(var.bastion_allowed_ssh_cidr, 0))[2]))
          || (split(".", cidrhost(var.bastion_allowed_ssh_cidr, 0))[1] == "31" && split(".", cidrhost(var.bastion_allowed_ssh_cidr, 0))[2] == "196")
          || (split(".", cidrhost(var.bastion_allowed_ssh_cidr, 0))[1] == "52" && split(".", cidrhost(var.bastion_allowed_ssh_cidr, 0))[2] == "193")
          || (split(".", cidrhost(var.bastion_allowed_ssh_cidr, 0))[1] == "88" && split(".", cidrhost(var.bastion_allowed_ssh_cidr, 0))[2] == "99")
          || (split(".", cidrhost(var.bastion_allowed_ssh_cidr, 0))[1] == "175" && split(".", cidrhost(var.bastion_allowed_ssh_cidr, 0))[2] == "48")
        )
      )
      && !(
        split(".", cidrhost(var.bastion_allowed_ssh_cidr, 0))[0] == "198"
        && (
          contains(["18", "19"], split(".", cidrhost(var.bastion_allowed_ssh_cidr, 0))[1])
          || (split(".", cidrhost(var.bastion_allowed_ssh_cidr, 0))[1] == "51" && split(".", cidrhost(var.bastion_allowed_ssh_cidr, 0))[2] == "100")
        )
      )
      && !(split(".", cidrhost(var.bastion_allowed_ssh_cidr, 0))[0] == "203" && split(".", cidrhost(var.bastion_allowed_ssh_cidr, 0))[1] == "0" && split(".", cidrhost(var.bastion_allowed_ssh_cidr, 0))[2] == "113"),
      false,
    )
    error_message = "bastion_allowed_ssh_cidr must be null or one canonical globally routable unicast IPv4 /32; private and IANA special-use ranges are rejected."
  }
}

variable "bastion_instance_type" {
  description = "ECS instance type for the optional bastion."
  type        = string
  default     = "ecs.g7.large"

  validation {
    condition     = can(regex("^ecs\\.[A-Za-z0-9.-]+$", var.bastion_instance_type))
    error_message = "bastion_instance_type must be one ECS instance type identifier."
  }
}

variable "bastion_image_id" {
  description = "Optional explicit Linux ECS image ID. Null selects the newest supported Aliyun Linux 3 image for the bastion instance type."
  type        = string
  default     = null
  nullable    = true
}

variable "bastion_system_disk_size_gb" {
  description = "Encrypted system disk size for the optional bastion."
  type        = number
  default     = 40

  validation {
    condition     = floor(var.bastion_system_disk_size_gb) == var.bastion_system_disk_size_gb && var.bastion_system_disk_size_gb >= 20 && var.bastion_system_disk_size_gb <= 500
    error_message = "bastion_system_disk_size_gb must be an integer from 20 through 500."
  }
}

variable "bastion_eip_bandwidth_mbps" {
  description = "Maximum pay-by-traffic EIP bandwidth for the optional bastion."
  type        = number
  default     = 5

  validation {
    condition     = floor(var.bastion_eip_bandwidth_mbps) == var.bastion_eip_bandwidth_mbps && var.bastion_eip_bandwidth_mbps >= 1 && var.bastion_eip_bandwidth_mbps <= 100
    error_message = "bastion_eip_bandwidth_mbps must be an integer from 1 through 100."
  }
}

variable "enable_acr_repositories" {
  description = "Create private repositories in an existing ACR Enterprise Edition instance. This never creates an ACR subscription."
  type        = bool
  default     = false

  validation {
    condition = (
      !var.enable_acr_repositories
      || (
        try(trimspace(var.acr_enterprise_instance_id) != "", false)
        && try(trimspace(var.acr_registry_domain) != "", false)
      )
    )
    error_message = "enable_acr_repositories requires acr_enterprise_instance_id and acr_registry_domain for an existing ACR Enterprise Edition instance."
  }
}

variable "acr_enterprise_instance_id" {
  description = "Existing ACR Enterprise Edition instance ID. Required only when enable_acr_repositories is true."
  type        = string
  default     = null
  nullable    = true
}

variable "acr_registry_domain" {
  description = "Existing ACR Enterprise registry bare hostname without a scheme, port, path, or trailing slash. It is supplied by the caller so the module does not retrieve instance details or tokens."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition = var.acr_registry_domain == null || try(
      length(var.acr_registry_domain) <= 253
      && can(regex("^(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\\.)+[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$", var.acr_registry_domain)),
      false,
    )
    error_message = "acr_registry_domain must be null or a bare DNS hostname without a scheme, port, path, or trailing slash."
  }
}

variable "acr_namespace" {
  description = "Private namespace to create in the existing ACR Enterprise Edition instance."
  type        = string
  default     = "sie"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9_.-]{0,118}[a-z0-9]$", var.acr_namespace))
    error_message = "acr_namespace must be 2-120 lowercase letters, digits, underscores, periods, or hyphens and cannot start or end with a delimiter."
  }
}

variable "acr_repositories" {
  description = "Private repositories to create inside acr_namespace."
  type = map(object({
    summary          = string
    detail           = optional(string, "Managed by Terraform for SIE.")
    tag_immutability = optional(bool, false)
  }))
  default = {
    sie-server  = { summary = "SIE server images" }
    sie-gateway = { summary = "SIE gateway images" }
    sie-config  = { summary = "SIE config-service images" }
  }

  validation {
    condition = alltrue([
      for name, repository in var.acr_repositories : (
        can(regex("^[a-z0-9][a-z0-9_.-]*[a-z0-9]$", name))
        && length(name) <= 64
        && trimspace(repository.summary) != ""
      )
    ])
    error_message = "ACR repository names must be at most 64 lowercase letters, digits, underscores, periods, or hyphens, and summaries cannot be empty."
  }
}

variable "tags" {
  description = "Additional Alibaba Cloud tags. The module-owned project and sie-cluster tags take precedence."
  type        = map(string)
  default = {
    "managed-by" = "terraform"
    "app"        = "sie"
  }
}
