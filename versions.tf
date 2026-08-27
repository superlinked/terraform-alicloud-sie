terraform {
  required_version = ">= 1.14"

  required_providers {
    alicloud = {
      source  = "aliyun/alicloud"
      version = "~> 1.289.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
}
