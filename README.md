# SIE Alibaba Cloud ACK Terraform Module

This module creates the Alibaba Cloud substrate for an SIE cluster. Terraform
owns the VPC, private-node egress, ACK Pro cluster, CPU and GPU node pools, ACK
autoscaling, native OSS model/payload storage, per-pool and RRSA RAM roles, ACK
Secret KMS encryption, SLS control-plane/audit logging, the managed NVIDIA and
pod-identity add-ons, an optional SSH bastion, and optional repositories in an
existing ACR Enterprise Edition instance. Deploy the SIE runtime separately
with the `sie-cluster` Helm chart.

The default deployment uses Frankfurt (`eu-central-1`) across
`eu-central-1a` and `eu-central-1c`. It creates one `ecs.g7.xlarge` system pool
and one on-demand `ecs.gn7i-c8g1.2xlarge` GPU pool with an NVIDIA A10 24 GiB.
The GPU pool scales from zero to ten nodes and uses a 500 GiB system disk. Both
pools default to ACK-resolved `AliyunLinux3ContainerOptimized` images.

## What the module creates

- An explicit VPC with separate system and GPU vSwitches in both zones.
- An Enhanced Internet NAT gateway, pay-as-you-go EIP, association, and one
  SNAT entry per vSwitch for private-node egress.
- A deletion-protected, private-API ACK Pro cluster using Flannel with separate
  pod and service CIDRs.
- ACK CSI components and the managed `ack-nvidia-device-plugin` add-on.
- ACK RRSA plus the managed `ack-pod-identity-webhook`, with an exact
  namespace/ServiceAccount OIDC trust policy.
- Autoscaling system and GPU node pools with encrypted ESSD system disks using
  distinct ECS-trusted RAM roles, plus ACK cluster-autoscaler settings.
- One private, Block-Public-Access, AES-256 encrypted and versioned OSS bucket:
  read-only model weights under `models/` and read/write payloads under
  `payloads/`, with current/noncurrent and multipart lifecycle cleanup.
- A rotating `Aliyun_AES_256` KMS key for ACK Secret envelope encryption, or an
  explicitly supplied existing same-region rotating key.
- One uniquely named SLS project for ACK API audit and Pro control-plane logs.
- An optional state-owned SSH bastion that exposes only TCP/22 from one exact
  operator `/32`; the ACK API itself remains private.
- Optional private repositories inside an existing ACR Enterprise Edition
  instance.

The module does not deploy Kubernetes workloads, create an ACR subscription,
retrieve registry tokens, activate account-wide services, create Alibaba
service roles, retrieve/store kubeconfig credentials, or purchase a KMS
subscription.

## Prerequisites

Before applying, enable ACK, KMS, OSS, and SLS in the selected account and
region, establish Alibaba's required ACK/NAT/Auto Scaling/OOS service roles,
and grant the Terraform principal the documented create/pass/use permissions.
These account-wide prerequisites are not owned by this reusable module.

Also confirm:

1. ACK Kubernetes 1.32 or later is available. Managed lifecycle for the
   `ack-nvidia-device-plugin` add-on requires 1.32 or later.
2. ACK metadata for the selected Kubernetes version and region offers the
   `AliyunLinux3ContainerOptimized` x86_64 family. Alibaba Cloud Linux 3
   Container-Optimized images must be release `20241226` or later for IMDSv2;
   they use cgroup v2. Every installed ACK component must support IMDSv2-only
   nodes.
3. ACK Pro, VPC, vSwitch, NAT gateway, EIP, ECS, OSS, KMS, and SLS quotas are
   sufficient in `eu-central-1`.
4. `ecs.g7.xlarge` and `ecs.gn7i-c8g1.2xlarge` are currently available in both
   configured zones. GPU and spot inventory changes over time.
5. Terraform 1.14 or newer, Aliyun CLI, `jq`, `kubectl`, and Helm are installed.
6. Provider credentials use the standard Alicloud provider credential chain.
   Never put access keys in Terraform files or state.

## Public example

The real public example keeps production lifecycle defaults and exposes only
caller-owned account inputs:

```bash
cd examples/dev-gn7i
cp terraform.tfvars.example terraform.tfvars
# Replace placeholders and select exactly one KMS authority recipe.
terraform init
terraform plan
terraform apply
```

The example uses the module's ordinary system and GPU pool defaults. It does
not enable the optional bastion, weaken cluster/KMS deletion protection, or
enable OSS force deletion. Its tfvars template deliberately selects no KMS
authority, so an unedited copy fails closed at plan.

## ACK Secret KMS authority

ACK Secret envelope encryption is enabled by default, and automatic rotation
is the parity posture. Select exactly one authority before planning:

