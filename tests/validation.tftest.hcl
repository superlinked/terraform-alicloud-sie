mock_provider "alicloud" {
  mock_resource "alicloud_cs_managed_kubernetes" {
    defaults = {
      id   = "c-test"
      name = "sie-ack"
      rrsa_metadata = [{
        enabled                = true
        ram_oidc_provider_arn  = "acs:ram::000000000000:oidc-provider/ack-test"
        ram_oidc_provider_name = "ack-test"
        rrsa_oidc_issuer_url   = "https://oidc.example.invalid"
      }]
    }
    override_during = plan
  }

  mock_data "alicloud_images" {
    defaults = {
      images = [{
        id = "aliyun-linux-test"
      }]
    }
  }

  mock_data "alicloud_kms_keys" {
    defaults = { keys = [] }
  }
}

mock_provider "random" {
  mock_resource "random_id" {
    defaults = {
      hex = "cafebabe"
    }
  }
}

variables {
  ack_secret_kms_default_rotation_entitled = true
}

run "validate_frankfurt_defaults" {
  command = plan

  assert {
    condition     = var.alicloud_region == "eu-central-1"
    error_message = "The Alibaba Cloud region default must be Frankfurt."
  }

  assert {
    condition     = var.zones == tolist(["eu-central-1a", "eu-central-1c"])
    error_message = "The default Frankfurt zones must be eu-central-1a and eu-central-1c."
  }

  assert {
    condition = (
      alicloud_cs_kubernetes_node_pool.system.instance_types == tolist(["ecs.g7.xlarge"])
      && alicloud_cs_kubernetes_node_pool.system.image_type == "AliyunLinux3ContainerOptimized"
    )
    error_message = "The default system pool must use ecs.g7.xlarge and the reviewed cgroup-v2 ACK image family."
  }

  assert {
    condition = (
      alicloud_cs_kubernetes_node_pool.gpu["a10"].instance_types == tolist(["ecs.gn7i-c8g1.2xlarge"])
      && alicloud_cs_kubernetes_node_pool.gpu["a10"].image_type == "AliyunLinux3ContainerOptimized"
    )
    error_message = "The default GPU pool must use the Frankfurt A10 instance type and the reviewed cgroup-v2 ACK image family."
  }

  assert {
    condition = (
      alicloud_cs_kubernetes_node_pool.gpu["a10"].system_disk_size == 500
      && alicloud_cs_kubernetes_node_pool.gpu["a10"].system_disk_size > 300
    )
    error_message = "The default GPU system disk must be 500 GiB, leaving headroom above the chart's 300 GiB node cache."
  }
}

run "validate_private_node_egress" {
  command = plan

  assert {
    condition = (
      alicloud_nat_gateway.main.nat_type == "Enhanced"
      && alicloud_nat_gateway.main.network_type == "internet"
      && alicloud_nat_gateway.main.availability_mode == "CrossAZ"
    )
    error_message = "Private nodes must use an Enhanced Internet NAT gateway."
  }

  assert {
    condition     = alicloud_eip_association.nat.instance_type == "Nat"
    error_message = "The pay-as-you-go EIP must be associated with the NAT gateway."
  }

  assert {
    condition     = alicloud_eip_address.nat.bandwidth == "100"
    error_message = "The default NAT EIP bandwidth must be 100 Mbit/s."
  }

  assert {
    condition     = length(alicloud_snat_entry.system) == 2 && length(alicloud_snat_entry.gpu) == 2
    error_message = "Every system and GPU vSwitch must have an explicit SNAT entry."
  }
}

run "validate_private_kubeconfig_command" {
  command = plan

  assert {
    condition     = output.kubeconfig_command == "aliyun cs DescribeClusterUserKubeconfig --ClusterId c-test --PrivateIpAddress true --TemporaryDurationMinutes 15 --region eu-central-1 | jq -er '.config'"
    error_message = "The kubeconfig output must use the named Aliyun CLI operation with a 15-minute private credential."
  }
}

