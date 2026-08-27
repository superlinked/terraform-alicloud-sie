locals {
  rrsa_metadata          = try(alicloud_cs_managed_kubernetes.main.rrsa_metadata[0], null)
  rrsa_oidc_provider_arn = try(local.rrsa_metadata.ram_oidc_provider_arn, "")
  rrsa_oidc_issuer_url   = try(local.rrsa_metadata.rrsa_oidc_issuer_url, "")
  workload_subject       = "system:serviceaccount:${var.sie_namespace}:${var.sie_service_account_name}"

  workload_assume_role_policy = jsonencode({
    Version = "1"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Federated = [local.rrsa_oidc_provider_arn] }
      Condition = {
        StringEquals = {
          "oidc:iss" = local.rrsa_oidc_issuer_url
          "oidc:aud" = "sts.aliyuncs.com"
          "oidc:sub" = local.workload_subject
        }
      }
    }]
  })
}

resource "alicloud_cs_kubernetes_addon" "pod_identity_webhook" {
  cluster_id = alicloud_cs_managed_kubernetes.main.id
  name       = "ack-pod-identity-webhook"
  # The runtime fixes STS to the official provider endpoint and rejects an
  # injected endpoint override. Keep core RRSA token/role injection enabled,
  # but do not inject ALIBABA_CLOUD_STS_ENDPOINT and related convenience env.
  config = jsonencode({ AutoInjectSTSEnvVars = false })
}

resource "alicloud_ram_role" "workload" {
  role_name                   = local.names.workload_role
  description                 = "RRSA role for SIE model-cache reads and payload-store access."
  assume_role_policy_document = local.workload_assume_role_policy
  max_session_duration        = 3600
  force                       = false
  tags                        = local.resource_tags

  lifecycle {
    precondition {
      condition     = try(local.rrsa_metadata.enabled, false) && local.rrsa_oidc_provider_arn != "" && local.rrsa_oidc_issuer_url != ""
      error_message = "ACK RRSA metadata must expose an enabled OIDC provider before the SIE workload role can be created."
    }
  }
}

resource "alicloud_ram_policy" "workload_oss" {
  count = var.create_model_cache ? 1 : 0

  policy_name = local.names.workload_policy
  description = "Prefix-scoped SIE access to model-cache reads and payload read/write/delete."
  force       = false
  tags        = local.resource_tags
  policy_document = jsonencode({
    Version = "1"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["oss:ListObjects"]
        Resource = ["acs:oss:*:*:${alicloud_oss_bucket.model_cache[0].bucket}"]
        Condition = {
          StringLike = {
            "oss:Prefix" = ["models/*", "payloads/*"]
          }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["oss:GetObject"]
        Resource = ["acs:oss:*:*:${alicloud_oss_bucket.model_cache[0].bucket}/models/*"]
      },
      {
        Effect = "Allow"
        Action = [
          "oss:GetObject",
          "oss:PutObject",
          "oss:DeleteObject",
          "oss:AbortMultipartUpload",
          "oss:ListParts",
        ]
        Resource = ["acs:oss:*:*:${alicloud_oss_bucket.model_cache[0].bucket}/payloads/*"]
      },
    ]
  })
}

resource "alicloud_ram_role_policy_attachment" "workload_oss" {
  count = var.create_model_cache ? 1 : 0

  role_name   = alicloud_ram_role.workload.role_name
  policy_name = alicloud_ram_policy.workload_oss[0].policy_name
  policy_type = "Custom"
}
