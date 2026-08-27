resource "alicloud_cs_kubernetes_node_pool" "system" {
  cluster_id           = alicloud_cs_managed_kubernetes.main.id
  node_pool_name       = local.names.system_pool
  vswitch_ids          = [for zone in var.zones : alicloud_vswitch.system[zone].id]
  instance_types       = var.system_node_pool.instance_types
  instance_charge_type = "PostPaid"
  spot_strategy        = "NoSpot"
  key_name             = var.ecs_key_name
  ram_role_name = (
    var.system_node_ram_role_name != null
    ? var.system_node_ram_role_name
    : alicloud_ram_role.system_node[0].role_name
  )
  image_type            = var.system_node_pool.image_type
  system_disk_category  = "cloud_essd"
  system_disk_size      = var.system_node_pool.system_disk_size
  system_disk_encrypted = true
  install_cloud_monitor = true
  tags                  = local.resource_tags

  instance_metadata_options {
    http_tokens = "required"
  }

  scaling_config {
    enable   = true
    min_size = var.system_node_pool.min_size
    max_size = var.system_node_pool.max_size
    type     = "cpu"
  }

  labels {
    key   = "project"
    value = local.node_labels.project
  }

  labels {
    key   = "sie-cluster"
    value = local.node_labels["sie-cluster"]
  }

  labels {
    key   = "sie.superlinked.com/node-type"
    value = "cpu"
  }
}

resource "alicloud_cs_kubernetes_node_pool" "gpu" {
  for_each = { for pool in var.gpu_node_pools : pool.name => pool }

  cluster_id                               = alicloud_cs_managed_kubernetes.main.id
  node_pool_name                           = "${var.cluster_name}-${each.value.name}"
  vswitch_ids                              = [for zone in var.zones : alicloud_vswitch.gpu[zone].id]
  instance_types                           = each.value.instance_types
  instance_charge_type                     = "PostPaid"
  spot_strategy                            = each.value.spot ? "SpotAsPriceGo" : "NoSpot"
  multi_az_policy                          = each.value.spot ? "COST_OPTIMIZED" : "BALANCE"
  compensate_with_on_demand                = each.value.spot ? each.value.compensate_with_on_demand : false
  on_demand_base_capacity                  = each.value.spot ? tostring(each.value.on_demand_base_capacity) : null
  on_demand_percentage_above_base_capacity = each.value.spot ? tostring(each.value.on_demand_percentage_above_capacity) : null
  key_name                                 = var.ecs_key_name
  ram_role_name = (
    each.value.ram_role_name != null
    ? each.value.ram_role_name
    : alicloud_ram_role.gpu_node[each.key].role_name
  )
  image_type            = each.value.image_type
  system_disk_category  = "cloud_essd"
  system_disk_size      = each.value.system_disk_size
  system_disk_encrypted = true
  install_cloud_monitor = true
  tags                  = local.resource_tags

  instance_metadata_options {
    http_tokens = "required"
  }

  scaling_config {
    enable   = true
    min_size = each.value.min_size
    max_size = each.value.max_size
    type     = each.value.spot ? "spot" : "gpu"
  }

  dynamic "labels" {
    for_each = merge(each.value.labels, local.node_labels, {
      "ack.node.gpu.schedule"         = "default"
      "sie.superlinked.com/node-type" = "gpu"
      "sie.superlinked.com/gpu-type"  = each.value.gpu_type
    })

    content {
      key   = labels.key
      value = labels.value
    }
  }

  taints {
    key    = "nvidia.com/gpu"
    value  = "present"
    effect = "NoSchedule"
  }
}