run "validate_ack_posture" {
  command = plan

  assert {
    condition = (
      alicloud_cs_managed_kubernetes.main.cluster_spec == "ack.pro.small"
      && alicloud_cs_managed_kubernetes.main.deletion_protection
      && !alicloud_cs_managed_kubernetes.main.slb_internet_enabled
      && !alicloud_cs_managed_kubernetes.main.new_nat_gateway
      && alicloud_cs_managed_kubernetes.main.enable_rrsa
      && !alicloud_cs_managed_kubernetes.main.disable_encryption
    )
    error_message = "ACK must default to Pro, deletion-protected, private API access, explicit NAT, RRSA, and Secret encryption."
  }

  assert {
    condition     = contains([for addon in alicloud_cs_managed_kubernetes.main.addons : addon.name], "flannel")
    error_message = "The ACK cluster must install Flannel."
  }

  assert {
    condition = alltrue([
      for addon in ["csi-plugin", "csi-provisioner"] :
      contains([for configured in alicloud_cs_managed_kubernetes.main.addons : configured.name], addon)
    ])
    error_message = "The ACK cluster must install the required CSI components."
  }

  assert {
    condition     = alicloud_cs_kubernetes_addon.nvidia_device_plugin.name == "ack-nvidia-device-plugin"
    error_message = "ACK must manage the NVIDIA device plugin add-on."
  }

  assert {
    condition = (
      alicloud_cs_kubernetes_addon.pod_identity_webhook.name == "ack-pod-identity-webhook"
      && !jsondecode(alicloud_cs_kubernetes_addon.pod_identity_webhook.config).AutoInjectSTSEnvVars
    )
    error_message = "ACK must manage the RRSA webhook without injecting an STS endpoint that the runtime rejects."
  }

  assert {
    condition = (
      alicloud_cs_managed_kubernetes.main.audit_log_config[0].enabled
      && alicloud_cs_managed_kubernetes.main.control_plane_log_components == tolist(["apiserver", "kcm", "scheduler", "ccm", "controlplane-events"])
      && alicloud_cs_managed_kubernetes.main.control_plane_log_ttl == "30"
    )
    error_message = "ACK must enable API audit and all required Pro control-plane component logs."
  }
}

run "validate_oss_storage_contract" {
  command = plan

  variables {
    model_cache_bucket_name = "sie-test-cache"
  }

  assert {
    condition = (
      alicloud_oss_bucket.model_cache[0].bucket == "sie-test-cache"
      && alicloud_oss_bucket_acl.model_cache[0].acl == "private"
      && alicloud_oss_bucket_public_access_block.model_cache[0].block_public_access
      && alicloud_oss_bucket_server_side_encryption.model_cache[0].sse_algorithm == "AES256"
      && alicloud_oss_bucket_versioning.model_cache[0].status == "Enabled"
      && !alicloud_oss_bucket.model_cache[0].force_destroy
    )
    error_message = "The managed OSS bucket must be private, public-blocked, AES-256 encrypted, versioned, and non-force-destroy by default."
  }

  assert {
    condition = (
      alicloud_oss_bucket.model_cache[0].lifecycle_rule[0].prefix == "payloads/"
      && one(alicloud_oss_bucket.model_cache[0].lifecycle_rule[0].expiration).days == 1
      && one(alicloud_oss_bucket.model_cache[0].lifecycle_rule[0].noncurrent_version_expiration).days == 1
      && one(alicloud_oss_bucket.model_cache[0].lifecycle_rule[1].expiration).expired_object_delete_marker
      && one(alicloud_oss_bucket.model_cache[0].lifecycle_rule[2].abort_multipart_upload).days == 7
    )
    error_message = "OSS lifecycle must clean current/noncurrent payloads after one day and incomplete multipart uploads after seven days."
  }

  assert {
    condition     = output.model_cache_bucket_url == "oss://sie-test-cache/models" && output.payload_store_url == "oss://sie-test-cache/payloads"
    error_message = "Terraform must expose native OSS URLs with exact models and payloads prefixes."
  }
}

run "validate_model_cache_can_be_disabled" {
  command = plan

  variables {
    create_model_cache = false
  }

  assert {
    condition = (
      length(alicloud_oss_bucket.model_cache) == 0
      && length(alicloud_ram_policy.workload_oss) == 0
      && output.model_cache_bucket_name == null
      && output.model_cache_bucket_url == null
      && output.payload_store_url == null
    )
    error_message = "Disabling the managed cache must remove OSS/policy resources and return null storage outputs."
  }
}

