resource "alicloud_cs_managed_kubernetes" "main" {
  name                           = var.cluster_name
  profile                        = "Default"
  cluster_spec                   = "ack.pro.small"
  version                        = var.kubernetes_version
  vswitch_ids                    = [for zone in var.zones : alicloud_vswitch.system[zone].id]
  new_nat_gateway                = false
  pod_cidr                       = var.pod_cidr
  service_cidr                   = var.service_cidr
  proxy_mode                     = "ipvs"
  ip_stack                       = "ipv4"
  slb_internet_enabled           = false
  deletion_protection            = var.deletion_protection
  enable_rrsa                    = true
  disable_encryption             = !var.ack_secret_encryption_enabled
  encryption_provider_key        = local.ack_secret_kms_key_id
  control_plane_log_components   = var.audit_logging_enabled ? ["apiserver", "kcm", "scheduler", "ccm", "controlplane-events"] : []
  control_plane_log_project      = var.audit_logging_enabled ? alicloud_log_project.ack[0].project_name : null
  control_plane_log_ttl          = var.audit_logging_enabled ? tostring(var.audit_log_retention_days) : null
  skip_set_certificate_authority = true
  tags                           = local.resource_tags

  addons {
    name = "flannel"
  }

  addons {
    name = "csi-plugin"
  }

  addons {
    name = "csi-provisioner"
  }

  dynamic "audit_log_config" {
    for_each = var.audit_logging_enabled ? [1] : []
    content {
      enabled          = true
      sls_project_name = alicloud_log_project.ack[0].project_name
    }
  }

  depends_on = [
    alicloud_snat_entry.system,
    alicloud_snat_entry.gpu,
  ]

  lifecycle {
    postcondition {
      condition     = try(trimspace(coalesce(self.connections["api_server_internet"], "")) == "", true)
      error_message = "The ACK cluster has a public API connection, which violates this module's private-only invariant. Remove the out-of-band public endpoint before continuing."
    }

    precondition {
      condition = (
        !var.ack_secret_encryption_enabled
        || (
          var.create_ack_secret_kms_key
          ? var.ack_secret_kms_key_id == null
          : var.ack_secret_kms_key_id != null
        )
      )
      error_message = "ACK Secret encryption requires exactly one KMS authority: create_ack_secret_kms_key=true with no existing ID, or false with ack_secret_kms_key_id."
    }
  }
}

resource "alicloud_cs_kubernetes_addon" "nvidia_device_plugin" {
  cluster_id = alicloud_cs_managed_kubernetes.main.id
  name       = "ack-nvidia-device-plugin"
  config     = jsonencode({})
}
