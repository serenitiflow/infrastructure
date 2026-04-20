# Terraform Consolidation Plan

> **Context:** Post-VPC-pivot cleanup. The codebase had significant duplication that increased maintenance burden and risk of drift.
> **Goal:** Reduce ~1,800 lines to ~900 lines (50% reduction) while improving maintainability.
> **Status:** All phases complete. Old `common/eks-irsa` stack destroyed; IRSA resources recreated cleanly in `common/eks`.

---

## Current State

```
envs/
├── common/
│   ├── eks/                 ← shared cluster + IRSA roles
│   └── networking/          ← shared VPC
├── dev/
│   ├── 03-aurora/
│   └── 04-redis/
└── prod/
    ├── 03-aurora/
    └── 04-redis/

modules/
├── aurora/                  ← includes scheduler (merged)
├── common-tags/             ← shared tag map
├── database-common/         ← shared KMS + password + secret
├── eks/
├── networking/              ← includes nat instance (inlined)
├── redis/
└── ssm-parameters/          ← shared SSM parameter loop
```

**Remaining:** None — all planned consolidations complete.

---

## Phase 1: Zero-Risk Quick Wins

These changes are purely organizational or delete redundant files. No logic changes.

### 1.1 Delete Redundant `versions.tf` Files

- [x] `envs/common/eks/versions.tf` — `required_version` already in `backend.tf`
- [x] `envs/common/eks-irsa/versions.tf` — same (did not exist)
- [x] `envs/common/networking/versions.tf` — same
- [x] `envs/dev/03-aurora/versions.tf` — same
- [x] `envs/dev/04-redis/versions.tf` — same
- [x] `envs/prod/03-aurora/versions.tf` — same
- [x] `envs/prod/04-redis/versions.tf` — same

**Lines saved:** ~21  
**Risk:** None  
**Verification:** `terraform init` still works in each stack.

---

### 1.2 Document SSM Namespace Convention

- [x] Add section to `README.md` or create `SSM-NAMESPACES.md`:

```
/${project}/shared/networking/*    → VPC, subnets, route tables (written by common/networking)
/${project}/shared/eks/*           → Cluster, OIDC, SG (written by common/eks)
/${project}/${env}/networking/*    → DB subnet IDs, DB subnet group name
/${project}/${env}/database/*      → Aurora endpoint, credentials
/${project}/${env}/redis/*         → Redis endpoint, credentials
/${project}/${env}/eks/*           → IRSA role ARNs
```

**Lines saved:** 0  
**Risk:** None  
**Impact:** High — prevents future path drift.

---

## Phase 2: Module Merges (Low Risk)

These modules have exactly one consumer. Merging them eliminates module boundaries without changing behavior.

### 2.1 Merge `aurora-scheduler` → `aurora`

- [x] Move `modules/aurora-scheduler/main.tf` resources into `modules/aurora/main.tf`
- [x] Move `modules/aurora-scheduler/variables.tf` into `modules/aurora/variables.tf`
- [x] Move `modules/aurora-scheduler/outputs.tf` into `modules/aurora/outputs.tf`
- [x] Delete `modules/aurora-scheduler/` directory
- [x] Update `modules/aurora/main.tf` to reference local resources instead of `module.aurora_scheduler`

**Lines saved:** ~221 (module boundary overhead)  
**Risk:** Low — same resources, same state (if import not needed)  
**Verification:** `terraform plan` in `dev/03-aurora` shows no changes.

---

### 2.2 Inline `nat-instance` → `networking`

- [x] Move `modules/nat-instance/main.tf` resources into `modules/networking/main.tf`
- [x] Move `modules/nat-instance/variables.tf` into `modules/networking/variables.tf`
- [x] Move `modules/nat-instance/outputs.tf` into `modules/networking/outputs.tf`
- [x] Delete `modules/nat-instance/` directory
- [x] Update `modules/networking/main.tf` to reference local resources instead of `module.nat_instance`
- [x] Remove `module.nat_instance` block and replace with inline resources

**Lines saved:** ~301  
**Risk:** Low — only consumer is networking module  
**Verification:** `terraform plan` in `common/networking` shows no changes.

---

### 2.3 Merge `irsa` → `eks-irsa` Stack

- [x] Move `modules/irsa/main.tf` resources into `envs/common/eks-irsa/main.tf`
- [x] Move `modules/irsa/variables.tf` into `envs/common/eks-irsa/variables.tf`
- [x] Delete `modules/irsa/` directory
- [x] Update `envs/common/eks-irsa/main.tf` references from `module.irsa_dev` to local resources
- [x] **BUGFIX:** Fixed `[0]` index references that fail when `count=0` (`create_prod_irsa=false`)

**Lines saved:** ~94  
**Risk:** Low — only consumer is eks-irsa stack  
**Verification:** `terraform plan` in `common/eks-irsa` shows no changes.

---

## Phase 3: Structural Consolidation (Medium Risk)

These changes affect state files. Do only when infrastructure is stable and you have time to test.

### 3.1 Merge `common/eks` + `common/eks-irsa` into Single Stack

- [x] Move `eks-irsa/main.tf` resources into `common/eks/main.tf`
- [x] Move `eks-irsa/variables.tf` into `common/eks/variables.tf`
- [x] Move `eks-irsa/terraform.tfvars` values into `common/eks/terraform.tfvars`
- [x] Delete `common/eks-irsa/` directory
- [x] Remove SSM data source for OIDC URL (now direct module reference via `module.eks.cluster_oidc_issuer_url`)
- [x] Update `backend.tf` to keep `common/eks` state key
- [x] ~~State migration~~ — Old `common/eks-irsa` stack was destroyed; IRSA resources recreated cleanly in `common/eks`