1. **Existing rotating key:** set `create_ack_secret_kms_key=false` and
   `ack_secret_kms_key_id=<same-region-key-id>`. The module reads the key and
   fails unless exactly one key is Enabled, `Aliyun_AES_256`,
   `ENCRYPT/DECRYPT`, and automatic rotation is Enabled. The caller owns that
   key's lifecycle and rotation.
2. **Existing software KMS instance:** leave key creation enabled and set
   `ack_secret_kms_instance_id=<same-region-instance-id>`, automatic rotation
   enabled, and an integral 7-365 day interval. The caller provisions and
   retains the KMS instance; the module creates only the cluster key in it.
3. **Pre-existing Default Key Rotation entitlement:** leave key creation
   enabled and set `ack_secret_kms_default_rotation_entitled=true` only after
   the one-per-account/region paid entitlement is already effective. This path
   is fixed at 365 days.

The public module does not order, purchase, import, renew, cancel, or otherwise
manage a KMS subscription or value-added entitlement. The attestation is a
fail-closed prerequisite, not purchase authorization. Setting
`ack_secret_kms_automatic_rotation_enabled=false` keeps envelope encryption but
is an explicit documented non-parity exception.

The input remains an integral day count. The diagnostic
`ack_secret_encryption.rotation_interval` output uses KMS's canonical seconds
representation (for example, `31536000s` for 365 days), matching read-after-write
state and avoiding a perpetual equivalent-duration diff.

## Native OSS and RRSA contract

Terraform exposes `oss://<bucket>/models` and `oss://<bucket>/payloads`.
The workload role can list/read only `models/`; it can list/read/write/delete
only `payloads/`. No node or bastion role receives OSS access. ACK projects a
short-lived OIDC token into pods using the shared `sie-server` ServiceAccount;
the runtime exchanges it for STS credentials and uses native OSS Signature V4.
No long-lived Alibaba AccessKey belongs in Terraform, Helm, or a Kubernetes
Secret.

The managed pod-identity webhook keeps `AutoInjectSTSEnvVars=false`: core RRSA
role/provider/token injection remains enabled, while the runtime derives and
pins the official STS endpoint instead of accepting an injected endpoint
override.

Alibaba OSS rejects concurrent bucket-control mutations. Terraform therefore
applies the private ACL, Block Public Access, AES-256 encryption, and versioning
in one explicit dependency chain after bucket creation. Keep that ordering when
changing storage controls.

`oss://` is deliberately not valid for the mutable `sie-config` epoch store:
OSS PutObject cannot implement its non-empty compare-and-swap contract. Keep
`sie-config` on the chart's local/PVC store. This does not affect model-cache or
large-payload support.

## Helm wiring

The API server is private-only. Reach it through an existing private network
path, or explicitly configure the optional module bastion with an existing ECS
key pair and one canonical globally routable operator `/32`. The module never
adds a public ACK API endpoint. Terraform returns a renewable Aliyun CLI
command, not kubeconfig contents; store any retrieved kubeconfig in a protected
temporary file outside the repository.

