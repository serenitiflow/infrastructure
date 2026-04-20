# Terraform - Multi-Stack Infrastructure

Split Terraform infrastructure into independent stacks with separate state files per environment, enabling independent updates, reduced blast radius, and clean environment isolation.

> **Warning for AI agents / automated assistants:** You must **never** run `terraform` commands (`init`, `plan`, `apply`, `destroy`, etc.) yourself. These commands must always be executed by the human user. Provide the commands in your response and let the user run them.

## Folder Structure

```
terraform/
├── bootstrap/              # One-time S3 bucket + DynamoDB setup
├── modules/                # Shared reusable infrastructure modules
│   ├── networking/         # VPC, subnets, NAT (inlined)
│   ├── eks/                # EKS cluster, node groups, SSM outputs
│   ├── aurora/             # Aurora PostgreSQL (consumes database-common)
│   ├── redis/              # ElastiCache Redis (consumes database-common)
│   ├── common-tags/        # Shared tag map
│   ├── ssm-parameters/     # Shared SSM parameter loop
│   ├── database-common/    # Shared KMS + password + empty secret
│   └── github-oidc/        # GitHub Actions OIDC provider + IAM role
├── shared/                 # Shared resources (VPC, EKS)
│   ├── networking/         # Primary VPC (shared EKS lives here)
│   └── eks/                # EKS cluster + IRSA IAM roles + GitHub OIDC
├── envs/                   # Environment-specific deployments
│   ├── dev/                # Dev-specific data resources
│   │   ├── aurora/
│   │   └── redis/
│   └── prod/               # Prod-specific data resources
│       ├── aurora/
│       └── redis/
├── _templates/             # Template files for new environments
└── scripts/
    └── init-env.sh         # Helper to initialize new peer environments
```

## Architecture

```
+-------------------------------------------------------------+
|                        AWS Account                          |
|                                                             |
|  +---------------------+     +---------------------+       |
|  |  shared/networking  |     |  shared/eks         |       |
|  |  (separate state)   |     |  (separate state)   |       |
|  |                     |     |                     |       |
|  |  - VPC 10.0.0.0/16  |     |  - EKS Cluster      |       |
|  |  - Public subnets   |     |  - Node Groups      |       |
|  |  - Private subnets  |     |  - OIDC Provider    |       |
|  |  - Database subnets |     |  - IRSA IAM Roles   |       |
|  |  - NAT Gateway/Inst |     |  - GitHub OIDC      |       |
|  |                     |     |                     |       |
|  |  Writes SSM params  +---->+  Reads SSM params   |       |
|  |  (/shared/...)            |  (/shared/eks/...)         |
|  +----------+----------+     +----------+----------+       |
|             |                           |                  |
|             |                           |                  |
|             v                           v                  |
|  +---------------------+     +---------------------+       |
|  |  dev/aurora         |     |  Application        |       |
|  |  (separate state)   |     |  (reads SSM params) |       |
|  |                     |     |                     |       |
|  |  - Aurora PostgreSQL|     |  - DB credentials   |       |
|  |  - Secrets Manager  |     |  - Redis endpoint   |       |
|  |                     |     |  - EKS kubeconfig   |       |
|  |  Reads EKS SG from  |     |  - IRSA role ARN    |       |
|  |  SSM for SG rules   |     |                     |       |
|  +---------------------+     +---------------------+       |
|             |                                              |
|             v                                              |
|  +---------------------+                                   |
|  |  dev/redis          |                                   |
|  |  (separate state)   |                                   |
|  |                     |                                   |
|  |  - ElastiCache Redis|                                   |
|  |  - Secrets Manager  |                                   |
|  |                     |                                   |
|  |  Reads EKS SG from  |                                   |
|  |  SSM for SG rules   |                                   |
|  +---------------------+                                   |
|                                                             |
|  Each stack has its own S3 state file and DynamoDB lock.   |
|  Stacks communicate via AWS SSM Parameter Store (not       |
|  terraform_remote_state), so they can be destroyed and      |
|  recreated independently without cascading dependencies.     |
|                                                             |
+-------------------------------------------------------------+
```

### Stack Design

**4 Independent Stacks:**

