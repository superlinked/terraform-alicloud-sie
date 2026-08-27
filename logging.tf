resource "alicloud_log_project" "ack" {
  count = var.audit_logging_enabled ? 1 : 0

  project_name = local.audit_log_project_name
  description  = "ACK API audit and control-plane component logs for ${var.cluster_name}."
  tags         = local.resource_tags
}
