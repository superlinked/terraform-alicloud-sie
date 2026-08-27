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
}

mock_provider "random" {
  mock_resource "random_id" {
    defaults = {
      hex = "cafebabe"
    }
  }
}

run "validate_frankfurt_and_safe_module_defaults" {
  command = plan

  variables {
    ack_secret_kms_default_rotation_entitled = true
  }

  assert {
    condition = (
      var.alicloud_region == "eu-central-1"
      && var.system_node_image_type == "AliyunLinux3ContainerOptimized"
      && var.gpu_node_image_type == "AliyunLinux3ContainerOptimized"
      && module.sie_ack.system_node_pool.image_type == "AliyunLinux3ContainerOptimized"
      && module.sie_ack.gpu_node_pools["a10"].image_type == "AliyunLinux3ContainerOptimized"
      && module.sie_ack.system_node_pool.min_size == 1
      && module.sie_ack.system_node_pool.max_size == 5
      && module.sie_ack.gpu_node_pools["a10"].min_size == 0
      && module.sie_ack.gpu_node_pools["a10"].max_size == 10
    )
    error_message = "The public example must retain the Frankfurt and ordinary module capacity defaults."
  }

  assert {
    condition = (
      module.sie_ack.ack_secret_encryption.module_created
      && module.sie_ack.ack_secret_encryption.deletion_protection
      && module.sie_ack.ack_secret_encryption.rotation_interval == "31536000s"
    )
    error_message = "The public example must retain the protected, rotating module-created KMS posture."
  }
}

run "reject_unreviewed_node_image_families" {
  command = plan

  variables {
    ack_secret_kms_default_rotation_entitled = true
    system_node_image_type                   = "AliyunLinux3"
    gpu_node_image_type                      = "ContainerOS"
  }

  expect_failures = [var.system_node_image_type, var.gpu_node_image_type]
}

run "validate_existing_rotating_key_path" {
  command = plan

  variables {
    create_ack_secret_kms_key = false
    ack_secret_kms_key_id     = "kms-existing-test"
  }

  override_data {
    target = module.sie_ack.data.alicloud_kms_keys.ack_secrets_existing[0]
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
      !module.sie_ack.ack_secret_encryption.module_created
      && module.sie_ack.ack_secret_encryption.key_id == "kms-existing-test"
      && module.sie_ack.ack_secret_encryption.automatic_rotation
      && module.sie_ack.ack_secret_encryption.rotation_interval == "31536000s"
    )
    error_message = "The public example must forward an existing rotating KMS key without creating another key."
  }
}

run "validate_caller_owned_software_kms_instance_path" {
  command = plan

  variables {
    ack_secret_kms_instance_id            = "kms-instance-test"
    ack_secret_kms_rotation_interval_days = 30
  }

  assert {
    condition = (
      module.sie_ack.ack_secret_encryption.module_created
      && module.sie_ack.ack_secret_encryption.kms_instance_id == "kms-instance-test"
      && module.sie_ack.ack_secret_encryption.rotation_interval == "2592000s"
    )
    error_message = "The public example must forward the caller-owned software KMS instance and integral rotation interval."
  }
}

run "validate_existing_default_rotation_entitlement_path" {
  command = plan

  variables {
    ack_secret_kms_default_rotation_entitled = true
  }

  assert {
    condition = (
      module.sie_ack.ack_secret_encryption.module_created
      && module.sie_ack.ack_secret_encryption.kms_instance_id == null
      && module.sie_ack.ack_secret_encryption.rotation_interval == "31536000s"
    )
    error_message = "The public example must forward only the pre-existing Default Key Rotation entitlement attestation."
  }
}

run "reject_missing_rotating_kms_authority" {
  command = plan

  expect_failures = [var.ack_secret_kms_default_rotation_entitled]
}

run "validate_optional_acr_coordinates" {
  command = plan

  variables {
    ack_secret_kms_default_rotation_entitled = true
    enable_acr_repositories                  = true
    acr_enterprise_instance_id               = "cri-existing-test"
    acr_registry_domain                      = "registry.example.invalid"
  }

  assert {
    condition = (
      length(module.sie_ack.acr_repositories) == 3
      && module.sie_ack.acr_repositories["sie-config"].endpoint == "registry.example.invalid/sie/sie-config"
      && module.sie_ack.acr_repositories["sie-gateway"].endpoint == "registry.example.invalid/sie/sie-gateway"
      && module.sie_ack.acr_repositories["sie-server"].endpoint == "registry.example.invalid/sie/sie-server"
    )
    error_message = "The public example must forward caller-owned ACR coordinates without creating an ACR subscription."
  }
}