| Stack | Responsibility | Deploy Frequency | Blast Radius |
|-------|---------------|------------------|--------------|
| `shared/networking` | Primary VPC, subnets, NAT | Rarely (infrastructure) | Isolated to network |
| `shared/eks` | Shared Kubernetes cluster + IRSA roles + GitHub OIDC | Occasionally (upgrades) | Isolated to compute |
| `aurora` | Aurora PostgreSQL, Secrets | Frequently (schema changes) | Isolated to data |
| `redis` | ElastiCache Redis, Secrets | Rarely (infra changes) | Isolated to cache |

**Cross-Stack Communication via SSM:**

Instead of `terraform_remote_state` (which creates hard dependencies), each stack writes its outputs to AWS SSM Parameter Store:

- **Networking** writes: `vpc_id`, `private_subnet_ids`, `database_subnet_group_name`, `database_route_table_ids`
- **EKS** writes: `cluster_name`, `cluster_endpoint`, `cluster_security_group_id`, `oidc_provider_arn`, `github_actions_role_arn`
- **Aurora** writes: `database_host`, `database_port`, `database_secret_arn`
- **Redis** writes: `redis_host`, `redis_port`, `redis_secret_arn`

Downstream stacks read these values via `data.aws_ssm_parameter`. This means:
- You can destroy and recreate EKS without touching the database
- You can change the VPC CIDR without affecting running clusters
- Each stack's state file is independent

## Prerequisites

- AWS CLI configured (`aws configure` or env vars)
- Terraform >= 1.5.0
- Bash

## Dev-Only Deployment (Start Here)

If you are starting with **dev only** and prod will be deployed later, use this simplified order:

```bash
# 1. Bootstrap (run once)
cd bootstrap && terraform init && terraform apply -var="environment=dev"

# 2. Primary networking (VPC where shared EKS lives)
cd shared/networking && terraform init && terraform apply

# 3. Shared EKS cluster
cd shared/eks && terraform init && terraform apply

# 4. Dev Aurora
cd envs/dev/aurora && terraform init && terraform apply

# 5. Dev Redis
cd envs/dev/redis && terraform init && terraform apply
```

**Prod data stacks** reuse the shared VPC and EKS cluster:
1. `envs/prod/aurora`
2. `envs/prod/redis`
3. Set `create_prod_irsa = true` in `shared/eks/terraform.tfvars` and re-apply EKS

## Step-by-Step Creation

### Step 1: Bootstrap the Environment (Run Once)

The bootstrap creates the S3 state bucket and DynamoDB lock table. This must be done once per environment.

```bash
cd bootstrap

# For dev:
terraform init
terraform apply -var="environment=dev"

# Note the outputs (bucket name and table name)
```

**What this creates:**
- S3 bucket: `serenity-dev-terraform-state-eu-central-1-{account_id}`
- DynamoDB table: `serenity-dev-terraform-locks-eu-central-1`
- KMS key for state encryption
- Separate logging bucket with TLS enforcement

**Important:** The bootstrap uses local state (no remote backend). After running, the `terraform.tfstate` file exists locally in the `bootstrap/` directory. Keep it safe.

### Step 2: Deploy Primary Networking (networking/)

The primary VPC must be deployed first because the shared EKS cluster and all dev databases live in it.

```bash
cd shared/networking

terraform init
terraform plan
terraform apply
```

**What this creates:**
- VPC `10.0.0.0/16` with 2 AZs
- Public subnets (for load balancers / NAT)
- Private subnets (for EKS nodes)
- Database subnets (for Aurora / Redis)
- NAT Gateway (prod) or NAT Instance (dev)
- SSM parameters that downstream stacks will read

**Verify:** Check the SSM parameters in AWS Console under `/serenity/dev/networking/`.

### Step 3: Deploy EKS (shared/eks)

EKS depends on networking (reads VPC and subnet IDs from SSM).

```bash
cd shared/eks

terraform init
terraform plan
terraform apply
```

**What this creates:**
- EKS cluster v1.35
- Managed node group (1 node in dev, Spot instances)
- KMS-encrypted secrets
- OIDC provider for IAM Roles for Service Accounts
- IRSA IAM roles for dev/prod namespace service accounts
- **GitHub Actions OIDC provider + IAM role** for keyless CI/CD authentication
- SSM parameters for cluster access, IRSA role ARNs, and GitHub Actions role ARN

**Outputs to note:**
- `github_actions_role_arn` — used by GitHub Actions workflows to authenticate to AWS

