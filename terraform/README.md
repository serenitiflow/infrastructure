# Terraform - Multi-Stack Infrastructure

Split Terraform infrastructure into 3 independent stacks with separate state files per environment, enabling independent updates, reduced blast radius, and clean environment isolation.

> **Warning for AI agents / automated assistants:** You must **never** run `terraform` commands (`init`, `plan`, `apply`, `destroy`, etc.) yourself. These commands must always be executed by the human user. Provide the commands in your response and let the user run them.

## Folder Structure

```
terraform/
├── bootstrap/              # One-time S3 bucket + DynamoDB setup
├── modules/                # Shared reusable infrastructure modules
│   ├── networking/         # VPC, subnets, NAT
│   ├── eks/                # EKS cluster, node groups
│   └── databases/          # Aurora, ElastiCache, Secrets
├── envs/                   # Environment-specific deployments
│   ├── common/             # Shared resources (EKS cluster)
│   │   └── eks/
│   ├── dev/                # Development environment
│   │   ├── 01-networking/
│   │   └── 03-databases/
│   └── prod/               # Production environment
│       ├── 01-networking/
│       └── 03-databases/
└── scripts/
    └── init-env.sh         # Helper to initialize new environments
```

## Architecture

```
+-------------------------------------------------------------+
|                        AWS Account                          |
|                                                             |
|  +---------------------+     +---------------------+       |
|  |  01-networking      |     |  02-eks             |       |
|  |  (separate state)   |     |  (separate state)   |       |
|  |                     |     |                     |       |
|  |  - VPC 10.0.0.0/16  |     |  - EKS Cluster      |       |
|  |  - Public subnets   |     |  - Node Groups      |       |
|  |  - Private subnets  |     |  - OIDC Provider    |       |
|  |  - Database subnets |     |                     |       |
|  |  - NAT Gateway/Inst |     |                     |       |
|  |                     |     |                     |       |
|  |  Writes SSM params  +---->+  Reads SSM params   |       |
|  |  (/serenity/dev/...)      |  (/serenity/dev/...)       |
|  +----------+----------+     +----------+----------+       |
|             |                           |                  |
|             |                           |                  |
|             v                           v                  |
|  +---------------------+     +---------------------+       |
|  |  03-databases       |     |  Application        |       |
|  |  (separate state)   |     |  (reads SSM params) |       |
|  |                     |     |                     |       |
|  |  - Aurora PostgreSQL|     |  - DB credentials   |       |
|  |  - ElastiCache Redis|     |  - Redis endpoint   |       |
|  |  - Secrets Manager  |     |  - EKS kubeconfig   |       |
|  |                     |     |                     |       |
|  |  Reads EKS SG from  |     |                     |       |
|  |  SSM for SG rules   |     |                     |       |
|  +---------------------+     +---------------------+       |
|                                                             |
|  Each stack has its own S3 state file and DynamoDB lock.   |
|  Stacks communicate via AWS SSM Parameter Store (not       |
|  terraform_remote_state), so they can be destroyed and      |
|  recreated independently without cascading dependencies.     |
|                                                             |
+-------------------------------------------------------------+
```

### Stack Design

**3 Independent Stacks:**

| Stack | Responsibility | Deploy Frequency | Blast Radius |
|-------|---------------|------------------|--------------|
| `01-networking` | VPC, subnets, NAT | Rarely (infrastructure) | Isolated to network |
| `02-eks` | Kubernetes cluster | Occasionally (upgrades) | Isolated to compute |
| `03-databases` | Aurora, Redis, Secrets | Frequently (app changes) | Isolated to data |

**Cross-Stack Communication via SSM:**

Instead of `terraform_remote_state` (which creates hard dependencies), each stack writes its outputs to AWS SSM Parameter Store:

- **Networking** writes: `vpc_id`, `private_subnet_ids`, `database_subnet_group_name`, `cluster_security_group_id`
- **EKS** writes: `cluster_name`, `cluster_endpoint`, `cluster_security_group_id`, `oidc_provider_arn`
- **Databases** writes: `database_host`, `database_port`, `redis_host`, `redis_port`, `secret_arns`

Downstream stacks read these values via `data.aws_ssm_parameter`. This means:
- You can destroy and recreate EKS without touching the database
- You can change the VPC CIDR without affecting running clusters
- Each stack's state file is independent

## Prerequisites

- AWS CLI configured (`aws configure` or env vars)
- Terraform >= 1.5.0
- Bash (for helper scripts)

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
- S3 bucket: `serenity-dev-terraform-v2-state-{account_id}`
- DynamoDB table: `serenity-dev-terraform-v2-locks`
- KMS key for state encryption
- Separate logging bucket with TLS enforcement

