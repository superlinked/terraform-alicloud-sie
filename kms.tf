data "alicloud_kms_keys" "ack_secrets_existing" {
  count = var.ack_secret_encryption_enabled && !var.create_ack_secret_kms_key && var.ack_secret_kms_key_id != null ? 1 : 0

  enable_details = true
  ids            = [var.ack_secret_kms_key_id]

  lifecycle {
    postcondition {
      condition = (
        length(self.keys) == 1
        && try(
          self.keys[0].key_id == var.ack_secret_kms_key_id
          && self.keys[0].status == "Enabled"
          && self.keys[0].key_spec == join("_", ["Aliyun", "AES", "256"])
          && self.keys[0].key_usage == "ENCRYPT/DECRYPT"
          && self.keys[0].automatic_rotation == "Enabled",
          false,
        )
      )
      error_message = "The existing ACK Secret KMS key must resolve exactly once in this region and be Enabled, Aliyun_AES_256, ENCRYPT/DECRYPT, and automatically rotating."
    }
  }
}

resource "alicloud_kms_key" "ack_secrets" {
  count = var.ack_secret_encryption_enabled && var.create_ack_secret_kms_key ? 1 : 0

  description                     = "ACK Secret envelope encryption key for ${var.cluster_name}."
  key_spec                        = "Aliyun_AES_256"
  key_usage                       = "ENCRYPT/DECRYPT"
  origin                          = "Aliyun_KMS"
  status                          = "Enabled"
  dkms_instance_id                = var.ack_secret_kms_instance_id
  automatic_rotation              = var.ack_secret_kms_automatic_rotation_enabled ? "Enabled" : null
  rotation_interval               = local.ack_secret_kms_rotation_interval
  deletion_protection             = var.ack_secret_kms_deletion_protection ? "Enabled" : "Disabled"
  deletion_protection_description = var.ack_secret_kms_deletion_protection ? "Protect the active ACK Secret envelope-encryption key." : null
  pending_window_in_days          = var.ack_secret_kms_pending_window_days
  tags                            = local.resource_tags

  lifecycle {
    precondition {
      condition     = !var.ack_secret_kms_deletion_protection || var.deletion_protection
      error_message = "ack_secret_kms_deletion_protection=true requires cluster deletion_protection=true; disable both only for an ephemeral run."
    }

    precondition {
      condition = (
        !var.ack_secret_kms_automatic_rotation_enabled
        || var.ack_secret_kms_instance_id != null
        || var.ack_secret_kms_default_rotation_entitled
      )
      error_message = "Automatic KMS rotation requires either ack_secret_kms_default_rotation_entitled=true after the paid regional entitlement is confirmed, or an existing software ack_secret_kms_instance_id."
    }

    precondition {
      condition = (
        !var.ack_secret_kms_automatic_rotation_enabled
        || var.ack_secret_kms_instance_id != null
        || var.ack_secret_kms_rotation_interval_days == 365
      )
      error_message = "The default-key rotation entitlement has a fixed 365-day interval; custom 7-365 day intervals require ack_secret_kms_instance_id."
    }
  }
}

locals {
  ack_secret_kms_rotation_interval = var.ack_secret_kms_automatic_rotation_enabled ? "${var.ack_secret_kms_rotation_interval_days * 86400}s" : null
  ack_secret_kms_key_id = var.ack_secret_encryption_enabled ? (
    var.create_ack_secret_kms_key
    ? try(alicloud_kms_key.ack_secrets[0].id, null)
    : try(data.alicloud_kms_keys.ack_secrets_existing[0].keys[0].key_id, null)
  ) : null
}
