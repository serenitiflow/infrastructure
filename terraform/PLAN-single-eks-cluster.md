# Plan: Single Shared EKS Cluster with Namespace-Based Environment Separation

## Context

**Current state:** All existing infrastructure has been destroyed. This is a **clean new setup** in **`eu-central-1`**.

The goal is to build a **single shared EKS cluster** where environments are separated by Kubernetes namespaces (`dev-serenity`, `prod-serenity`). Environment-specific AWS resources (Aurora, Redis, Secrets Manager) remain provisioned per environment with their existing prefixes. EKS workloads in the `dev` namespace connect to `dev-aurora`, and workloads in the `prod` namespace connect to `prod-aurora`.

**Status:** All phases implemented. Review completed (46 findings). See [`PLAN-single-eks-cluster_review_feedback.md`](PLAN-single-eks-cluster_review_feedback.md) and [`PLAN-single-eks-cluster_todo.md`](PLAN-single-eks-cluster_todo.md) for details.

---

## Decision: VPC Placement of the Shared EKS Cluster

**Chosen approach: Option A - Reuse dev VPC for shared EKS**

- Keep EKS cluster in dev VPC's private subnets
- Create VPC peering connection: dev VPC ↔ prod VPC
- Add routing rules so EKS pods (in dev VPC) can reach prod Aurora/Redis (in prod VPC)
- Rationale: No new VPC to manage, no 3rd NAT, simplest path for a single-account setup

---

## Phase 1: Make the Common EKS Cluster Truly Shared

**Status: Complete**

All files created/modified as specified. EKS module now writes to `/serenity/shared/eks/*` SSM paths and reads VPC/subnets from dev networking via `networking_environment` variable.

### 1.1 Update `envs/common/eks/` to be environment-agnostic

**Files:**
- `infrastructure/terraform/envs/common/eks/terraform.tfvars`
  - Change `environment = "dev"` to `environment = "shared"`
- `infrastructure/terraform/envs/common/eks/backend.tf`
  - Change state key from `dev/eks/terraform.tfstate` to `common/eks/terraform.tfstate`

### 1.2 Update EKS module SSM output paths

**File:** `infrastructure/terraform/modules/eks/main.tf`

Change all `aws_ssm_parameter` resources from:
```hcl
name = "/${var.project_name}/${var.environment}/eks/..."
```
to:
```hcl
name = "/${var.project_name}/shared/eks/..."
```

### 1.3 Update EKS module data sources to read from dev networking

**File:** `infrastructure/terraform/modules/eks/data.tf`

Add a `networking_environment` variable so the module reads VPC/subnets from the correct environment's SSM paths:

```hcl
variable "networking_environment" {
  description = "Environment whose VPC/subnets to use for the cluster"
  type        = string
  default     = "dev"
}

data "aws_ssm_parameter" "vpc_id" {
  name = "/${var.project_name}/${var.networking_environment}/networking/vpc_id"
}

data "aws_ssm_parameter" "private_subnet_ids" {
  name = "/${var.project_name}/${var.networking_environment}/networking/private_subnet_ids"
}

data "aws_ssm_parameter" "public_subnet_ids" {
  name = "/${var.project_name}/${var.networking_environment}/networking/public_subnet_ids"
}
```

---

## Phase 2: Enable Cross-VPC Database Access (VPC Peering)

**Status: Complete**

VPC peering stack created under `envs/dev/vpc-peering-prod/`. Routes both directions between dev and prod private subnets. Databases use shared EKS cluster SG for ingress.

### 2.1 Create VPC peering between dev and prod

**New stack:** `infrastructure/terraform/envs/dev/vpc-peering-prod/`

```hcl
resource "aws_vpc_peering_connection" "dev_to_prod" {
  vpc_id        = data.aws_ssm_parameter.dev_vpc_id.value
  peer_vpc_id   = data.aws_ssm_parameter.prod_vpc_id.value
  peer_owner_id = data.aws_caller_identity.current.account_id
  auto_accept   = true

  tags = {
    Name = "serenity-dev-to-prod"
  }
}

# Dev private route tables → prod CIDR
resource "aws_route" "dev_to_prod" {
  for_each                  = toset(local.dev_private_route_table_ids)
  route_table_id            = each.value
  destination_cidr_block    = data.aws_ssm_parameter.prod_vpc_cidr.value
  vpc_peering_connection_id = aws_vpc_peering_connection.dev_to_prod.id
}

# Prod private route tables → dev CIDR
resource "aws_route" "prod_to_dev" {
  for_each                  = toset(local.prod_private_route_table_ids)
  route_table_id            = each.value
  destination_cidr_block    = data.aws_ssm_parameter.dev_vpc_cidr.value
  vpc_peering_connection_id = aws_vpc_peering_connection.dev_to_prod.id
}
```

### 2.2 Update database modules to use shared EKS SG

**File:** `infrastructure/terraform/modules/databases/data.tf`

Add a data source for the shared EKS cluster security group:

