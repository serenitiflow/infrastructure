# Plan: Single Shared VPC for All Environments

> **Context:** Pivot from multi-VPC (dev + prod + peering) to a single shared VPC where all environments live. Environment separation moves from VPC boundaries to subnet boundaries (shared public/private subnets, per-environment database subnets) and Kubernetes namespaces.
>
> **Review Date:** 2026-04-20

---

## Architecture Overview

```
+-------------------------------------------------------------+
|                    Shared VPC: 10.0.0.0/16                  |
|                                                             |
|  +------------------+  +------------------+                |
|  | Public Subnets   |  | Private Subnets  |                |
|  | 10.0.101.0/24    |  | 10.0.1.0/24      |                |
|  | 10.0.102.0/24    |  | 10.0.2.0/24      |                |
|  | (ALB, NAT)       |  | (EKS nodes)      |                |
|  +------------------+  +------------------+                |
|                                                             |
|  +------------------+  +------------------+                |
|  | Dev DB Subnets   |  | Prod DB Subnets  |                |
|  | 10.0.201.0/24    |  | 10.0.211.0/24    |                |
|  | 10.0.202.0/24    |  | 10.0.212.0/24    |                |
|  | (Aurora, Redis)  |  | (Aurora, Redis)  |                |
|  +------------------+  +------------------+                |
|                                                             |
|  Single NAT (instance ~$4/mo)                               |
|  No VPC peering needed                                      |
|                                                             |
+-------------------------------------------------------------+
```

### Why This Simplifies Things

| Before (Multi-VPC) | After (Single VPC) |
|---|---|
| Dev VPC + Prod VPC + Peering | One VPC |
| 2 NATs (or NAT + Gateway) | 1 NAT |
| VPC peering routes + SGs | Intra-VPC routing (free, automatic) |
| Cross-VPC database access rules | Same-VPC security groups |
| `prod-networking/` stack | Deleted |
| `vpc-peering-prod/` stack | Deleted |
| Per-environment networking SSM | `shared/networking/` + `{env}/database_subnets` |

### Cost Impact

| Item | Before | After | Savings |
|---|---|---|---|
| NAT | Instance + Gateway (~$36/mo) | 1 Instance (~$4/mo) | **~$32/mo** |
| VPC Peering data transfer | ~$0.01/GB | $0 (same VPC) | Negligible |
| EKS Control Plane | $73/mo (shared) | $73/mo | $0 |
| **Net savings** | | | **~$32/mo** |

---

## Subnet Allocation

| Subnet | AZ1 | AZ2 | Purpose |
|---|---|---|---|
| Public | `10.0.101.0/24` | `10.0.102.0/24` | ALB, NAT, bastion |
| Private | `10.0.1.0/24` | `10.0.2.0/24` | EKS nodes (all envs) |
| Dev DB | `10.0.201.0/24` | `10.0.202.0/24` | Dev Aurora + Redis |
| Prod DB | `10.0.211.0/24` | `10.0.212.0/24` | Prod Aurora + Redis |
| Staging DB (future) | `10.0.221.0/24` | `10.0.222.0/24` | Future env |

All derived from `var.vpc_cidr` using `cidrsubnet()` for automatic allocation.

---

## Phase 1: Networking Module — Single Shared VPC

### 1.1 Update `modules/networking/main.tf`

**Changes:**
- Expand `database_subnets` to include ALL environment DB subnets
- Create custom `aws_db_subnet_group` per environment
- Write SSM params under `/shared/networking/` for VPC-level outputs
- Write per-environment SSM params for DB subnet IDs and DB subnet group names
- Add `environments` variable (list of environments to create DB subnets for)
- Tag DB subnets with `Environment = dev|prod` for filtering

**New subnet structure:**
```hcl
azs              = ["${var.aws_region}a", "${var.aws_region}b"]
public_subnets   = [cidrsubnet(var.vpc_cidr, 8, 101), cidrsubnet(var.vpc_cidr, 8, 102)]
private_subnets  = [cidrsubnet(var.vpc_cidr, 8, 1), cidrsubnet(var.vpc_cidr, 8, 2)]
database_subnets = concat(
  [for i, env in var.environments : cidrsubnet(var.vpc_cidr, 8, 200 + (i * 10) + 1)],
  [for i, env in var.environments : cidrsubnet(var.vpc_cidr, 8, 200 + (i * 10) + 2)],
)
```

