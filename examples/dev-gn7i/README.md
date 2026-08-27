# Alibaba Cloud Frankfurt A10 example

This example deploys an ACK Pro cluster in `eu-central-1` across two zones. It
uses an `ecs.g7.xlarge` system pool and an on-demand
`ecs.gn7i-c8g1.2xlarge` GPU pool with one NVIDIA A10 24 GiB GPU per node. The
GPU pool scales from zero to ten nodes, and both pools use
`AliyunLinux3ContainerOptimized` with cgroup v2 and IMDSv2.

Read the module [README](../../README.md) before applying. Enable ACK, KMS,
OSS, and SLS, create Alibaba Cloud's required ACK/NAT/Auto Scaling/OOS service
roles, confirm quota and ECS inventory, and configure a Terraform principal
that can create and pass the module's RAM roles.

## Select a KMS configuration

The module encrypts ACK Secrets and enables automatic key rotation by default.
Copy the placeholder values file and select exactly one option:

```bash
cp terraform.tfvars.example terraform.tfvars
```

1. Use an existing rotating KMS key:

   ```hcl
   create_ack_secret_kms_key = false
   ack_secret_kms_key_id     = "replace-with-a-same-region-rotating-kms-key-id"
   ```

   The key must be in the selected region, Enabled, `Aliyun_AES_256`, authorized
   for `ENCRYPT/DECRYPT`, and configured for automatic rotation.

2. Create the cluster key in an existing software KMS instance:

   ```hcl
   ack_secret_kms_instance_id            = "replace-with-a-same-region-software-kms-instance-id"
   ack_secret_kms_rotation_interval_days = 30
   ```

   The interval must be a whole number from 7 through 365 days. This example
   creates the key but does not manage the software KMS instance.

3. Use an active regional Default Key Rotation entitlement:

   ```hcl
   ack_secret_kms_default_rotation_entitled = true
   ```

   Set this only after the paid, one-per-account-and-region entitlement is
   active. This option uses a fixed 365-day rotation interval.

Neither the example nor the module can purchase, renew, cancel, or import a KMS
subscription or value-added entitlement. The plan fails until one option is
selected.

## Apply

Set a unique `cluster_name` in `terraform.tfvars`, add any optional existing
resource IDs, and review a saved plan:

```bash
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

The defaults keep ACK and module-created KMS deletion protection enabled, use a
30-day KMS pending-deletion window, and retain OSS object versions. The example
does not create a public ACK API endpoint or enable the optional SSH bastion.

Both node pools must use `AliyunLinux3ContainerOptimized`. Do not substitute
plain `AliyunLinux3`, `ContainerOS`, or a date-stamped image ID. ACK selects the
concrete regional image. Changing the image type of an existing node pool can
roll nodes, so check capacity and disruption before applying the change.

`ecs_key_name` and `system_node_ram_role_name` can refer to existing resources.
To create private repositories in an existing ACR Enterprise Edition instance,
set all three ACR inputs:

```hcl
enable_acr_repositories     = true
acr_enterprise_instance_id = "replace-with-an-existing-acr-ee-instance-id"
acr_registry_domain        = "replace-with-an-existing-acr-registry-hostname"
```

This creates only the namespace and repositories. Configure the ACR
subscription, network and DNS connectivity, registry credentials, and
Kubernetes image-pull access separately.

## Install SIE

Reach the private ACK API through an existing private network path. The
`kubeconfig_command` output retrieves a renewable, short-lived kubeconfig. Save
it in a mode-0600 temporary file outside the repository and remove it after use.

Install the Helm chart with `values-ack.yaml`, then pass the Terraform outputs
for the model cache, payload store, and RRSA workload role. Version `0.7.2` is
the chart release tested with this module version:

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

The native OSS paths use Signature V4 and short-lived RRSA credentials. The
workload role can read `models/` and can read, write, and delete `payloads/`.
Payload storage is required for requests over 1 MiB. Node roles have no OSS
permission, and no long-lived AccessKey is stored in Terraform or Kubernetes.

Keep mutable `sie-config` data on its local or PVC-backed store because OSS
does not provide the required compare-and-swap operation. Ingress remains
disabled until you install and secure an ACK-compatible ingress controller.

The default A10 disk is 500 GiB, leaving nominal space beyond the chart's
300 GiB node-backed model-cache limit for images, logs, the operating system,
and kubelet eviction thresholds. That limit does not reserve disk space.

## Costs and cleanup

ACK Pro, the system node, NAT gateway, EIP, OSS, SLS, and KMS can incur charges
while the GPU pool is at zero. Check current pricing before applying.

To remove the example, first set `deletion_protection=false` and
`ack_secret_kms_deletion_protection=false`, then apply those changes. Set
`model_cache_force_destroy=true` as well if the module-created OSS bucket and
all object versions should be deleted. After the update, run:

```bash
terraform destroy
```

A module-created KMS key remains in `PendingDeletion` for its configured
window. After destroy, check the selected account and region for retained
resources and pending KMS key deletion.