```hcl
data "aws_ssm_parameter" "shared_cluster_security_group_id" {
  name = "/${var.project_name}/shared/eks/cluster_security_group_id"
}
```

**File:** `infrastructure/terraform/modules/databases/main.tf`

Update Aurora and Redis security group rules to use the shared cluster SG:

```hcl
# Aurora
security_group_rules = {
  eks_ingress = {
    source_security_group_id = data.aws_ssm_parameter.shared_cluster_security_group_id.value
    description              = "PostgreSQL from shared EKS"
  }
}

# Redis
security_group_rules = {
  eks_ingress = {
    referenced_security_group_id = data.aws_ssm_parameter.shared_cluster_security_group_id.value
    description                  = "Redis from shared EKS"
  }
}
```

---

## Phase 3: Kubernetes Namespaces and Service Accounts

**Status: Complete**

Both `dev-serenity` and `prod-serenity` namespaces created. Service accounts created with IRSA role ARNs. Dev SA placeholder `<ACCOUNT_ID>` replaced with actual account ID.

### 3.1 Create prod namespace and service account

**New file:** `infrastructure/k8s/prod/namespace.yaml`
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: prod-serenity
  labels:
    environment: prod
    project: serenity
```

**New file:** `infrastructure/k8s/prod/serviceaccount.yaml`
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: serenity-services
  namespace: prod-serenity
  annotations:
    eks.amazonaws.com/role-arn: "arn:aws:iam::692046683886:role/prod-serenity-services-role"
```

### 3.2 Fix dev service account

**File:** `infrastructure/k8s/dev/serviceaccount.yaml`
- Replace `<ACCOUNT_ID>` placeholder with `692046683886`

---

## Phase 4: IRSA Roles (Terraform)

**Status: Complete**

IRSA module created at `modules/irsa/`. Shared stack at `envs/common/irsa/` instantiates dev and prod roles. Role ARNs written to SSM for CI/CD reference.

### 4.1 Create IRSA module

**New module:** `infrastructure/terraform/modules/irsa/main.tf`

Creates an IAM role with trust policy scoped to a specific namespace's service account:

```hcl
locals {
  oidc_provider = replace(var.oidc_issuer_url, "https://", "")
}

resource "aws_iam_role" "namespace_services" {
  name = "${var.project_name}-${var.environment}-services-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.oidc_provider}"
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_provider}:aud" = "sts.amazonaws.com"
          "${local.oidc_provider}:sub" = "system:serviceaccount:${var.namespace}:serenity-services"
        }
      }
    }]
  })
}

# Policy: read env-specific Secrets Manager secrets
resource "aws_iam_role_policy" "secrets_read" {
  name = "${var.project_name}-${var.environment}-secrets-read"
  role = aws_iam_role.namespace_services.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ]
      Resource = "arn:aws:secretsmanager:*:${data.aws_caller_identity.current.account_id}:secret:${var.project_name}/${var.environment}/*"
    }]
  })
}
```

### 4.2 Instantiate IRSA for both environments

**New stack:** `infrastructure/terraform/envs/common/irsa/main.tf`

```hcl
module "irsa_dev" {
  source = "../../../modules/irsa"

  project_name    = var.project_name
  environment     = "dev"
  namespace       = "dev-serenity"
  oidc_issuer_url = data.aws_ssm_parameter.oidc_issuer_url.value
}

module "irsa_prod" {
  source = "../../../modules/irsa"

  project_name    = var.project_name
  environment     = "prod"
  namespace       = "prod-serenity"
  oidc_issuer_url = data.aws_ssm_parameter.oidc_issuer_url.value
}

# Write role ARNs to SSM for CI/CD reference
resource "aws_ssm_parameter" "dev_irsa_role_arn" {
  name  = "/${var.project_name}/dev/eks/irsa_services_role_arn"
  type  = "String"
  value = module.irsa_dev.role_arn
}

resource "aws_ssm_parameter" "prod_irsa_role_arn" {
  name  = "/${var.project_name}/prod/eks/irsa_services_role_arn"
  type  = "String"
  value = module.irsa_prod.role_arn
}
```

---

## Phase 5: Application Deployment Manifests

**Status: Complete (with known issues to fix)**

Prod deployment manifest created. Both dev and prod ConfigMaps have placeholder endpoints that must be replaced with actual Aurora/Redis endpoints after infrastructure is deployed.

### 5.1 Environment-specific ConfigMaps

**Current issue:** `platform-user-service/config/k8s/dev/deployment.yaml` hardcodes database hostnames.

**Fix:** Create environment-specific ConfigMaps with correct Aurora/Redis endpoints.

**New file:** `platform-user-service/config/k8s/prod/configmap.yaml`
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: platform-user-service-config
  namespace: prod-serenity
data:
  DATABASE_URL: "jdbc:postgresql://PROD_AURORA_ENDPOINT:5432/serenity"
  REDIS_HOST: "PROD_REDIS_ENDPOINT"
  REDIS_PORT: "6379"
  REDIS_USERNAME: "default"
  SPRING_PROFILES_ACTIVE: "prod"
