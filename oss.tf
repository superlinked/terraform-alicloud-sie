resource "random_id" "storage_suffix" {
  byte_length = 4

  keepers = {
    cluster_name = var.cluster_name
  }
}

resource "alicloud_oss_bucket" "model_cache" {
  count = var.create_model_cache ? 1 : 0

  bucket                                   = local.model_cache_bucket_name
  storage_class                            = "Standard"
  redundancy_type                          = "LRS"
  force_destroy                            = var.model_cache_force_destroy
  lifecycle_rule_allow_same_action_overlap = true
  tags                                     = local.resource_tags

  lifecycle_rule {
    id      = "expire-payloads"
    prefix  = "payloads/"
    enabled = true

    expiration {
      days = var.payload_expiration_days
    }

    dynamic "noncurrent_version_expiration" {
      for_each = var.model_cache_versioning_enabled ? [1] : []
      content {
        days = var.payload_expiration_days
      }
    }
  }

  lifecycle_rule {
    id      = "expire-payload-delete-markers"
    prefix  = "payloads/"
    enabled = true

    expiration {
      expired_object_delete_marker = true
    }
  }

  lifecycle_rule {
    id      = "abort-incomplete-multipart"
    prefix  = ""
    enabled = true

    abort_multipart_upload {
      days = var.incomplete_multipart_expiration_days
    }
  }

  lifecycle {
    # Provider refresh copies the settings owned by the standalone resources
    # below into these inline bucket mirror fields. Ignoring that mirror
    # prevents destructive encryption deletion and a perpetual versioning diff.
    ignore_changes = [server_side_encryption_rule, versioning]

    precondition {
      condition     = !var.model_cache_force_destroy || !var.deletion_protection
      error_message = "model_cache_force_destroy=true is allowed only when deletion_protection=false for an explicitly ephemeral cluster."
    }
  }
}

resource "alicloud_oss_bucket_acl" "model_cache" {
  count = var.create_model_cache ? 1 : 0

  bucket = alicloud_oss_bucket.model_cache[0].bucket
  acl    = "private"

  depends_on = [alicloud_oss_bucket.model_cache]
}

resource "alicloud_oss_bucket_public_access_block" "model_cache" {
  count = var.create_model_cache ? 1 : 0

  bucket              = alicloud_oss_bucket.model_cache[0].bucket
  block_public_access = true

  depends_on = [alicloud_oss_bucket_acl.model_cache]
}

resource "alicloud_oss_bucket_server_side_encryption" "model_cache" {
  count = var.create_model_cache ? 1 : 0

  bucket        = alicloud_oss_bucket.model_cache[0].bucket
  sse_algorithm = "AES256"

  depends_on = [alicloud_oss_bucket_public_access_block.model_cache]
}

resource "alicloud_oss_bucket_versioning" "model_cache" {
  count = var.create_model_cache ? 1 : 0

  bucket = alicloud_oss_bucket.model_cache[0].bucket
  status = var.model_cache_versioning_enabled ? "Enabled" : "Suspended"

  depends_on = [alicloud_oss_bucket_server_side_encryption.model_cache]
}