run "validate_rrsa_prefix_policy" {
  command = plan

  variables {
    model_cache_bucket_name = "sie-test-cache"
  }

  assert {
    condition = (
      jsondecode(alicloud_ram_role.workload.assume_role_policy_document).Statement[0].Condition.StringEquals["oidc:aud"] == "sts.aliyuncs.com"
      && jsondecode(alicloud_ram_role.workload.assume_role_policy_document).Statement[0].Condition.StringEquals["oidc:sub"] == "system:serviceaccount:sie:sie-server"
    )
    error_message = "The workload role trust must bind the ACK audience and exact namespace/ServiceAccount subject."
  }

  assert {
    condition = (
      !contains(flatten([for statement in jsondecode(alicloud_ram_policy.workload_oss[0].policy_document).Statement : statement.Action]), "oss:*")
      && contains(jsondecode(alicloud_ram_policy.workload_oss[0].policy_document).Statement[1].Action, "oss:GetObject")
      && !contains(jsondecode(alicloud_ram_policy.workload_oss[0].policy_document).Statement[1].Action, "oss:PutObject")
      && contains(jsondecode(alicloud_ram_policy.workload_oss[0].policy_document).Statement[2].Action, "oss:PutObject")
      && contains(jsondecode(alicloud_ram_policy.workload_oss[0].policy_document).Statement[2].Action, "oss:DeleteObject")
    )
    error_message = "The workload policy must keep models read-only, payloads read/write/delete, and contain no oss:* grant."
  }
}

run "validate_kms_and_logging_contract" {
  command = plan

  assert {
    condition = (
      alicloud_kms_key.ack_secrets[0].key_spec == join("_", ["Aliyun", "AES", "256"])
      && alicloud_kms_key.ack_secrets[0].automatic_rotation == "Enabled"
      && alicloud_kms_key.ack_secrets[0].rotation_interval == "31536000s"
      && alicloud_kms_key.ack_secrets[0].deletion_protection == "Enabled"
      && alicloud_kms_key.ack_secrets[0].pending_window_in_days == 30
      && output.ack_secret_encryption.automatic_rotation
      && output.ack_secret_encryption.rotation_interval == "31536000s"
      && !alicloud_cs_managed_kubernetes.main.disable_encryption
    )
    error_message = "ACK Secrets must use a protected, rotating Aliyun_AES_256 KMS key."
  }

  assert {
    condition     = length(alicloud_log_project.ack) == 1 && alicloud_cs_managed_kubernetes.main.audit_log_config[0].enabled
    error_message = "One Terraform-owned SLS project must receive ACK API audit logs."
  }
}

run "validate_existing_kms_key_authority" {
  command = plan

  variables {
    create_ack_secret_kms_key = false
    ack_secret_kms_key_id     = "kms-existing-test"
  }

  override_data {
    target = data.alicloud_kms_keys.ack_secrets_existing[0]
    values = {
      keys = [{
        id                 = "kms-existing-test"
        key_id             = "kms-existing-test"
        status             = "Enabled"
        key_spec           = "Aliyun_\u0041ES_256"
        key_usage          = "ENCRYPT/DECRYPT"
        automatic_rotation = "Enabled"
        rotation_interval  = "31536000s"
      }]
    }
  }

  assert {
    condition = (
      length(alicloud_kms_key.ack_secrets) == 0
      && length(data.alicloud_kms_keys.ack_secrets_existing) == 1
      && data.alicloud_kms_keys.ack_secrets_existing[0].ids == tolist(["kms-existing-test"])
      && output.ack_secret_encryption.key_id == "kms-existing-test"
      && output.ack_secret_encryption.automatic_rotation
      && output.ack_secret_encryption.rotation_interval == "31536000s"
      && !output.ack_secret_encryption.module_created
    )
    error_message = "An explicit existing rotating KMS key must be validated and replace, not accompany, module key creation."
  }
}

run "reject_rotating_default_key_without_entitlement" {
  command = plan

  variables {
    ack_secret_kms_default_rotation_entitled = false
  }

  expect_failures = [alicloud_kms_key.ack_secrets[0]]
}

run "validate_rotating_kms_instance_key" {
  command = plan

  variables {
    ack_secret_kms_default_rotation_entitled = false
    ack_secret_kms_instance_id               = "kms-instance-test"
    ack_secret_kms_rotation_interval_days    = 30
  }

  assert {
    condition = (
      alicloud_kms_key.ack_secrets[0].dkms_instance_id == "kms-instance-test"
      && alicloud_kms_key.ack_secrets[0].automatic_rotation == "Enabled"
      && alicloud_kms_key.ack_secrets[0].rotation_interval == "2592000s"
      && output.ack_secret_encryption.rotation_interval == "2592000s"
    )
    error_message = "An existing software KMS instance must support provider-managed rotation at a 7-365 day interval."
  }
}

