# SIE Alibaba Cloud ACK Terraform Module

This module creates a GPU-ready Alibaba Cloud Container Service for Kubernetes
(ACK) cluster and the supporting infrastructure needed to run
[SIE](https://github.com/superlinked/sie). After Terraform creates the
infrastructure, install the SIE runtime with the `sie-cluster` Helm chart.

By default, the module deploys in Frankfurt (`eu-central-1`) across zones
`eu-central-1a` and `eu-central-1c`. It creates an `ecs.g7.xlarge` system pool
and an on-demand `ecs.gn7i-c8g1.2xlarge` GPU pool with one NVIDIA A10 24 GiB
GPU per node. The GPU pool scales from zero to ten nodes and uses a 500 GiB
system disk. Both pools use the ACK-resolved
`AliyunLinux3ContainerOptimized` image family.

## What you get

- A VPC with separate system and GPU vSwitches in both configured zones.
- Private-node internet egress through an Enhanced Internet NAT gateway and a
  pay-as-you-go EIP.
- A private-API ACK Pro cluster using Flannel, with deletion protection enabled
  by default.
- Autoscaling system and GPU node pools with encrypted ESSD system disks,
  IMDSv2-only metadata access, and separate ECS-trusted RAM roles.
- ACK CSI components, the managed `ack-nvidia-device-plugin`, RRSA, and the
  managed `ack-pod-identity-webhook`.
- A private, encrypted, versioned OSS bucket for model weights under `models/`
  and large request payloads under `payloads/`.
- A least-privilege RRSA workload role scoped to the configured SIE namespace
  and ServiceAccount.
- KMS envelope encryption for ACK Secrets, with automatic key rotation enabled
  by default.
- ACK API audit and control-plane logs in an SLS project.
- Optional private repositories in an existing ACR Enterprise Edition instance.
- An optional SSH bastion restricted to one operator `/32`; the ACK API remains
  private.

Not included: Kubernetes workloads, account-wide service activation and service
roles, an ACR subscription, registry credentials, kubeconfig storage, or the
purchase of a KMS Default Key Rotation entitlement.

## Quick start

### Use the module from the Terraform Registry

Configure OSS and SLS Signature V4 in the provider, then call the module with a
unique cluster name and one of the supported KMS configurations. Pin `version`
to the value shown in the Registry **Provision Instructions** for reproducible
deployments.

```hcl
terraform {
  required_version = ">= 1.14"

  required_providers {
    alicloud = {
      source  = "aliyun/alicloud"
      version = "~> 1.289.0"
    }
  }
}

provider "alicloud" {
  region = "eu-central-1"

  sign_version {
    oss = "v4"
    sls = "v4"
  }
}

module "sie_ack" {
  source = "superlinked/sie/alicloud"
  # version = "<version-from-registry-provision-instructions>"

  cluster_name               = "replace-with-a-unique-cluster-name"
  ack_secret_kms_instance_id = "replace-with-a-same-region-software-kms-instance-id"
}
```

Initialize Terraform, review a saved plan, and apply it when it matches your
intended infrastructure:

```bash
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

### Run the included example

The [`examples/dev-gn7i`](examples/dev-gn7i/) configuration deploys the default
Frankfurt A10 topology. From a checkout of the module source:

```bash
cd examples/dev-gn7i
cp terraform.tfvars.example terraform.tfvars
# Set a unique cluster_name and select one KMS configuration below.
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

Terraform returns a command for obtaining a renewable, 15-minute private
kubeconfig without writing credentials into state:

```bash
terraform output -raw kubeconfig_command
```

Run the printed command from a host with private connectivity to the ACK API,
save its output in a mode-0600 temporary file, and use that file with
`kubectl`. Continue with [Connect to ACK and install SIE](#connect-to-ack-and-install-sie).

## Prerequisites

Before applying the module:

1. Enable ACK, KMS, OSS, and SLS in the target account and region.
2. Create the Alibaba Cloud service roles required by ACK, NAT Gateway, Auto
   Scaling, and OOS. The Terraform principal must be able to create resources,
   create and pass RAM roles, and use the selected KMS resources.
3. Confirm that ACK Pro and the required VPC, vSwitch, NAT, EIP, ECS, OSS, KMS,
   and SLS quotas are available.
4. Confirm current `ecs.g7.xlarge` and `ecs.gn7i-c8g1.2xlarge` inventory in
   each configured zone. GPU and spot capacity can change independently of
   Terraform configuration.
5. Use ACK Kubernetes 1.32 or later. The managed NVIDIA device-plugin lifecycle
   requires 1.32 or later.
6. Confirm that ACK offers `AliyunLinux3ContainerOptimized` for the selected
   Kubernetes version, architecture, and region. For IMDSv2, the resolved
   Alibaba Cloud Linux 3 Container-Optimized image must be release `20241226`
   or later, and installed ACK components must support cgroup v2 and IMDSv2.
7. Install Terraform 1.14 or later, the Aliyun CLI, `jq`, `kubectl`, and Helm.
8. Configure credentials through the standard Alicloud provider credential
   chain. Do not put access keys in Terraform files or state.
9. Ensure the machine used for `kubectl` and Helm can reach the private ACK API,
   either through an existing private network path or the optional bastion.

The optional ACR integration also requires an existing ACR Enterprise Edition
instance and working network and DNS connectivity from the cluster.

## Configure KMS encryption

ACK Secret envelope encryption is enabled by default. Select one of these KMS
configurations before planning.

### Use an existing rotating key

```hcl
create_ack_secret_kms_key = false
ack_secret_kms_key_id     = "replace-with-a-same-region-rotating-kms-key-id"
```

The key must resolve exactly once in the selected region and be Enabled,
`Aliyun_AES_256`, authorized for `ENCRYPT/DECRYPT`, and configured for automatic
rotation. The module uses the key but does not manage its lifecycle.

### Create a key in an existing software KMS instance

```hcl
ack_secret_kms_instance_id            = "replace-with-a-same-region-software-kms-instance-id"
ack_secret_kms_rotation_interval_days = 30
```

Leave `create_ack_secret_kms_key=true`. The module creates the cluster key in
the supplied instance. The rotation interval must be a whole number from 7
through 365 days. The software KMS instance remains outside this module.

### Use an active Default Key Rotation entitlement

```hcl
ack_secret_kms_default_rotation_entitled = true
```

Leave `create_ack_secret_kms_key=true`. Set this value only after the paid,
one-per-account-and-region entitlement is active. This option uses a fixed
365-day rotation interval. The module cannot purchase, renew, cancel, or import
the entitlement.

Automatic rotation is recommended. Setting
`ack_secret_kms_automatic_rotation_enabled=false` keeps KMS envelope encryption
enabled but creates the key without automatic rotation. In that configuration,
you are responsible for the key's rotation policy.

The `ack_secret_encryption.rotation_interval` output uses the provider's
canonical seconds format, such as `31536000s` for 365 days.

## Connect to ACK and install SIE

The module never creates a public ACK API endpoint. Use an existing private
network path or enable the optional bastion with an existing ECS key pair and
one canonical, globally routable operator `/32`. Retrieve kubeconfig with the
`kubeconfig_command` output and keep it in a protected temporary file outside
the module directory.

Install the SIE chart with its ACK values file and the Terraform outputs for
OSS and RRSA. Version `0.7.2` is the chart release tested with this module
version:

```bash
MODEL_CACHE_URL="$(terraform output -raw model_cache_bucket_url)"
PAYLOAD_STORE_URL="$(terraform output -raw payload_store_url)"
RRSA_ROLE_NAME="$(terraform output -raw rrsa_workload_role_name)"

helm pull oci://ghcr.io/superlinked/charts/sie-cluster --version 0.7.2 --untar
helm upgrade --install sie-cluster ./sie-cluster \
  --namespace sie \
  --create-namespace \
  --values ./sie-cluster/values-ack.yaml \
  --set workers.common.clusterCache.enabled=true \
  --set-string workers.common.clusterCache.url="${MODEL_CACHE_URL}" \
  --set-string payloadStore.url="${PAYLOAD_STORE_URL}" \
  --set-string serviceAccount.annotations."pod-identity\.alibabacloud\.com/role-name"="${RRSA_ROLE_NAME}"

unset MODEL_CACHE_URL PAYLOAD_STORE_URL RRSA_ROLE_NAME
```

The ACK chart values leave Ingress disabled. Install and secure an
ACK-compatible ingress controller before enabling Ingress.

## Model cache, payload store, and workload identity

The shared OSS bucket exposes two separate paths:

- `oss://<bucket>/models` stores model weights. The workload role can list and
  read this prefix but cannot modify it.
- `oss://<bucket>/payloads` stores work items that are too large for the queue.
  The workload role can list, read, write, and delete this prefix. OSS lifecycle
  rules remove current and noncurrent payload objects after the configured
  expiration period and abort incomplete multipart uploads.

Payload storage is required for requests over 1 MiB, including many image
requests. Keep `create_model_cache=true` unless you configure another supported
payload store when installing SIE.

ACK projects a short-lived OIDC token into the `sie-server` ServiceAccount.
The runtime exchanges that token for STS credentials and signs OSS requests
with region-scoped Signature V4. Node and bastion roles have no OSS permission,
metadata credential fallback is disabled, and no long-lived Alibaba Cloud
AccessKey is stored in Terraform, Helm, or a Kubernetes Secret.

OSS is not suitable for the mutable `sie-config` store because OSS PutObject
does not provide the required non-empty compare-and-swap operation. Keep
`sie-config` on the chart's local or PVC-backed store.

## Node pools and supported images

`AliyunLinux3ContainerOptimized` is the supported `image_type` for both system
and GPU pools. ACK resolves the concrete regional image; do not replace it with
a date-stamped image ID. This image family provides the cgroup v2 and IMDSv2
properties required by the module. Plain `AliyunLinux3` may resolve without
cgroup v2, and the provider's `ContainerOS` value does not select the required
GPU image family.

Changing a node pool's `image_type` can roll its nodes. Check replacement
capacity and workload disruption before applying the change. If node-pool
creation fails because inventory or quota is unavailable and no pool was
created, resolve the capacity issue and retry with the same Terraform state.

The default GPU pool uses on-demand capacity because Frankfurt spot inventory
can be intermittent. Spot pools are supported, but must keep
`compensate_with_on_demand=true`. Compensation can improve capacity but does
not guarantee it and may increase cost.

The default GPU system disk is 500 GiB. The SIE chart's model cache uses a
300 GiB `emptyDir` size limit on that root disk, leaving nominal space for
container images, logs, the operating system, and kubelet eviction thresholds.
The size limit does not reserve disk space.

System and GPU pools use distinct ECS-trusted RAM roles. You can supply an
existing system role with `system_node_ram_role_name` and per-GPU-pool roles
with `ram_role_name`; otherwise, the module creates dedicated roles. Node roles
do not receive OSS permissions because SIE accesses OSS through RRSA.

The Frankfurt A10 topology described above is the module's supported default.
Always recheck image metadata, quota, and instance inventory before deploying
it in another account or at a later date.

## Optional ACR Enterprise repositories

ACR repository creation is disabled by default and never creates a paid ACR
instance. To create private repositories in an existing Enterprise Edition
instance:

```hcl
enable_acr_repositories     = true
acr_enterprise_instance_id = "replace-with-an-existing-acr-ee-instance-id"
acr_registry_domain        = "replace-with-an-existing-acr-registry-hostname"
```

The module creates only the configured namespace and repositories. It does not
create or subscribe to an ACR instance, retrieve registry credentials, or
configure Kubernetes image-pull secrets. Configure VPC and DNS connectivity and
image-pull authentication separately.

## Key variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `alicloud_region` | `eu-central-1` | Alibaba Cloud region for all resources |
| `zones` | `eu-central-1a`, `eu-central-1c` | ACK and node-pool zones |
| `kubernetes_version` | ACK default | Kubernetes 1.32 or later |
| `deletion_protection` | `true` | Protect the ACK cluster from deletion |
| `system_node_pool` | `ecs.g7.xlarge`, 1-5 nodes | System-pool image, capacity, and disk |
| `gpu_node_pools` | A10, on-demand, 0-10 nodes | GPU-pool image, capacity, disk, and RAM role |
| `create_model_cache` | `true` | Create the OSS model-cache and payload-store bucket |
| `model_cache_force_destroy` | `false` | Delete OSS object versions during bucket destruction |
| `ack_secret_encryption_enabled` | `true` | Encrypt ACK Secrets with KMS |
| `ack_secret_kms_default_rotation_entitled` | `false` | Confirm an active Default Key Rotation entitlement |
| `ack_secret_kms_instance_id` | `null` | Existing software KMS instance for a new key |
| `ack_secret_kms_rotation_interval_days` | `365` | Rotation interval for a software KMS instance key |
| `audit_logging_enabled` | `true` | Send ACK audit and control-plane logs to SLS |
| `bastion_enabled` | `false` | Create a restricted SSH path to the private API |
| `enable_acr_repositories` | `false` | Create repositories in an existing ACR EE instance |

See the Registry **Inputs** tab or `variables.tf` for the complete typed
interface and validation rules.

## Outputs

| Output | Description |
| --- | --- |
| `cluster_id` | ACK cluster ID |
| `kubeconfig_command` | Aliyun CLI command for a renewable private kubeconfig |
| `model_cache_bucket_url` | `oss://` URL to pass to `workers.common.clusterCache.url` |
| `payload_store_url` | `oss://` URL to pass to `payloadStore.url` |
| `rrsa_workload_role_name` | RAM role for the pod-identity ServiceAccount annotation |
| `gpu_node_pools` | GPU pool IDs, instance types, capacity, disk, and purchase mode |
| `ack_secret_encryption` | KMS key ID, creation mode, deletion protection, and rotation settings |
| `audit_logging` | SLS project, retention, and enabled control-plane components |
| `bastion_connection` | Sensitive connection details for the optional bastion |
| `acr_repositories` | Optional ACR repository IDs and endpoints |

Additional outputs expose the cluster name and private endpoint, networking
IDs, node roles, OSS endpoint, and RRSA identity details.

## Costs and cleanup

ACK Pro, the system node, NAT gateway, EIP, OSS, SLS, and KMS can incur charges
even when the GPU pool has scaled to zero. The optional bastion and an existing
ACR Enterprise Edition instance can add cost. Check current Alibaba Cloud
pricing for the selected region before applying.

The defaults protect the ACK cluster and a module-created KMS key, and retain
OSS object versions. Before destroying a cluster, update the configuration as
needed:

```hcl
deletion_protection                 = false
ack_secret_kms_deletion_protection = false
# Set true only when all versions in the module-created bucket should be deleted.
model_cache_force_destroy = true
```

Apply those changes first, then run `terraform destroy`. A module-created KMS
key enters `PendingDeletion` for its configured 7-30 day window instead of
disappearing immediately. Existing KMS instances, entitlements, ACR instances,
and other external prerequisites are not removed by this module. After destroy,
check the selected account and region for retained resources and pending KMS
key deletion.