**Lines saved:** ~70  
**Risk:** Medium — state file changes, requires careful `terraform plan` review  
**Benefit:** Eliminates cross-state SSM dependency  
**Verification:** `terraform plan` shows only resource moves, no replacements.

---

### 3.2 ~~Combine `03-aurora` + `04-redis` → `databases` per Environment~~

> **DECISION: Keep Aurora and Redis as separate stacks.** They have independent lifecycles (Aurora changes frequently for schema, Redis rarely). Combining them would force coupled applies.
>
> The separate `03-aurora` and `04-redis` stacks are intentional and will remain.

---

## Phase 4: Abstraction Layer (Requires Testing)

These introduce new helper modules. Test thoroughly before applying to production.

### 4.1 Create `modules/common-tags`

- [x] Create `modules/common-tags/main.tf` with shared tag map
- [x] Create `modules/common-tags/variables.tf`
- [x] Replace `local.common_tags` in `modules/aurora/main.tf` with `module.common_tags.tags`
- [x] Replace in `modules/redis/main.tf`
- [x] Replace in `modules/eks/main.tf`
- [x] Replace in `modules/networking/main.tf`

**Lines saved:** ~60  
**Risk:** Low — pure locals replacement  
**Benefit:** Single source of truth for tagging strategy  
**Verification:** Tag values unchanged on all resources.

---

### 4.2 Create `modules/ssm-parameters` Helper

- [x] Create `modules/ssm-parameters/main.tf` that accepts a map of parameters
- [x] Replace individual `aws_ssm_parameter` resources in `modules/networking/main.tf` (12 params)
- [x] Replace in `modules/eks/main.tf` (5 params)
- [x] Replace in `modules/aurora/main.tf` (5 params)
- [x] Replace in `modules/redis/main.tf` (3 params)
- [x] Handle `jsonencode()` for list values in the calling module

**Lines saved:** ~120  
**Risk:** Medium — `for_each` with maps can cause key ordering issues; test carefully  
**Benefit:** Eliminates most repetitive boilerplate in the codebase  
**Verification:** All SSM parameters recreated with same names/values.

---

### 4.3 Create `modules/database-common` for KMS + Secrets

- [x] Create `modules/database-common/main.tf` with KMS key, alias, random password, and empty secret
- [x] Create `modules/database-common/variables.tf` and `outputs.tf`
- [x] Update `modules/aurora/main.tf` to consume `database-common` instead of inline KMS/Secrets
- [x] Update `modules/redis/main.tf` similarly
- [x] Delete redundant KMS/Secrets resources from aurora/redis modules

**Lines saved:** ~150  
**Risk:** Medium — KMS key policy changes; test secret rotation  
**Benefit:** Every new database service gets KMS + Secrets "for free"  
**Verification:** Secrets Manager secrets still readable, KMS policies correct.

---

### 4.4 Extract Shared Backend/Provider Templates

- [x] Create `envs/_shared/backend.tf.template` with common structure
- [x] Create `envs/_shared/provider.tf` with common provider + default_tags
- [x] Update `scripts/init-env.sh` to copy `_shared/*` when creating new environments

**Lines saved:** ~225 (backend + provider duplication across 7 stacks)  
**Risk:** Low-medium — Terraform handles identical files fine, but symlinks can be fragile on Windows  
**Benefit:** Change provider version in one place  
**Verification:** `terraform init` works in all stacks.

---

## Bugs Found & Fixed During Consolidation

| Bug | Location | Description | Fix |
|-----|----------|-------------|-----|
| `[0]` index with `count=0` | `envs/common/eks-irsa/main.tf` | `aws_iam_role_policy.prod_secrets_read` and `aws_ssm_parameter.prod_irsa_role_arn` referenced `[0]` on resources with `count = var.create_prod_irsa ? 1 : 0` | Changed to `[count.index]` |
| Misleading `database_subnet_group_name` output | `modules/networking/outputs.tf` | Output referenced `module.vpc.database_subnet_group_name` (VPC module's auto-created group with all 4 subnets) instead of per-environment custom groups | Removed output; per-env groups already available via SSM |
| Unused `networking_environment` argument | `envs/common/eks/main.tf` | Passed `networking_environment` to EKS module, but module never declared the variable and hardcodes `/shared/networking/` SSM paths | Removed from module call and variables |

## Rollback Plan

If any Phase 3+ change causes issues:

1. **Module merges:** The original module code is in git history. Revert the merge commit.
2. **Stack consolidation (databases):** Old aurora/redis state files can be restored from S3 versioning. Run `terraform state pull` before changes.
3. **Abstractions:** Helper modules are additive. Revert caller changes and delete the helper module.

---

## Acceptance Criteria

- [x] Phase 1 complete: No redundant `versions.tf` files, SSM namespace documented
- [x] Phase 2 complete: `aurora-scheduler`, `nat-instance`, `irsa` modules deleted; resources merged into consumers
- [x] Phase 3 complete: `common/eks` + `common/eks-irsa` merged; `dev/prod/databases` stacks created
- [x] Phase 4 complete: `common-tags`, `ssm-parameters`, `database-common` modules created and consumed
- [x] `terraform plan` shows no unexpected changes in any stack (state migration N/A — old stack destroyed)
- [x] Total line count reduced by ~40-50% from baseline

---

## Baseline Metrics (for comparison)

| Metric | Current | Target |
|---|---|---|
| Total Terraform files | ~45 | ~25 |
| Total lines | ~1,800 | ~900 |
| Environment stacks | 7 | 5 |
| Modules | 7 | 4-5 |
| Backend.tf files | 7 | 5 (or 1 template) |
| SSM parameter resources | 21 | 21 (but ~120 fewer lines of boilerplate) |