run "validate_seven_day_kms_instance_rotation" {
  command = plan

  variables {
    ack_secret_kms_default_rotation_entitled = false
    ack_secret_kms_instance_id               = "kms-instance-test"
    ack_secret_kms_rotation_interval_days    = 7
  }

  assert {
    condition = (
      alicloud_kms_key.ack_secrets[0].rotation_interval == "604800s"
      && output.ack_secret_encryption.rotation_interval == "604800s"
    )
    error_message = "The minimum supported KMS rotation interval must serialize to provider-canonical seconds."
  }
}

run "reject_custom_default_key_rotation_interval" {
  command = plan

  variables {
    ack_secret_kms_default_rotation_entitled = true
    ack_secret_kms_rotation_interval_days    = 30
  }

  expect_failures = [alicloud_kms_key.ack_secrets[0]]
}

run "validate_explicit_nonparity_rotation_opt_out" {
  command = plan

  variables {
    ack_secret_kms_automatic_rotation_enabled = false
    ack_secret_kms_default_rotation_entitled  = false
  }

  assert {
    condition = (
      !var.ack_secret_kms_automatic_rotation_enabled
      && !output.ack_secret_encryption.automatic_rotation
      && output.ack_secret_encryption.rotation_interval == null
      && !alicloud_cs_managed_kubernetes.main.disable_encryption
    )
    error_message = "The explicit non-parity opt-out must disable only automatic rotation while retaining ACK Secret envelope encryption."
  }
}

run "reject_existing_disabled_kms_key" {
  command = plan

  variables {
    create_ack_secret_kms_key = false
    ack_secret_kms_key_id     = "kms-existing-test"
  }

  override_data {
    target = data.alicloud_kms_keys.ack_secrets_existing[0]
    values = {
      keys = [{
        key_id             = "kms-existing-test"
        status             = "Disabled"
        key_spec           = "Aliyun_\u0041ES_256"
        key_usage          = "ENCRYPT/DECRYPT"
        automatic_rotation = "Enabled"
      }]
    }
  }

  expect_failures = [data.alicloud_kms_keys.ack_secrets_existing[0]]
}

run "reject_existing_wrong_spec_kms_key" {
  command = plan

  variables {
    create_ack_secret_kms_key = false
    ack_secret_kms_key_id     = "kms-existing-test"
  }

  override_data {
    target = data.alicloud_kms_keys.ack_secrets_existing[0]
    values = {
      keys = [{
        key_id             = "kms-existing-test"
        status             = "Enabled"
        key_spec           = "RSA_2048"
        key_usage          = "ENCRYPT/DECRYPT"
        automatic_rotation = "Enabled"
      }]
    }
  }

  expect_failures = [data.alicloud_kms_keys.ack_secrets_existing[0]]
}

run "reject_existing_nonrotating_kms_key" {
  command = plan

  variables {
    create_ack_secret_kms_key = false
    ack_secret_kms_key_id     = "kms-existing-test"
  }

  override_data {
    target = data.alicloud_kms_keys.ack_secrets_existing[0]
    values = {
      keys = [{
        key_id             = "kms-existing-test"
        status             = "Enabled"
        key_spec           = "Aliyun_\u0041ES_256"
        key_usage          = "ENCRYPT/DECRYPT"
        automatic_rotation = "Disabled"
      }]
    }
  }

  expect_failures = [data.alicloud_kms_keys.ack_secrets_existing[0]]
}

run "reject_two_kms_key_authorities" {
  command = plan

  variables {
    create_ack_secret_kms_key = true
    ack_secret_kms_key_id     = "kms-existing-test"
  }

  expect_failures = [alicloud_cs_managed_kubernetes.main]
}

run "reject_existing_kms_mode_without_key_id" {
  command = plan

  variables {
    create_ack_secret_kms_key = false
    ack_secret_kms_key_id     = null
  }

  assert {
    condition     = length(data.alicloud_kms_keys.ack_secrets_existing) == 0
    error_message = "A missing existing key ID must not invoke the KMS key lookup with a null filter."
  }

  expect_failures = [alicloud_cs_managed_kubernetes.main]
}

run "validate_audit_logging_can_be_disabled" {
  command = plan

  variables {
    audit_logging_enabled = false
  }

  assert {
    condition = (
      length(alicloud_log_project.ack) == 0
      && length(alicloud_cs_managed_kubernetes.main.audit_log_config) == 0
      && length(alicloud_cs_managed_kubernetes.main.control_plane_log_components) == 0
    )
    error_message = "Disabling audit logging must remove the SLS project and ACK audit/component configuration."
  }
}