**After apply, configure kubectl:**
```bash
aws eks update-kubeconfig --region eu-central-1 --name serenity-shared-cluster
kubectl get nodes
```

**Lens users:** Open Lens -> Add Cluster -> it will auto-detect the context from your kubeconfig.

**Important:** The `kubernetes` provider authenticates to EKS using a short-lived AWS token. Your AWS credentials must be active when running `terraform apply`. On the **first** run on a fresh cluster, the data sources may fail because the cluster doesn't exist yet; run `terraform apply -target=module.eks` first, then `terraform apply`.

### Step 4: Deploy Aurora (aurora)

Aurora depends on networking (subnets, VPC) and EKS (security group for ingress rules).

```bash
cd envs/dev/aurora

terraform init
terraform plan
terraform apply
```

**What this creates:**
- Aurora Serverless v2 (PostgreSQL 16.4, 0.5-2 ACU)
- Secrets Manager with auto-generated passwords
- SSM parameters with connection details
- Aurora scheduler (dev only, stops cluster at night)

**Verify:** Check the SSM parameters in AWS Console under `/serenity/dev/database/`.

### Step 5: Deploy Redis (redis)

Redis depends on networking (database subnets, VPC) and EKS (security group for ingress rules).

```bash
cd envs/dev/redis

terraform init
terraform plan
terraform apply
```

**What this creates:**
- ElastiCache Redis 7.0 (cache.t4g.micro)
- Secrets Manager with auto-generated auth token
- SSM parameters with connection details

**Verify:** Check the SSM parameters in AWS Console under `/serenity/dev/redis/`.

### Step 6: Verify Cross-Stack Communication

Confirm all SSM parameters exist:

```bash
aws ssm get-parameters-by-path --path "/serenity/dev" --recursive
```

You should see parameters from all stacks under `/serenity/shared/networking/`, `/serenity/shared/eks/`, `/serenity/dev/networking/`, `/serenity/dev/database/`, and `/serenity/dev/redis/`.

## GitHub Actions CI/CD to EKS

The `shared/eks` stack creates a GitHub Actions OIDC provider and IAM role. This enables **keyless authentication** — no long-lived AWS credentials are stored in GitHub.

### How it works

1. GitHub Actions generates a short-lived OIDC token
2. The workflow calls `aws-actions/configure-aws-credentials` with `role-to-assume`
3. AWS validates the token and issues temporary STS credentials
4. The workflow uses `kubectl` to deploy to EKS

### Required repository secret

Each service repo that deploys to EKS must set:

| Secret | Value | Source |
|--------|-------|--------|
| `AWS_ROLE_ARN` | `arn:aws:iam::692046683886:role/serenity-github-actions-role` | `terraform output github_actions_role_arn` |

### Service repo structure

Each microservice should have:

```
.github/workflows/deploy.yml          # Caller workflow
config/k8s/dev/
  ├── deployment.yaml                  # Deployment, Service, PDB
  ├── configmap.yaml                   # Non-sensitive env vars
  └── secret.yaml.template             # Secret template (not committed)
```

Example deployment manifests are in `platform-user-service/config/k8s/dev/`.

### K8s secrets (one-time setup)

Create the secret manually from your local machine:

```bash
aws eks update-kubeconfig --name serenity-shared-cluster --region eu-central-1

kubectl create secret generic platform-user-service \
  --namespace=dev-serenity \
  --from-literal=DATABASE_URL="..." \
  --from-literal=DATABASE_USERNAME="..." \
  --from-literal=DATABASE_PASSWORD="..." \
  --from-literal=REDIS_HOST="..." \
  --from-literal=REDIS_PASSWORD="..."
```

## Environment Isolation

Each environment has **completely isolated**:
- S3 state bucket (`serenity-{env}-terraform-state-{account_id}`)
- DynamoDB lock table (`serenity-{env}-terraform-locks`)
- SSM parameter namespace (`/serenity/{env}/...`)
- Terraform workspace (separate directory)

