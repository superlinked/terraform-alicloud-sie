locals {
  resource_tags = merge(var.tags, {
    project       = "sie"
    "sie-cluster" = var.cluster_name
  })

  node_labels = {
    project       = "sie"
    "sie-cluster" = var.cluster_name
  }

  system_vswitches = {
    for index, zone in var.zones : zone => {
      cidr = try(var.system_vswitch_cidrs[index], var.system_vswitch_cidrs[0])
    }
  }

  gpu_vswitches = {
    for index, zone in var.zones : zone => {
      cidr = try(var.gpu_vswitch_cidrs[index], var.gpu_vswitch_cidrs[0])
    }
  }

  all_cluster_cidrs = concat(
    var.system_vswitch_cidrs,
    var.gpu_vswitch_cidrs,
    [var.pod_cidr, var.service_cidr],
  )

  cidr_ranges = [
    for cidr in local.all_cluster_cidrs : {
      cidr = cidr
      start = sum([
        for index, octet in split(".", cidrhost(cidr, 0)) :
        tonumber(octet) * pow(256, 3 - index)
      ])
      end = sum([
        for index, octet in split(".", cidrhost(cidr, 0)) :
        tonumber(octet) * pow(256, 3 - index)
      ]) + pow(2, 32 - tonumber(split("/", cidr)[1])) - 1
    }
  ]

  vpc_range = {
    start = sum([
      for index, octet in split(".", cidrhost(var.vpc_cidr, 0)) :
      tonumber(octet) * pow(256, 3 - index)
    ])
    end = sum([
      for index, octet in split(".", cidrhost(var.vpc_cidr, 0)) :
      tonumber(octet) * pow(256, 3 - index)
    ]) + pow(2, 32 - tonumber(split("/", var.vpc_cidr)[1])) - 1
  }

  cidrs_do_not_overlap = alltrue(flatten([
    for left_index, left in local.cidr_ranges : [
      for right_index, right in local.cidr_ranges :
      left.end < right.start || right.end < left.start
      if left_index < right_index
    ]
  ]))

  vswitches_are_inside_vpc = alltrue([
    for cidr_range in slice(local.cidr_ranges, 0, length(var.system_vswitch_cidrs) + length(var.gpu_vswitch_cidrs)) :
    cidr_range.start >= local.vpc_range.start && cidr_range.end <= local.vpc_range.end
  ])

  pod_and_service_are_outside_vpc = alltrue([
    for cidr_range in slice(local.cidr_ranges, length(local.cidr_ranges) - 2, length(local.cidr_ranges)) :
    cidr_range.end < local.vpc_range.start || cidr_range.start > local.vpc_range.end
  ])
}