run "validate_explicit_current_kubernetes_version" {
  command = plan

  variables {
    kubernetes_version = "1.35.7-aliyun.1"
  }

  assert {
    condition     = alicloud_cs_managed_kubernetes.main.version == "1.35.7-aliyun.1"
    error_message = "A current explicit ACK Kubernetes version must pass through to the cluster."
  }
}

run "validate_future_major_kubernetes_version" {
  command = plan

  variables {
    kubernetes_version = "2.0.0"
  }

  assert {
    condition     = alicloud_cs_managed_kubernetes.main.version == "2.0.0"
    error_message = "The validation must not reject future Kubernetes major versions."
  }
}

run "reject_kubernetes_version_older_than_1_32" {
  command = plan

  variables {
    kubernetes_version = "1.31.9-aliyun.1"
  }

  expect_failures = [var.kubernetes_version]
}

run "reject_detected_public_api_connection" {
  command = plan

  override_resource {
    target = alicloud_cs_managed_kubernetes.main
    values = {
      connections = {
        api_server_internet = "https://public-api.example.com:6443"
      }
    }
    override_during = plan
  }

  expect_failures = [alicloud_cs_managed_kubernetes.main]
}

run "validate_gpu_scale_from_zero_and_scheduling" {
  command = plan

  assert {
    condition = (
      alicloud_cs_kubernetes_node_pool.gpu["a10"].scaling_config[0].enable
      && alicloud_cs_kubernetes_node_pool.gpu["a10"].scaling_config[0].min_size == 0
      && alicloud_cs_kubernetes_node_pool.gpu["a10"].scaling_config[0].max_size == 10
      && alicloud_cs_autoscaling_config.main.scale_up_from_zero
    )
    error_message = "The default GPU pool and ACK autoscaler must support scale-from-zero."
  }

  assert {
    condition = (
      contains([for label in alicloud_cs_kubernetes_node_pool.gpu["a10"].labels : "${label.key}=${label.value}"], "ack.node.gpu.schedule=default")
      &&
      contains([for label in alicloud_cs_kubernetes_node_pool.gpu["a10"].labels : "${label.key}=${label.value}"], "sie.superlinked.com/node-type=gpu")
      && contains([for label in alicloud_cs_kubernetes_node_pool.gpu["a10"].labels : "${label.key}=${label.value}"], "sie.superlinked.com/gpu-type=a10")
    )
    error_message = "GPU nodes must have the ACK and SIE scheduling labels."
  }

  assert {
    condition = (
      alicloud_cs_kubernetes_node_pool.gpu["a10"].taints[0].key == "nvidia.com/gpu"
      && alicloud_cs_kubernetes_node_pool.gpu["a10"].taints[0].value == "present"
      && alicloud_cs_kubernetes_node_pool.gpu["a10"].taints[0].effect == "NoSchedule"
    )
    error_message = "GPU nodes must carry the nvidia.com/gpu=present:NoSchedule taint."
  }
}

run "validate_worker_security_hardening" {
  command = plan

  variables {
    system_node_ram_role_name = "sie-system-nodes"
    gpu_node_pools = [{
      name          = "a10"
      ram_role_name = "sie-a10-nodes"
    }]
  }

  assert {
    condition = (
      alicloud_cs_kubernetes_node_pool.system.instance_metadata_options[0].http_tokens == "required"
      && alicloud_cs_kubernetes_node_pool.gpu["a10"].instance_metadata_options[0].http_tokens == "required"
    )
    error_message = "Both ACK node pools must require IMDSv2 session tokens."
  }

  assert {
    condition = (
      alicloud_cs_kubernetes_node_pool.system.system_disk_encrypted
      && alicloud_cs_kubernetes_node_pool.gpu["a10"].system_disk_encrypted
    )
    error_message = "Both ACK node pools must use provider-managed system-disk encryption."
  }

  assert {
    condition = (
      alicloud_cs_kubernetes_node_pool.system.ram_role_name == "sie-system-nodes"
      && alicloud_cs_kubernetes_node_pool.gpu["a10"].ram_role_name == "sie-a10-nodes"
    )
    error_message = "System and GPU node pools must accept distinct explicit RAM role overrides."
  }
}

run "validate_spot_compensation" {
  command = plan

  variables {
    gpu_node_pools = [{
      name                      = "a10-spot"
      spot                      = true
      compensate_with_on_demand = true
    }]
  }

  assert {
    condition = (
      alicloud_cs_kubernetes_node_pool.gpu["a10-spot"].spot_strategy == "SpotAsPriceGo"
      && alicloud_cs_kubernetes_node_pool.gpu["a10-spot"].multi_az_policy == "COST_OPTIMIZED"
      && alicloud_cs_kubernetes_node_pool.gpu["a10-spot"].compensate_with_on_demand
      && alicloud_cs_kubernetes_node_pool.gpu["a10-spot"].scaling_config[0].type == "spot"
    )
    error_message = "Spot GPU pools must use cost-optimized spot capacity with explicit on-demand compensation."
  }
}