Install the chart with the ACK overlay and pass only the runtime values derived
from Terraform outputs:

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
```

Unset the shell variables after installation. The ACK overlay leaves Ingress
disabled because neither this module nor the chart installs an ingress
controller for ACK. Install and secure a compatible controller before enabling
Ingress.

## Node image contract

Each system/GPU pool has an explicit `image_type`. The safe default and current
fail-closed allowlist contain only `AliyunLinux3ContainerOptimized`: ACK resolves
the concrete regional image, so Terraform does not pin a date-stamped image ID.
This family is the only provider-1.289 option currently verified across the
module's declared ACK range for x86_64, cgroup v2, IMDSv2, and the mixed
CPU/A10 topology.

Before changing Kubernetes versions or regions, re-check Alibaba's
[ACK version metadata API](https://www.alibabacloud.com/help/doc-detail/2668189.html),
[Alibaba Cloud Linux 3 Container-Optimized image contract](https://www.alibabacloud.com/help/en/ack/ack-managed-and-ack-dedicated/user-guide/alibaba-cloud-linux-3-container-optimized-image-overview),
and [IMDSv2 image floor](https://www.alibabacloud.com/help/en/ack/ack-managed-and-ack-dedicated/security-and-compliance/secure-access-to-ecs-instance-metadata).

Plain `AliyunLinux3` is intentionally rejected because ACK can resolve it to an
image without cgroup v2. `ContainerOS` is not admitted because the provider's
accepted value selects the non-GPU family, while the GPU-specific ACK metadata
value is not accepted by the pinned provider. Other families remain closed
until the same Kubernetes-version, region, GPU, cgroup-v2, and IMDSv2 contract
is proven.

Changing `image_type` on an existing node pool is an ACK node-pool update and
can roll nodes. Review capacity and disruption before changing it. The
Terraform resource addresses do not change, and a failed create with no node
pool in state can be retried from the same state without state surgery.

## GPU capacity and node identity

The default GPU pool is on-demand because Frankfurt spot inventory is not
reliable. Spot remains an explicit override and must keep
`compensate_with_on_demand=true`. Compensation improves the chance of obtaining
capacity but does not guarantee inventory and can increase cost.

The default GPU system disk is 500 GiB. The chart's model cache is a 300 GiB
`emptyDir` size limit on that root disk, leaving nominal headroom for images,
logs, the operating system, and kubelet eviction thresholds. The size limit
does not reserve disk space.

Both system and GPU pools require IMDSv2 tokens and use distinct ECS-trusted
roles. Existing centrally managed roles can be selected with
`system_node_ram_role_name` and each GPU pool's `ram_role_name`. These roles
intentionally receive no OSS policy; the pod-level RRSA workload role is
separate.

## Optional ACR Enterprise repositories

ACR support is disabled by default and never creates a paid instance. Supply an
existing Enterprise Edition instance ID and its registry hostname to create
only private namespaces/repositories:

```hcl
enable_acr_repositories     = true
acr_enterprise_instance_id = "replace-with-existing-instance-id"
acr_registry_domain        = "replace-with-registry-hostname"
```

The caller must separately provide working VPC/DNS reachability and Kubernetes
image-pull credentials. Repository creation alone does not make private images
pullable.

## Important variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `alicloud_region` | `eu-central-1` | Alibaba Cloud region |
| `zones` | `eu-central-1a`, `eu-central-1c` | ACK and node-pool zones |
| `deletion_protection` | `true` | Protect the ACK cluster from deletion |
| `system_node_ram_role_name` | `null` | Existing system-pool role; null creates one |
| `system_node_pool` | `ecs.g7.xlarge`, AL3 CO, 1-5 | System image and capacity |
| `gpu_node_pools` | A10, AL3 CO, on-demand, 0-10, 500 GiB | GPU image, capacity, and role override |
| `create_model_cache` | `true` | Private encrypted/versioned OSS bucket |
| `model_cache_force_destroy` | `false` | Retain object versions during normal deletion |
| `ack_secret_encryption_enabled` | `true` | KMS envelope encryption for ACK Secrets |
| `ack_secret_kms_default_rotation_entitled` | `false` | Attest an existing paid rotation authority |
| `ack_secret_kms_instance_id` | `null` | Existing software KMS instance authority |
| `ack_secret_kms_rotation_interval_days` | `365` | Instance key 7-365 days; default entitlement 365 |
| `audit_logging_enabled` | `true` | ACK audit/control-plane logs in SLS |
| `bastion_enabled` | `false` | Exact-/32 SSH path to the private API |
| `enable_acr_repositories` | `false` | Repositories in an existing ACR EE instance |

See the published module's `variables.tf` for the complete typed interface and
validation rules.

## Cleanup and cost warning

ACK Pro, the system node, NAT gateway, EIP, OSS, SLS, and KMS may incur charges
even when the GPU pool is at zero. The optional bastion and an existing ACR
Enterprise instance may add cost. Review current Alibaba Cloud pricing before
applying.

Production-safe defaults deliberately protect the cluster and a module-created
KMS key and retain OSS object versions. A decommission must be a reviewed,
explicit lifecycle change: first disable the relevant deletion protections,
apply that posture change, then destroy. A module-created KMS key enters
`PendingDeletion` for its configured 7-30 day window rather than disappearing
immediately. Independently inventory the selected account and region after a
decommission; never describe an empty Terraform state as proof that provider
resources are absent.

## Standalone publication

Stable SIE releases publish this closed projection to
`superlinked/terraform-alicloud-sie` and tag the same `vX.Y.Z` identity used by
the module source and Helm chart. The projection retains only the reusable
module, `examples/dev-gn7i`, tests, public configuration, and the destination's
license and optional changelog. Account bootstrap, live evidence, Terraform
state, locks, and internal examples remain private.

## Validation scope

The repository runs provider-schema validation and credential-free mocked plan
tests for the reusable module and public example. One point-in-time Frankfurt
deployment also proved the full ACK and A10 topology, KMS/SLS resources, and a
greater-than-1-MiB SDK image request through the RRSA-backed OSS payload
offload, fetch, cleanup, GPU inference, and 512-dimensional response path. That
past run does not guarantee future regional inventory, account quota, another
account's prerequisites, or provider convergence.