```

### 5.2 Environment-specific Secrets

Each namespace needs its own K8s Secret with credentials from the correct environment's Secrets Manager secret.

---

## Phase 6: CI/CD Workflow Updates

**Status: Complete (with known issues to fix)**

Workflow updated with unified `eks-cluster-name` input, separate namespace inputs for dev/prod, and a new `deploy-prod-eks` job. `kubectl apply` path needs fixing to target `config/k8s/dev/` and `config/k8s/prod/`.

### 6.1 Update `microservice-deploy.yml`

**File:** `infrastructure/.github/workflows/microservice-deploy.yml`

1. Unify EKS cluster name:
   - Replace `eks-cluster-dev` and `eks-cluster-prod` with a single `eks-cluster-name` input (default: `serenity-shared-cluster`)

2. Add prod EKS deployment job:
   - Target namespace: `prod-serenity`

3. Parameterize namespace:
   ```yaml
   eks-namespace:
     description: 'Target EKS namespace'
     required: false
     default: 'dev-serenity'
   ```

---

## Critical Files Status

| File | Status | Notes |
|------|--------|-------|
| `terraform/modules/eks/main.tf` | Done | SSM paths updated to `/serenity/shared/eks/*` |
| `terraform/modules/eks/data.tf` | Done | `networking_environment` variable added |
| `terraform/envs/common/eks/terraform.tfvars` | Done | `environment = "shared"` |
| `terraform/envs/common/eks/backend.tf` | Done | State key: `common/eks/terraform.tfstate` |
| `terraform/modules/databases/data.tf` | Done | Reads shared EKS cluster SG |
| `terraform/modules/databases/main.tf` | Done | Uses shared EKS SG for Aurora/Redis ingress |
| `terraform/envs/dev/vpc-peering-prod/` | Done | Peering + routes created |
| `terraform/modules/irsa/` | Done | IRSA role module created |
| `terraform/envs/common/irsa/` | Done | Dev + prod IRSA roles |
| `infrastructure/k8s/prod/namespace.yaml` | Done | `prod-serenity` namespace |
| `infrastructure/k8s/prod/serviceaccount.yaml` | Done | Prod IRSA service account |
| `infrastructure/k8s/dev/serviceaccount.yaml` | Done | `<ACCOUNT_ID>` replaced |
| `.github/workflows/microservice-deploy.yml` | Done | Shared cluster + namespace params |
| `platform-user-service/config/k8s/prod/deployment.yaml` | Done | Prod manifest created (placeholders remain) |

---

## Post-Implementation Review

A full code review was conducted after implementation. **46 findings** were identified across 4 categories:
- **11 Critical** — must fix before deployment
- **20 Warnings** — should address soon
- **15 Suggestions** — nice-to-have improvements

See the full reports:
- [`PLAN-single-eks-cluster_review_feedback.md`](PLAN-single-eks-cluster_review_feedback.md) — detailed findings by category
- [`PLAN-single-eks-cluster_todo.md`](PLAN-single-eks-cluster_todo.md) — actionable checklist

### Top critical fixes remaining
1. **Subnet CIDRs are hardcoded** — networking module uses `10.0.x.0/24` regardless of `vpc_cidr` value
2. **NAT instance `private_cidr` is hardcoded** — always `10.0.0.0/16`
3. **Prod deployment uses `latest` image tag**
4. **Prod ConfigMap has placeholder endpoints** (`PROD_AURORA_ENDPOINT`, `PROD_REDIS_ENDPOINT`)
5. **CI/CD `kubectl apply` path is wrong** — applies `config/k8s/` instead of `config/k8s/dev/` or `config/k8s/prod/`
6. **No HTTPS on ALB** — HTTP only on internet-facing load balancer
7. **Placeholder credentials in `docker-registry-secret.yaml`** — risk of committing real secrets
8. **JWT keys in ConfigMaps** — should be in Secrets; same key in dev and prod
9. **No NetworkPolicies** — default allow-all between pods across namespaces
10. **No Pod Security Admission labels** — namespaces don't enforce security standards

---

## Clean Slate Deployment Order

Since all infrastructure has been destroyed, apply in this order:

1. `dev/01-networking` + `prod/01-networking` (parallel)
2. `dev/vpc-peering-prod`
3. `common/eks`
4. `dev/03-databases` + `prod/03-databases` (parallel, needs shared EKS SG)
5. `common/irsa`
6. Apply K8s namespaces and service accounts
7. Update ConfigMaps with real Aurora/Redis endpoints
8. Deploy applications

---

## Rollback Plan

If issues occur:
1. Revert `modules/databases/main.tf` to use per-environment EKS SG
2. Delete VPC peering connection and routes
3. Services can still deploy via Coolify (primary target)

---

## Cost Impact

| Item | Before | After | Savings |
|------|--------|-------|---------|
| EKS Control Plane | $73/mo x 2 = $146/mo | $73/mo x 1 = $73/mo | **$73/mo** |
| VPC Peering | $0 | ~$0.01/GB data transfer | Negligible |
| **Net savings** | | | **~$73/mo** |