run "reject_spot_without_compensation" {
  command = plan

  variables {
    gpu_node_pools = [{
      name                      = "a10-spot"
      spot                      = true
      compensate_with_on_demand = false
    }]
  }

  expect_failures = [var.gpu_node_pools]
}

run "reject_equal_system_pool_bounds" {
  command = plan

  variables {
    system_node_pool = {
      min_size = 2
      max_size = 2
    }
  }

  expect_failures = [var.system_node_pool]
}

run "reject_non_cgroup_v2_system_image_family" {
  command = plan

  variables {
    system_node_pool = {
      image_type = "AliyunLinux3"
    }
  }

  expect_failures = [var.system_node_pool]
}

run "reject_unreviewed_gpu_image_family" {
  command = plan

  variables {
    gpu_node_pools = [{
      name       = "a10"
      image_type = "ContainerOS"
    }]
  }

  expect_failures = [var.gpu_node_pools]
}

run "validate_existing_acr_opt_in" {
  command = plan

  variables {
    enable_acr_repositories    = true
    acr_enterprise_instance_id = "cri-test"
    acr_registry_domain        = "test-registry.eu-central-1.cr.aliyuncs.com"
  }

  assert {
    condition     = length(alicloud_cr_ee_namespace.sie) == 1 && alicloud_cr_ee_namespace.sie[0].default_visibility == "PRIVATE"
    error_message = "ACR opt-in must create one private namespace in the supplied existing instance."
  }

  assert {
    condition     = length(alicloud_cr_ee_repo.sie) == 3 && alltrue([for repository in alicloud_cr_ee_repo.sie : repository.repo_type == "PRIVATE"])
    error_message = "ACR opt-in must create only the configured private repositories."
  }
}

run "reject_acr_without_existing_instance" {
  command = plan

  variables {
    enable_acr_repositories = true
  }

  expect_failures = [var.enable_acr_repositories]
}

run "reject_acr_registry_domain_with_scheme_and_path" {
  command = plan

  variables {
    acr_registry_domain = "https://registry.example.com/v2/"
  }

  expect_failures = [var.acr_registry_domain]
}

run "reject_acr_repository_name_over_64_characters" {
  command = plan

  variables {
    acr_repositories = {
      (join("", [for _ in range(65) : "a"])) = {
        summary = "Name exceeds the ACR API limit"
      }
    }
  }

  expect_failures = [var.acr_repositories]
}

run "reject_overlapping_cluster_cidrs" {
  command = plan

  variables {
    # This slice is unused by the default vSwitches but still inside the VPC.
    pod_cidr = "10.0.64.0/20"
  }

  expect_failures = [alicloud_vpc.main]
}

run "reject_overlapping_pod_and_service_cidrs" {
  command = plan

  variables {
    service_cidr = "10.1.128.0/17"
  }

  expect_failures = [alicloud_vpc.main]
}

run "reject_cluster_name_too_long_for_system_pool" {
  command = plan

  variables {
    cluster_name = join("", [for _ in range(57) : "a"])
  }

  expect_failures = [var.cluster_name]
}

run "reject_composed_gpu_pool_name_too_long" {
  command = plan

  variables {
    cluster_name = join("", [for _ in range(56) : "a"])
    gpu_node_pools = [{
      name = "gpu-pool"
    }]
  }

  expect_failures = [var.gpu_node_pools]
}

run "reject_vswitch_prefix_outside_api_range" {
  command = plan

  variables {
    system_vswitch_cidrs = ["10.0.0.0/30", "10.0.16.0/20"]
  }

  expect_failures = [var.system_vswitch_cidrs]
}

run "reject_public_pod_cidr" {
  command = plan

  variables {
    pod_cidr = "100.64.0.0/16"
  }

  expect_failures = [var.pod_cidr]
}

run "reject_public_service_cidr" {
  command = plan

  variables {
    service_cidr = "100.64.0.0/16"
  }

  expect_failures = [var.service_cidr]
}

run "reject_service_prefix_outside_api_range" {
  command = plan

  variables {
    service_cidr = "172.20.0.0/25"
  }

  expect_failures = [var.service_cidr]
}

