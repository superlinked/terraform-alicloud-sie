resource "alicloud_cr_ee_namespace" "sie" {
  count = var.enable_acr_repositories ? 1 : 0

  instance_id        = coalesce(var.acr_enterprise_instance_id, "existing-acr-instance-required")
  name               = local.names.acr_namespace
  auto_create        = false
  default_visibility = "PRIVATE"
}

resource "alicloud_cr_ee_repo" "sie" {
  for_each = var.enable_acr_repositories ? var.acr_repositories : {}

  instance_id      = coalesce(var.acr_enterprise_instance_id, "existing-acr-instance-required")
  namespace        = alicloud_cr_ee_namespace.sie[0].name
  name             = each.key
  repo_type        = "PRIVATE"
  summary          = each.value.summary
  detail           = each.value.detail
  tag_immutability = each.value.tag_immutability
}
