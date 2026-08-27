# Alibaba Cloud Frankfurt A10 example

This public example consumes the version-matched Alibaba Cloud Registry module
and creates its ordinary ACK Pro topology in `eu-central-1`: two zones, an
`ecs.g7.xlarge` system pool, and an on-demand
`ecs.gn7i-c8g1.2xlarge` A10 24 GiB GPU pool that scales from zero to ten nodes.
Both pools use the ACK-resolved
`AliyunLinux3ContainerOptimized` family so Kubernetes gets cgroup v2 while the
module keeps IMDSv2 required.

Read the module [README](../../README.md) before applying. The selected account
and region must already have ACK, KMS, OSS, and SLS enabled, Alibaba's required
ACK/NAT/Auto Scaling/OOS service roles established, sufficient quota/current
ECS inventory, and a Terraform principal that can create and pass the module
roles. Those caller-owned landing-zone prerequisites are outside this example.

## Select a KMS authority

The module encrypts ACK Secrets and requires automatic key rotation by default.
Copy the placeholder values file and choose exactly one recipe:

```bash
cp terraform.tfvars.example terraform.tfvars
```

1. Use an existing rotating key:

   ```hcl
   create_ack_secret_kms_key = false
   ack_secret_kms_key_id     = "replace-with-a-same-region-rotating-kms-key-id"
   ```

   The module reads the key and admits it only when exactly one key is Enabled,
   `Aliyun_AES_256`, `ENCRYPT/DECRYPT`, and automatic rotation is Enabled. The
   caller retains its lifecycle and rotation.

2. Create the cluster key in a caller-owned software KMS instance:

   ```hcl
   ack_secret_kms_instance_id            = "replace-with-a-same-region-software-kms-instance-id"
   ack_secret_kms_rotation_interval_days = 30
   ```

   The interval must be an integer from 7 through 365 days. The caller
   provisions and retains the software KMS instance.

3. Use an already-effective regional Default Key Rotation entitlement:

   ```hcl
   ack_secret_kms_default_rotation_entitled = true
   ```

   Set this attestation only after the one-per-account/region paid entitlement
   exists. This path is fixed at 365 days.

Neither this example nor the reusable module orders, purchases, imports,
renews, cancels, or otherwise manages a KMS subscription or value-added
entitlement. Leaving all three recipes unselected fails closed at plan.

## Apply

Replace the active cluster-name placeholder and any optional caller-owned
inputs, then review a saved plan:

```bash
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

The example deliberately keeps the module's production lifecycle defaults:
ACK and module-created KMS deletion protection remain enabled, the KMS
pending-deletion window remains 30 days, and OSS force deletion remains off.
It does not create a public ACK API endpoint or enable the optional SSH
bastion.

The system and GPU image inputs default to
`AliyunLinux3ContainerOptimized`. The example rejects plain `AliyunLinux3` and
other unreviewed families; do not substitute a date-stamped image ID. ACK owns
regional image resolution. Changing an existing pool's image type can roll its
nodes, so review disruption and capacity before applying such a change.

`ecs_key_name` and `system_node_ram_role_name` are optional caller-owned
inputs. If ACR repositories are needed, set all three existing-instance inputs:

```hcl
enable_acr_repositories     = true
acr_enterprise_instance_id = "replace-with-an-existing-acr-ee-instance-id"
acr_registry_domain        = "replace-with-an-existing-acr-registry-hostname"
```

This creates repositories only. It does not create an ACR Enterprise Edition
subscription, discover registry credentials, or configure Kubernetes image
pull access.

## Install SIE

Reach the private ACK API through a caller-managed private network path. The
`kubeconfig_command` output retrieves a renewable short-lived kubeconfig; keep
the resulting file mode 0600 outside the repository and remove it after use.

Install the Helm chart with `values-ack.yaml`, then pass:

- `model_cache_bucket_url` to `workers.common.clusterCache.url`;
- `payload_store_url` to `payloadStore.url`; and
- `rrsa_workload_role_name` to the
  `pod-identity.alibabacloud.com/role-name` ServiceAccount annotation.

Pull the chart at the same release version as this module, unpack it so the
packaged ACK overlay is available, and install it with the Terraform-derived
OSS and RRSA values:

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

The native OSS storage paths use RRSA short-lived credentials and OSS Signature
V4. The workload role can read `models/`, and read/write/delete `payloads/`.
Node roles receive no OSS policy. Keep mutable `sie-config` data on its
local/PVC store because OSS does not satisfy the required compare-and-swap
contract.

Ingress stays disabled until the caller installs and secures an ACK-compatible
controller. The default A10 disk is 500 GiB, leaving nominal headroom over the
chart's 300 GiB node-backed cache for images, logs, the operating system, and
kubelet eviction thresholds.

## Cleanup and costs

ACK Pro, the system node, NAT gateway, EIP, OSS, SLS, and KMS can incur charges
while the GPU pool is at zero. Review current pricing before applying.

Decommissioning requires an explicit reviewed lifecycle change because the
safe defaults protect the ACK cluster and module-created KMS key and retain OSS
versions. A deleted module-created key can remain in `PendingDeletion` for its
configured window. Independently inventory the provider after destroy rather
than treating an empty Terraform state as proof of absence.