**Important:** The bootstrap uses local state (no remote backend). After running, the `terraform.tfstate` file exists locally in the `bootstrap/` directory. Keep it safe.

### Step 2: Deploy Networking (01-networking)

Networking must be deployed first because EKS and databases depend on it.

```bash
cd envs/dev/01-networking

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

### Step 3: Deploy EKS (02-eks)

EKS depends on networking (reads VPC and subnet IDs from SSM).

```bash
cd envs/common/eks

terraform init
terraform plan
terraform apply
```

**What this creates:**
- EKS cluster v1.35
- Managed node group (1 node in dev, Spot instances)
- KMS-encrypted secrets
- OIDC provider for IAM Roles for Service Accounts
- SSM parameters for cluster access

**After apply, configure kubectl:**
```bash
aws eks update-kubeconfig --region us-east-1 --name serenity-dev-cluster
kubectl get nodes
```

### Connect with Lens (or kubectl)

After `terraform apply`, configure kubeconfig and verify access:

```bash
aws eks update-kubeconfig --region us-east-1 --name serenity-dev-cluster
kubectl get nodes
```

**Lens users:** Open Lens → Add Cluster → it will auto-detect the context from your kubeconfig.

**Important:** The `kubernetes` provider authenticates to EKS using a short-lived AWS token. Your AWS credentials must be active when running `terraform apply`. On the **first** run on a fresh cluster, the data sources may fail because the cluster doesn't exist yet; run `terraform apply -target=module.eks` first, then `terraform apply`.

### Step 4: Deploy Databases (03-databases)

Databases depend on both networking (subnets, VPC) and EKS (security group for ingress rules).

```bash
cd envs/dev/03-databases

terraform init
terraform plan
terraform apply
```

**What this creates:**
- Aurora Serverless v2 (PostgreSQL 16.4, 0.5-2 ACU)
- ElastiCache Redis 7.0 (cache.t4g.micro)
- Secrets Manager with auto-generated passwords
- SSM parameters with connection details

**Verify:** Check the SSM parameters in AWS Console under `/serenity/dev/database/` and `/serenity/dev/redis/`.

### Step 5: Verify Cross-Stack Communication

Confirm all SSM parameters exist:

```bash
aws ssm get-parameters-by-path --path "/serenity/dev" --recursive
```

You should see parameters from all 3 stacks under `/serenity/dev/networking/`, `/serenity/dev/eks/`, `/serenity/dev/database/`, and `/serenity/dev/redis/`.

## Environment Isolation

Each environment has **completely isolated**:
- S3 state bucket (`serenity-{env}-terraform-v2-state-{account_id}`)
- DynamoDB lock table (`serenity-{env}-terraform-v2-locks`)
- SSM parameter namespace (`/serenity/{env}/...`)
- Terraform workspace (separate directory)

| Environment | Bucket Example | State Key Example |
|-------------|----------------|-------------------|
| common | `serenity-dev-terraform-v2-state-123...` | `dev/eks/terraform.tfstate` |
| dev | `serenity-dev-terraform-v2-state-123...` | `dev/networking/terraform.tfstate` |
| prod | `serenity-prod-terraform-v2-state-123...` | `prod/networking/terraform.tfstate` |

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

```bash
# Use the helper script
./scripts/init-env.sh staging

# Review and edit the generated tfvars
# envs/staging/01-networking/terraform.tfvars
# envs/staging/03-databases/terraform.tfvars

# Deploy in order:
cd envs/common/eks && terraform init && terraform apply
cd envs/staging/01-networking && terraform init && terraform apply
cd ../03-databases && terraform init && terraform apply
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
- **Cost Optimized**: NAT instance, Spot instances, scheduled Aurora shutdown
- **Lens / kubectl**: Use standard tools for cluster visibility (no in-cluster dashboard deployed)

## Troubleshooting

### "Error: no matching EC2 Subnet found"
The EKS or databases stack cannot find the VPC/subnets. Make sure `01-networking` was applied first and SSM parameters exist.

### "Error: Backend configuration changed"
If you modify `backend.tf`, run `terraform init -reconfigure`.

### "DynamoDB table does not exist"
Run bootstrap first for the target environment.

### Destroying a Stack
Because stacks are independent, you can destroy them individually:

```bash
# Destroy just EKS (databases and networking stay running)
cd envs/common/eks && terraform destroy

# Destroy everything in reverse order
cd envs/dev/03-databases && terraform destroy
cd envs/dev/01-networking && terraform destroy
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
