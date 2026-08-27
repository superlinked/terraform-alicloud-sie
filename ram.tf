locals {
  ecs_assume_role_policy = jsonencode({
    Version = "1"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = ["ecs.aliyuncs.com"] }
    }]
  })

  gpu_node_roles_to_create = {
    for pool in var.gpu_node_pools : pool.name => pool
    if pool.ram_role_name == null
  }
}

resource "alicloud_ram_role" "system_node" {
  count = var.system_node_ram_role_name == null ? 1 : 0

  role_name                   = local.names.system_node_role
  description                 = "ECS-trusted role isolated to the ${var.cluster_name} system node pool."
  assume_role_policy_document = local.ecs_assume_role_policy
  max_session_duration        = 3600
  force                       = false
  tags                        = local.resource_tags
}

resource "alicloud_ram_role" "gpu_node" {
  for_each = local.gpu_node_roles_to_create

  role_name                   = local.gpu_node_role_names[each.key]
  description                 = "ECS-trusted role isolated to ACK GPU node pool ${each.key}."
  assume_role_policy_document = local.ecs_assume_role_policy
  max_session_duration        = 3600
  force                       = false
  tags                        = local.resource_tags
}