run "validate_module_created_node_roles_are_distinct" {
  command = plan

  assert {
    condition = (
      alicloud_cs_kubernetes_node_pool.system.ram_role_name == alicloud_ram_role.system_node[0].role_name
      && alicloud_cs_kubernetes_node_pool.gpu["a10"].ram_role_name == alicloud_ram_role.gpu_node["a10"].role_name
      && alicloud_cs_kubernetes_node_pool.system.ram_role_name != alicloud_cs_kubernetes_node_pool.gpu["a10"].ram_role_name
      && alicloud_cs_kubernetes_node_pool.system.ram_role_name != alicloud_ram_role.workload.role_name
    )
    error_message = "Default system, GPU, and RRSA workload roles must be distinct."
  }

  assert {
    condition = alltrue([
      for role in concat([alicloud_ram_role.system_node[0]], values(alicloud_ram_role.gpu_node)) :
      jsondecode(role.assume_role_policy_document).Statement[0].Principal.Service[0] == "ecs.aliyuncs.com"
    ])
    error_message = "Every module-created node role must trust ECS only."
  }
}

run "validate_long_shared_prefix_gpu_role_names_do_not_collide" {
  command = plan

  variables {
    cluster_name = "sie-shared-cluster-prefix"
    gpu_node_pools = [
      { name = "gpu-pool-shared-prefix-alpha" },
      { name = "gpu-pool-shared-prefix-bravo" },
    ]
  }

  assert {
    condition = (
      alicloud_ram_role.gpu_node["gpu-pool-shared-prefix-alpha"].role_name
      != alicloud_ram_role.gpu_node["gpu-pool-shared-prefix-bravo"].role_name
      && alltrue([
        for name, role in alicloud_ram_role.gpu_node : (
          role.role_name == "${substr(var.cluster_name, 0, 24)}-${substr(name, 0, 16)}-${substr(sha256("${var.cluster_name}/${name}"), 0, 16)}-node"
          && startswith(role.role_name, "${substr(var.cluster_name, 0, 24)}-${substr(name, 0, 16)}-")
          && length(role.role_name) <= 64
        )
      ])
    )
    error_message = "Module-created GPU role names must retain readable prefixes and use the full cluster/pool pair for a collision-resistant suffix within the 64-character RAM limit."
  }
}

run "validate_optional_bastion_contract" {
  command = plan

  variables {
    bastion_enabled          = true
    bastion_allowed_ssh_cidr = "8.8.8.8/32"
    ecs_key_name             = "existing-operator-key"
  }

  assert {
    condition = (
      length(alicloud_instance.bastion) == 1
      && alicloud_instance.bastion[0].system_disk_encrypted
      && alicloud_instance.bastion[0].http_tokens == "required"
      && alicloud_instance.bastion[0].http_put_response_hop_limit == 1
      && alicloud_instance.bastion[0].internet_max_bandwidth_out == 0
    )
    error_message = "The optional bastion must have an encrypted disk, IMDSv2-required posture, and no instance public bandwidth."
  }

  assert {
    condition = (
      alicloud_security_group_rule.bastion_ssh[0].port_range == "22/22"
      && alicloud_security_group_rule.bastion_ssh[0].nic_type == "intranet"
      && alicloud_security_group_rule.bastion_ssh[0].cidr_ip == "8.8.8.8/32"
      && alicloud_eip_association.bastion[0].instance_type == "EcsInstance"
    )
    error_message = "The VPC bastion must use an intranet security-group rule and expose only SSH from the exact operator /32 through a Terraform-owned EIP."
  }
}

run "reject_bastion_without_key" {
  command = plan

  variables {
    bastion_enabled          = true
    bastion_allowed_ssh_cidr = "8.8.8.8/32"
  }

  expect_failures = [alicloud_instance.bastion[0]]
}

run "reject_noncanonical_bastion_cidr" {
  command = plan

  variables {
    bastion_allowed_ssh_cidr = "8.8.8.0/24"
  }

  expect_failures = [var.bastion_allowed_ssh_cidr]
}

run "reject_nonpublic_bastion_cidr" {
  command = plan

  variables {
    bastion_allowed_ssh_cidr = "100.64.0.42/32"
  }

  expect_failures = [var.bastion_allowed_ssh_cidr]
}

run "reject_zero_network_bastion_cidr" {
  command = plan

  variables {
    bastion_allowed_ssh_cidr = "0.1.2.3/32"
  }

  expect_failures = [var.bastion_allowed_ssh_cidr]
}