| Environment | Bucket Example | State Key Example |
|-------------|----------------|-------------------|
| shared | `serenity-dev-terraform-state-eu-central-1-123...` | `shared/networking/terraform.tfstate` |
| shared | `serenity-dev-terraform-state-eu-central-1-123...` | `shared/eks/terraform.tfstate` |
| dev | `serenity-dev-terraform-state-eu-central-1-123...` | `dev/aurora/terraform.tfstate` |
| dev | `serenity-dev-terraform-state-eu-central-1-123...` | `dev/redis/terraform.tfstate` |
| prod | `serenity-prod-terraform-state-eu-central-1-123...` | `prod/aurora/terraform.tfstate` |
| prod | `serenity-prod-terraform-state-eu-central-1-123...` | `prod/redis/terraform.tfstate` |

## SSM Parameter Store Conventions

The following naming convention is used for all cross-stack parameters in AWS SSM Parameter Store:

| Path Pattern | Written By | Contents |
|--------------|------------|----------|
| `/${project_name}/shared/networking/*` | `shared/networking` | VPC ID, subnets, route tables |
| `/${project_name}/shared/eks/*` | `shared/eks` | Cluster name, OIDC provider ARN, security group ID, GitHub Actions role ARN |
| `/${project_name}/${env}/networking/*` | `shared/networking` | DB subnet IDs, DB subnet group name |
| `/${project_name}/${env}/database/*` | `aurora` | Aurora endpoint, port, credentials secret ARN |
| `/${project_name}/${env}/redis/*` | `redis` | Redis endpoint, port, credentials secret ARN |
| `/${project_name}/${env}/eks/*` | `shared/eks` | IRSA role ARNs for CI/CD |

- The `shared` prefix is for infrastructure shared across all environments.
- The `${env}` prefix is for environment-specific resources.
- This convention enables stacks to be destroyed and recreated independently without cascading dependencies.

## Environment Configuration Differences

| Setting | Dev | Prod |
|---------|-----|------|
| NAT | Instance (~$4/mo) | Gateway (HA) |
| EKS Nodes | Spot (1 node) | On-Demand (2+ nodes) |
| Aurora | 0.5-2 ACU, scheduler on | 1-8 ACU, scheduler off |
| Redis | cache.t4g.micro | cache.t4g.small |
| Backups | 1 day | 30 days |
| CloudWatch | 1 day | 30 days |
| Cluster UI | Lens / kubectl | Lens / kubectl |

## Adding a New Environment

New environments reuse the shared VPC and EKS cluster. Only data stacks are created per environment.

### 1. Create the environment directory structure

```bash
ENV=staging
mkdir -p envs/$ENV/aurora envs/$ENV/redis
```

### 2. Generate `backend.tf` for each stack

Use the template in `_templates/backend.tf`, replacing `{{ENV}}` and `{{STACK}}`:

```bash
# For aurora
sed -e "s/{{ENV}}/$ENV/g" -e "s/{{STACK}}/aurora/g" _templates/backend.tf > envs/$ENV/aurora/backend.tf

# For redis  
sed -e "s/{{ENV}}/$ENV/g" -e "s/{{STACK}}/redis/g" _templates/backend.tf > envs/$ENV/redis/backend.tf
```

### 3. Copy `provider.tf` from templates

```bash
cp _templates/provider.tf envs/$ENV/aurora/provider.tf
cp _templates/provider.tf envs/$ENV/redis/provider.tf
```

### 4. Copy module configs from dev as starting point

```bash
cp envs/dev/aurora/main.tf envs/$ENV/aurora/main.tf
cp envs/dev/aurora/variables.tf envs/$ENV/aurora/variables.tf
cp envs/dev/aurora/terraform.tfvars envs/$ENV/aurora/terraform.tfvars

cp envs/dev/redis/main.tf envs/$ENV/redis/main.tf
cp envs/dev/redis/variables.tf envs/$ENV/redis/variables.tf
cp envs/dev/redis/terraform.tfvars envs/$ENV/redis/terraform.tfvars
```

### 5. Update environment in tfvars

```bash
sed -i.bak -e "s/environment *= *\"dev\"/environment = \"$ENV\"/g" envs/$ENV/aurora/terraform.tfvars
sed -i.bak -e "s/environment *= *\"dev\"/environment = \"$ENV\"/g" envs/$ENV/redis/terraform.tfvars
rm -f envs/$ENV/aurora/terraform.tfvars.bak envs/$ENV/redis/terraform.tfvars.bak
```

### 6. Review and deploy