Actually, simpler explicit list:
```hcl
database_subnets = [
  cidrsubnet(var.vpc_cidr, 8, 201),  # dev-db-az1
  cidrsubnet(var.vpc_cidr, 8, 202),  # dev-db-az2
  cidrsubnet(var.vpc_cidr, 8, 211),  # prod-db-az1
  cidrsubnet(var.vpc_cidr, 8, 212),  # prod-db-az2
]
```

**Custom DB subnet groups:**
```hcl
resource "aws_db_subnet_group" "dev" {
  name       = "${var.project_name}-dev-db-subnet-group"
  subnet_ids = [module.vpc.database_subnets[0], module.vpc.database_subnets[1]]
  tags = merge(local.common_tags, { Environment = "dev" })
}

resource "aws_db_subnet_group" "prod" {
  name       = "${var.project_name}-prod-db-subnet-group"
  subnet_ids = [module.vpc.database_subnets[2], module.vpc.database_subnets[3]]
  tags = merge(local.common_tags, { Environment = "prod" })
}
```

**SSM parameters (new paths):**
- `/serenity/shared/networking/vpc_id`
- `/serenity/shared/networking/vpc_cidr`
- `/serenity/shared/networking/private_subnet_ids`
- `/serenity/shared/networking/public_subnet_ids`
- `/serenity/dev/networking/database_subnet_ids`
- `/serenity/dev/networking/database_subnet_group_name`
- `/serenity/prod/networking/database_subnet_ids`
- `/serenity/prod/networking/database_subnet_group_name`

### 1.2 Update `modules/networking/variables.tf`

- Change `environment` default from `"dev"` to `"shared"`
- Remove `validation` that restricts to `dev|staging|prod` (or add `"shared"`)
- Add `environments` list variable: `["dev", "prod"]`

### 1.3 Update `modules/networking/outputs.tf`

- Add `dev_database_subnet_ids`, `prod_database_subnet_ids`
- Add `dev_database_subnet_group_name`, `prod_database_subnet_group_name`
- Keep existing outputs for compatibility

---

## Phase 2: Delete Obsolete Stacks

### 2.1 Delete `envs/prod-networking/`

No longer needed. Prod databases live in the shared VPC's prod DB subnets.

### 2.2 Delete `envs/dev/vpc-peering-prod/`

No longer needed. Everything is in one VPC.

### 2.3 Delete `modules/vpc-peering/` (if exists)

Clean up any peering-specific modules.

---

## Phase 3: Update Database Modules

### 3.1 Update `modules/aurora/data.tf`

Change VPC read from environment-specific to shared:

```hcl
data "aws_ssm_parameter" "vpc_id" {
  name = "/${var.project_name}/shared/networking/vpc_id"
}

# DB subnet group stays environment-specific
data "aws_ssm_parameter" "database_subnet_group_name" {
  name = "/${var.project_name}/${var.environment}/networking/database_subnet_group_name"
}
```

### 3.2 Update `modules/redis/data.tf`

Same pattern:

```hcl
data "aws_ssm_parameter" "vpc_id" {
  name = "/${var.project_name}/shared/networking/vpc_id"
}

# DB subnet IDs stay environment-specific
data "aws_ssm_parameter" "database_subnet_ids" {
  name = "/${var.project_name}/${var.environment}/networking/database_subnet_ids"
}
```

### 3.3 Security Group Rules

Aurora and Redis SG rules already reference the shared EKS cluster SG (`/serenity/shared/eks/cluster_security_group_id`). No change needed — intra-VPC traffic between EKS nodes and DB subnets is automatic within the same VPC.

Remove any VPC-peering-specific SG rules (none exist in current modules).

---

## Phase 4: Update EKS Module

### 4.1 Update `modules/eks/data.tf`

