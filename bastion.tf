data "alicloud_images" "bastion" {
  count = var.bastion_enabled && var.bastion_image_id == null ? 1 : 0

  owners                = "system"
  name_regex            = "^aliyun_3_x64_20G_alibase_.*"
  architecture          = "x86_64"
  os_type               = "linux"
  status                = "Available"
  most_recent           = true
  instance_type         = var.bastion_instance_type
  is_support_cloud_init = true
}

resource "alicloud_security_group" "bastion" {
  count = var.bastion_enabled ? 1 : 0

  security_group_name = local.names.bastion_sg
  description         = "SSH-only ingress for the Terraform-owned ACK private-API bastion."
  vpc_id              = alicloud_vpc.main.id
  security_group_type = "normal"
  inner_access_policy = "Drop"
  tags                = local.resource_tags
}

resource "alicloud_security_group_rule" "bastion_ssh" {
  count = var.bastion_enabled ? 1 : 0

  type              = "ingress"
  ip_protocol       = "tcp"
  port_range        = "22/22"
  nic_type          = "intranet"
  policy            = "accept"
  priority          = 1
  cidr_ip           = var.bastion_allowed_ssh_cidr
  security_group_id = alicloud_security_group.bastion[0].id
  description       = "Exact operator /32 for the temporary SSH SOCKS tunnel."
}

resource "alicloud_instance" "bastion" {
  count = var.bastion_enabled ? 1 : 0

  instance_name               = local.names.bastion
  host_name                   = local.names.bastion
  image_id                    = var.bastion_image_id != null ? var.bastion_image_id : data.alicloud_images.bastion[0].images[0].id
  instance_type               = var.bastion_instance_type
  instance_charge_type        = "PostPaid"
  vswitch_id                  = alicloud_vswitch.system[var.zones[0]].id
  security_groups             = [alicloud_security_group.bastion[0].id]
  key_name                    = var.ecs_key_name
  internet_max_bandwidth_out  = 0
  system_disk_category        = "cloud_essd"
  system_disk_size            = var.bastion_system_disk_size_gb
  system_disk_encrypted       = true
  http_endpoint               = "enabled"
  http_tokens                 = "required"
  http_put_response_hop_limit = 1
  deletion_protection         = false
  tags = merge(local.resource_tags, {
    component = "private-api-bastion"
  })

  lifecycle {
    precondition {
      condition     = var.ecs_key_name != null && try(trimspace(var.ecs_key_name) != "", false)
      error_message = "bastion_enabled=true requires ecs_key_name for an existing ECS key pair."
    }

    precondition {
      condition     = var.bastion_allowed_ssh_cidr != null
      error_message = "bastion_enabled=true requires bastion_allowed_ssh_cidr with one canonical operator /32."
    }
  }
}

resource "alicloud_eip_address" "bastion" {
  count = var.bastion_enabled ? 1 : 0

  address_name         = local.names.bastion_eip
  payment_type         = "PayAsYouGo"
  internet_charge_type = "PayByTraffic"
  bandwidth            = tostring(var.bastion_eip_bandwidth_mbps)
  tags                 = merge(local.resource_tags, { component = "private-api-bastion" })
}

resource "alicloud_eip_association" "bastion" {
  count = var.bastion_enabled ? 1 : 0

  allocation_id = alicloud_eip_address.bastion[0].id
  instance_id   = alicloud_instance.bastion[0].id
  instance_type = "EcsInstance"
}