run "reject_protocol_assignment_bastion_cidr" {
  command = plan

  variables {
    bastion_allowed_ssh_cidr = "192.0.0.42/32"
  }

  expect_failures = [var.bastion_allowed_ssh_cidr]
}

run "reject_test_net_one_bastion_cidr" {
  command = plan

  variables {
    bastion_allowed_ssh_cidr = "192.0.2.42/32"
  }

  expect_failures = [var.bastion_allowed_ssh_cidr]
}

run "reject_benchmark_bastion_cidr" {
  command = plan

  variables {
    bastion_allowed_ssh_cidr = "198.18.0.42/32"
  }

  expect_failures = [var.bastion_allowed_ssh_cidr]
}

run "reject_test_net_two_bastion_cidr" {
  command = plan

  variables {
    bastion_allowed_ssh_cidr = "198.51.100.42/32"
  }

  expect_failures = [var.bastion_allowed_ssh_cidr]
}

run "reject_test_net_three_bastion_cidr" {
  command = plan

  variables {
    bastion_allowed_ssh_cidr = "203.0.113.42/32"
  }

  expect_failures = [var.bastion_allowed_ssh_cidr]
}

run "reject_force_destroy_on_protected_cluster" {
  command = plan

  variables {
    model_cache_force_destroy = true
  }

  expect_failures = [alicloud_oss_bucket.model_cache[0]]
}

run "reject_fractional_system_pool_values" {
  command = plan

  variables {
    system_node_pool = {
      min_size         = 1.5
      max_size         = 3
      system_disk_size = 100
    }
  }

  expect_failures = [var.system_node_pool]
}

run "reject_fractional_gpu_pool_values" {
  command = plan

  variables {
    gpu_node_pools = [{
      name             = "a10"
      min_size         = 0
      max_size         = 2.5
      system_disk_size = 500
    }]
  }

  expect_failures = [var.gpu_node_pools]
}

run "reject_fractional_lifecycle_audit_and_kms_values" {
  command = plan

  variables {
    payload_expiration_days               = 1.5
    incomplete_multipart_expiration_days  = 7.5
    audit_log_retention_days              = 30.5
    ack_secret_kms_pending_window_days    = 7.5
    ack_secret_kms_rotation_interval_days = 30.5
  }

  expect_failures = [
    var.payload_expiration_days,
    var.incomplete_multipart_expiration_days,
    var.audit_log_retention_days,
    var.ack_secret_kms_pending_window_days,
    var.ack_secret_kms_rotation_interval_days,
  ]
}

run "reject_kms_rotation_below_seven_days" {
  command = plan

  variables {
    ack_secret_kms_rotation_interval_days = 6
  }

  expect_failures = [var.ack_secret_kms_rotation_interval_days]
}

run "reject_kms_rotation_above_365_days" {
  command = plan

  variables {
    ack_secret_kms_rotation_interval_days = 366
  }

  expect_failures = [var.ack_secret_kms_rotation_interval_days]
}

run "reject_fractional_bastion_values" {
  command = plan

  variables {
    bastion_system_disk_size_gb = 40.5
    bastion_eip_bandwidth_mbps  = 5.5
  }

  expect_failures = [var.bastion_system_disk_size_gb, var.bastion_eip_bandwidth_mbps]
}

run "reject_noncanonical_vpc_cidr" {
  command = plan

  variables {
    vpc_cidr = "10.0.1.0/16"
  }

  expect_failures = [var.vpc_cidr]
}

run "reject_noncanonical_vswitch_cidr" {
  command = plan

  variables {
    system_vswitch_cidrs = ["10.0.1.0/20", "10.0.16.0/20"]
  }

  expect_failures = [var.system_vswitch_cidrs]
}

run "reject_noncanonical_pod_and_service_cidrs" {
  command = plan

  variables {
    pod_cidr     = "10.1.1.0/16"
    service_cidr = "172.20.1.0/16"
  }

  expect_failures = [var.pod_cidr, var.service_cidr]
}

run "reject_public_vpc_and_vswitch_cidrs" {
  command = plan

  variables {
    vpc_cidr             = "100.64.0.0/16"
    system_vswitch_cidrs = ["100.64.0.0/20", "100.64.16.0/20"]
    gpu_vswitch_cidrs    = ["100.64.32.0/20", "100.64.48.0/20"]
  }

  expect_failures = [var.vpc_cidr, var.system_vswitch_cidrs, var.gpu_vswitch_cidrs]
}

run "reject_pod_prefix_outside_ack_range" {
  command = plan

  variables {
    pod_cidr = "10.1.0.0/25"
  }

  expect_failures = [var.pod_cidr]
}