Change networking read from `var.networking_environment` (currently `"dev"`) to `"shared"`:

```hcl
data "aws_ssm_parameter" "vpc_id" {
  name = "/${var.project_name}/shared/networking/vpc_id"
}

data "aws_ssm_parameter" "private_subnet_ids" {
  name = "/${var.project_name}/shared/networking/private_subnet_ids"
}

data "aws_ssm_parameter" "public_subnet_ids" {
  name = "/${var.project_name}/shared/networking/public_subnet_ids"
}
```

The `networking_environment` variable can be removed or its default changed to `"shared"`.

### 4.2 EKS Module SSM Outputs

Already writes to `/serenity/shared/eks/*`. No change.

---

## Phase 5: Update Environment Stacks

### 5.1 Update `envs/common/networking/` (the shared VPC stack)

**`terraform.tfvars`:**
```hcl
project_name        = "serenity"
app                 = "serenity"
environment         = "shared"
aws_region          = "eu-central-1"
nat_gateway_enabled = false
nat_instance_type   = "t4g.nano"
vpc_cidr            = "10.0.0.0/16"
environments        = ["dev", "prod"]
```

**`backend.tf`:**
- Change state key from `dev/networking/terraform.tfstate` to `shared/networking/terraform.tfstate` (or `networking/terraform.tfstate`)

### 5.2 Update `envs/dev/03-aurora/`

No tfvars changes needed. The module's data sources now read VPC from `shared` and DB subnet group from `dev` automatically.

### 5.3 Update `envs/prod/03-aurora/`

Same — module handles the path resolution.

### 5.4 Update `envs/dev/04-redis/` and `envs/prod/04-redis/`

Same pattern.

### 5.5 Update `envs/common/eks/`

**`terraform.tfvars`:**
- `networking_environment = "shared"` (or remove the variable entirely)

### 5.6 Update `envs/common/eks-irsa/`

No changes needed. Reads OIDC from EKS (already shared).

---

## Phase 6: Update Scripts

### 6.1 Update `scripts/init-env.sh`

Remove networking copy logic. New environments are added by:
1. Adding the environment to `environments` list in `envs/common/networking/terraform.tfvars`
2. Re-applying the networking stack (adds DB subnets + subnet group)
3. Creating `envs/{new_env}/03-aurora/` and `04-redis/` from templates

Simplified script:
```bash
#!/bin/bash
# Initialize a new environment in the shared VPC
# Usage: ./scripts/init-env.sh <environment_name>
#
# New environments share the VPC but get their own DB subnets.
# Run this AFTER adding the environment to envs/common/networking/terraform.tfvars
# and applying the networking stack.
```

---

## Phase 7: Documentation Update

### 7.1 Rewrite `README.md`

- Update folder structure (remove prod-networking, vpc-peering-prod)
- Update architecture diagram (single VPC)
- Update deployment order (no peering step)
- Update troubleshooting (remove peering references)
- Update cost estimates

### 7.2 Update `BACKEND.md`

- Remove prod-networking state key
- Add shared/networking state key

### 7.3 Update `PLAN-single-eks-cluster.md`

Mark as superseded by this plan. Add note at top.

### 7.4 Update `PLAN-single-eks-cluster_todo.md`

Mark all networking/VPC-peering tasks as superseded.

---

## Phase 8: Clean Slate Deployment Order

After all code changes, apply in this order on a fresh account:

1. `bootstrap` (run once, `environment = "shared"` or reuse dev bucket)
2. `envs/common/networking/` — creates the single shared VPC with all subnets
3. `envs/common/eks/` — shared EKS cluster in shared VPC private subnets
4. `envs/dev/03-aurora/` + `envs/dev/04-redis/` (parallel)
5. `envs/prod/03-aurora/` + `envs/prod/04-redis/` (parallel, when ready)
6. `envs/common/eks-irsa/`
7. Apply K8s namespaces and service accounts
8. Deploy applications

**No VPC peering step.**

---

## Migration From Current State

If the current multi-VPC state exists in AWS:

