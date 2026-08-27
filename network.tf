resource "alicloud_vpc" "main" {
  vpc_name   = local.names.vpc
  cidr_block = var.vpc_cidr
  tags       = local.resource_tags

  lifecycle {
    precondition {
      condition     = local.cidrs_do_not_overlap
      error_message = "System vSwitch, GPU vSwitch, pod, and service CIDRs must not overlap."
    }

    precondition {
      condition     = local.vswitches_are_inside_vpc
      error_message = "Every system and GPU vSwitch CIDR must be contained by vpc_cidr."
    }

    precondition {
      condition     = local.pod_and_service_are_outside_vpc
      error_message = "pod_cidr and service_cidr must not overlap vpc_cidr."
    }
  }
}

resource "alicloud_vswitch" "system" {
  for_each = local.system_vswitches

  vpc_id       = alicloud_vpc.main.id
  zone_id      = each.key
  cidr_block   = each.value.cidr
  vswitch_name = "${var.cluster_name}-system-${each.key}"
  tags         = local.resource_tags
}

resource "alicloud_vswitch" "gpu" {
  for_each = local.gpu_vswitches

  vpc_id       = alicloud_vpc.main.id
  zone_id      = each.key
  cidr_block   = each.value.cidr
  vswitch_name = "${var.cluster_name}-gpu-${each.key}"
  tags         = local.resource_tags
}

resource "alicloud_nat_gateway" "main" {
  vpc_id               = alicloud_vpc.main.id
  vswitch_id           = alicloud_vswitch.system[var.zones[0]].id
  nat_gateway_name     = local.names.nat_gateway
  nat_type             = "Enhanced"
  network_type         = "internet"
  availability_mode    = "CrossAZ"
  payment_type         = "PayAsYouGo"
  internet_charge_type = "PayByLcu"
  eip_bind_mode        = "NAT"
  tags                 = local.resource_tags
}

resource "alicloud_eip_address" "nat" {
  address_name         = local.names.nat_eip
  payment_type         = "PayAsYouGo"
  internet_charge_type = "PayByTraffic"
  bandwidth            = tostring(var.nat_eip_bandwidth_mbps)
  tags                 = local.resource_tags
}

resource "alicloud_eip_association" "nat" {
  allocation_id = alicloud_eip_address.nat.id
  instance_id   = alicloud_nat_gateway.main.id
  instance_type = "Nat"
}

resource "alicloud_snat_entry" "system" {
  for_each = alicloud_vswitch.system

  snat_table_id     = alicloud_nat_gateway.main.snat_table_ids
  source_vswitch_id = each.value.id
  snat_ip           = alicloud_eip_address.nat.ip_address
  snat_entry_name   = "${var.cluster_name}-system-${each.key}"

  depends_on = [alicloud_eip_association.nat]
}

resource "alicloud_snat_entry" "gpu" {
  for_each = alicloud_vswitch.gpu

  snat_table_id     = alicloud_nat_gateway.main.snat_table_ids
  source_vswitch_id = each.value.id
  snat_ip           = alicloud_eip_address.nat.ip_address
  snat_entry_name   = "${var.cluster_name}-gpu-${each.key}"

  depends_on = [alicloud_eip_association.nat]
}