```bash
# Review the generated tfvars
# envs/staging/aurora/terraform.tfvars
# envs/staging/redis/terraform.tfvars

# Deploy in order (shared/eks already exists):
cd envs/$ENV/aurora && terraform init && terraform apply
cd ../redis && terraform init && terraform apply
```

## Resource Tagging

Every AWS resource created by Terraform is tagged with:

| Tag | Value Example | Purpose |
|-----|--------------|---------|
| `Name` | `serenity-dev` | Resource name |
| `Project` | `serenity` | Project identifier |
| `App` | `serenity-dev` | **App + Environment** for easy filtering |
| `Environment` | `dev` | Environment name |
| `ManagedBy` | `terraform` | Infrastructure source |
| `Stack` | `networking` | Stack identifier |

The `App` tag combines `app` and `environment` (e.g., `serenity-dev`, `serenity-prod`), making it easy to:
- Filter resources in AWS Console by app and environment
- Group resources in AWS Resource Groups
- Allocate costs in AWS Cost Explorer

To use a different app name, set `app` in each stack's `terraform.tfvars`:

```hcl
app = "myapp"
```

This produces `App = myapp-dev` or `App = myapp-prod` on all resources.

## Key Features

- **Environment Isolation**: Each env has its own state bucket and SSM namespace
- **Independent State Files**: Each stack has its own S3 state file
- **SSM Parameter Store**: Cross-stack communication (not terraform_remote_state)
- **Security Hardened**: KMS encryption, TLS enforcement, scoped IAM policies
- **Keyless CI/CD**: GitHub Actions authenticates via OIDC — no long-lived AWS credentials
- **Cost Optimized**: NAT instance, Spot instances, scheduled Aurora shutdown
- **Lens / kubectl**: Use standard tools for cluster visibility (no in-cluster dashboard deployed)

## Troubleshooting

### "Error: no matching EC2 Subnet found"
The EKS or Aurora/Redis stack cannot find the VPC/subnets. Make sure `shared/networking/` was applied first and SSM parameters exist.

### "Error: Backend configuration changed"
If you modify `backend.tf`, run `terraform init -reconfigure`.

### "DynamoDB table does not exist"
Run bootstrap first for the target environment.

### "Error: failed to assume role"
If GitHub Actions fails with `AccessDenied` on `sts:AssumeRoleWithWebIdentity`:
1. Verify the `AWS_ROLE_ARN` secret in the service repo matches `terraform output github_actions_role_arn`
2. Check the workflow has `permissions: id-token: write`
3. Ensure the repo is listed in the `allowed_repositories` condition of the IAM role trust policy

### Destroying a Stack
Because stacks are independent, you can destroy them individually:

```bash
# Destroy just EKS (Aurora, Redis, and networking stay running)
cd shared/eks && terraform destroy

# Destroy everything in reverse order
cd envs/dev/redis && terraform destroy
cd envs/dev/aurora && terraform destroy
cd shared/eks && terraform destroy

# WARNING: shared/networking is the shared VPC used by ALL environments.
# Only destroy it after ALL environment data stacks (dev, prod, etc.) are destroyed.
cd shared/networking && terraform destroy
```

## Documentation

- [BACKEND.md](BACKEND.md) - Backend configuration reference
- [Bootstrap](bootstrap/) - State bucket and locking setup

## Estimated Monthly Cost

| Environment | Estimate |
|-------------|----------|
| **Dev** | **~$145-170/month** |
| **Prod** | **~$350-450/month** |

## Security Compliance

| Requirement | Implementation |
|-------------|----------------|
| SEC-1 | Aurora scheduler IAM policy scoped to specific cluster |
| SEC-2 | EKS public endpoint disabled by default (dev enables explicitly) |
| SEC-3 | Separate S3 bucket for access logs |
| SEC-4 | TLS enforcement on all S3 buckets |
| SEC-5 | Restricted KMS key policies (no wildcard kms:*) |
| SEC-6 | Terraform state encrypted with SSE-KMS (not SSE-S3) |
| SEC-7 | NAT instance security group restricted to HTTP/HTTPS/DNS |
| SEC-8 | Sensitive outputs marked with `sensitive = true` |
| SEC-9 | SSM parameters use `overwrite = true` for idempotent recreation |
| SEC-10 | GitHub Actions uses OIDC federation — no long-lived AWS credentials in CI/CD |