1. **Backup data** from prod Aurora/Redis (if any exists)
2. **Destroy prod networking** (`envs/prod-networking/`)
3. **Destroy VPC peering** (`envs/dev/vpc-peering-prod/`)
4. **Destroy and recreate networking** (`envs/common/networking/`) — this is the big bang
   - EKS will lose its VPC reference temporarily
   - Plan for downtime
5. **Re-apply EKS** (reads new shared VPC SSM paths)
6. **Re-apply all databases** (now in shared VPC, no peering needed)
7. **Verify connectivity** — pods should reach DBs via intra-VPC routing

> **Alternative (zero-downtime):** Since user said all infra was destroyed and this is a clean setup, the migration path is simply: delete the old stacks from code, apply the new ones fresh.

---

## Critical Files to Modify

| File | Change |
|---|---|
| `modules/networking/main.tf` | Single VPC, all DB subnets, custom DB subnet groups, new SSM paths |
| `modules/networking/variables.tf` | `environment = "shared"`, add `environments` list |
| `modules/networking/outputs.tf` | Add per-environment DB subnet outputs |
| `modules/aurora/data.tf` | Read VPC from `shared`, DB subnet group from env |
| `modules/redis/data.tf` | Read VPC from `shared`, DB subnet IDs from env |
| `modules/eks/data.tf` | Read all networking from `shared` |
| `envs/common/networking/terraform.tfvars` | `environment = "shared"`, add `environments` |
| `envs/common/networking/backend.tf` | State key to `shared/networking/terraform.tfstate` |
| `envs/common/eks/terraform.tfvars` | `networking_environment = "shared"` |
| `envs/common/eks-irsa/` | No changes |
| `scripts/init-env.sh` | Remove networking copy, simplify |
| `README.md` | Major rewrite for single VPC |
| `BACKEND.md` | Update state keys |

## Files to Delete

| File | Reason |
|---|---|
| `envs/prod-networking/` | No separate prod VPC |
| `envs/dev/vpc-peering-prod/` | No peering in single VPC |
| `modules/vpc-peering/` (if exists) | Unused |

---

## Security Considerations

### Intra-VPC Isolation

In a single VPC, environment isolation is NOT at the network boundary (that's the tradeoff). Isolation comes from:

1. **Security Groups**: Dev Aurora SG only allows ingress from shared EKS SG on port 5432. Prod Aurora SG does the same. SGs don't reference each other.
2. **Database Credentials**: Dev and prod have separate Secrets Manager secrets. Even if a dev pod knew the prod endpoint, it lacks credentials.
3. **Kubernetes Namespaces**: `dev-serenity` and `prod-serenity` namespaces with NetworkPolicies.
4. **IAM (IRSA)**: Dev service account can only read `serenity/dev/*` secrets. Prod service account can only read `serenity/prod/*` secrets.

### NACLs (Optional Hardening)

If desired, add NACLs to database subnets to restrict inter-environment traffic:
- Dev DB subnets: only allow ingress from EKS node CIDRs + admin CIDRs on ports 5432, 6379
- Prod DB subnets: same

NACLs are stateless and add complexity. Security Groups provide sufficient isolation for most use cases.

---

## Rollback Plan

If issues occur:
1. Revert networking module to per-environment VPC creation
2. Re-create `prod-networking/` and `vpc-peering-prod/` stacks
3. Revert Aurora/Redis data sources to read per-environment VPC
4. Re-apply in original multi-VPC order

---

## Acceptance Criteria

- [ ] `terraform plan` in `envs/common/networking/` shows a single VPC with 8 subnets (2 public + 2 private + 4 DB)
- [ ] `terraform plan` in `envs/dev/03-aurora/` shows Aurora in dev DB subnets, reading VPC from `shared`
- [ ] `terraform plan` in `envs/prod/03-aurora/` shows Aurora in prod DB subnets, reading VPC from `shared`
- [ ] `terraform plan` in `envs/common/eks/` shows EKS in shared private subnets
- [ ] No references to `prod-networking` or `vpc-peering-prod` in code
- [ ] `scripts/init-env.sh` does not copy networking stacks
- [ ] README accurately describes single-VPC architecture
