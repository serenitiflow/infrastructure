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
│   └── eks/                # EKS cluster + IRSA IAM roles + GitHub OIDC + ALB Controller
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
|  |                     |     |  - ALB Controller   |       |
|  |  Writes SSM params  +---->+  Reads SSM params   |       |
|  |  (/shared/...)            |  (/shared/eks/...)         |
|  +----------+----------+     +----------+----------+       |
|             |                           |                  |
|             |                           v                  |
|             |                  +---------------------+     |
|             |                  | Route 53            |     |
|             |                  | - serenitiflow.com  |     |
|             |                  | - ACM validation    |     |
|             |                  | - ALB alias records |     |
|             |                  +----------+----------+     |
|             |                             |                |
|             v                             v                |
|  +---------------------+     +---------------------+      |
|  |  dev/aurora         |     | Application         |      |
|  |  (separate state)   |     | (reads SSM params)  |      |
|  |                     |     |                     |      |
|  |  - Aurora PostgreSQL|     |  - DB credentials   |      |
|  |  - Secrets Manager  |     |  - Redis endpoint   |      |
|  |                     |     |  - EKS kubeconfig   |      |
|  |  Reads EKS SG from  |     |  - IRSA role ARN    |      |
|  |  SSM for SG rules   |     |                     |      |
|  +---------------------+     +---------------------+      |
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

### Core Concepts

**1. Multi-Stack Decoupled Architecture**

The infrastructure is split into 4 independent stacks, each with its own Terraform state:

| Stack | Responsibility | Deploy Frequency | Blast Radius |
|-------|---------------|------------------|--------------|
| `shared/networking` | Primary VPC, subnets, NAT | Rarely (infrastructure) | Isolated to network |
| `shared/eks` | Shared Kubernetes cluster, IRSA roles, GitHub OIDC, ALB Controller | Occasionally (upgrades) | Isolated to compute |
| `aurora` | Aurora PostgreSQL, Secrets | Frequently (schema changes) | Isolated to data |
| `redis` | ElastiCache Redis, Secrets | Rarely (infra changes) | Isolated to cache |

**2. Cross-Stack Communication via SSM**

Instead of `terraform_remote_state` (which creates hard dependencies), each stack writes its outputs to AWS SSM Parameter Store. Downstream stacks read these values via `data.aws_ssm_parameter`.

This means:
- You can destroy and recreate EKS without touching the database
- You can change the VPC CIDR without affecting running clusters
- Each stack's state file is independent

**3. Ingress & Load Balancing**

The AWS Load Balancer Controller is installed via Helm in the `shared/eks` stack. It watches Kubernetes `Ingress` resources with `ingressClassName: alb` and automatically provisions AWS Application Load Balancers.

Key behaviors:
- One ALB per `alb.ingress.kubernetes.io/group.name` (multiple services can share a single ALB)
- ALB names are limited to 32 characters — choose short names via `alb.ingress.kubernetes.io/load-balancer-name`
- The controller auto-discovers subnets using tags: `kubernetes.io/role/elb` (public) or `kubernetes.io/role/internal-elb` (private) combined with `kubernetes.io/cluster/<cluster-name> = shared`
- HTTPS is configured via ACM certificate ARNs on the Ingress annotations

**4. IRSA (IAM Roles for Service Accounts)**

Kubernetes pods authenticate to AWS using OIDC-based IAM roles. The `shared/eks` stack creates:
- `serenity-services` service account in `dev-serenity` (and optionally `prod-serenity`) with Secrets Manager read access
- `aws-load-balancer-controller` service account in `kube-system` with ELB/EC2 permissions

This means pods never use node IAM credentials — each service has its own scoped role.

**5. Keyless CI/CD with GitHub OIDC**

GitHub Actions workflows authenticate to AWS via OIDC federation. No long-lived AWS credentials are stored in GitHub. The `shared/eks` stack creates the OIDC provider and IAM role for this.

---

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

---

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

**Important — Subnet Tags for ALB Controller:**

The networking module adds the cluster-specific tag `kubernetes.io/cluster/serenity-shared-cluster = shared` to all public and private subnets. This tag is **required** by the AWS Load Balancer Controller to auto-discover which subnets to place ALBs in. Without it, Ingress resources will fail to provision load balancers.

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
- **AWS Load Balancer Controller** (Helm release in `kube-system`) — watches Ingress resources and provisions ALBs
- **GitHub Actions OIDC provider + IAM role** for keyless CI/CD authentication
- SSM parameters for cluster access, IRSA role ARNs, and GitHub Actions role ARN

**ALB Controller Resources (new in `shared/eks/alb-controller.tf`):**

| Resource | Purpose |
|----------|---------|
| `aws_iam_policy.alb_controller` | Base IAM policy from upstream AWS LB Controller project |
| `aws_iam_policy.alb_controller_supplement` | Supplementary policy for permissions not in the base JSON (e.g., `ec2:GetSecurityGroupsForVpc`) |
| `module.alb_controller_irsa` | IRSA role with trust policy scoped to `kube-system/aws-load-balancer-controller` |
| `kubernetes_service_account_v1.alb_controller` | K8s SA annotated with the IRSA role ARN |
| `helm_release.alb_controller` | Helm chart for the controller (v2.8.2) |

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

---

## Ingress Configuration (ALB)

Once the AWS Load Balancer Controller is installed, Kubernetes `Ingress` resources with `ingressClassName: alb` automatically provision AWS ALBs.

### Example Ingress manifest

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: platform-user-service
  namespace: dev-serenity
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
    alb.ingress.kubernetes.io/ssl-redirect: "443"
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:eu-central-1:ACCOUNT:certificate/UUID
    alb.ingress.kubernetes.io/load-balancer-name: dev-serenity-user-svc
    alb.ingress.kubernetes.io/group.name: dev-serenity
spec:
  ingressClassName: alb
  rules:
    - host: dev-identity.serenitiflow.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: platform-user-service
                port:
                  number: 8080
```

### Key annotations

| Annotation | Purpose | Example |
|-----------|---------|---------|
| `scheme` | `internet-facing` or `internal` | `internet-facing` |
| `target-type` | `ip` (pod IP) or `instance` (node port) | `ip` |
| `listen-ports` | ALB listener ports | `[{"HTTP": 80}, {"HTTPS": 443}]` |
| `ssl-redirect` | Redirect HTTP to HTTPS | `"443"` |
| `certificate-arn` | ACM certificate for HTTPS | `arn:aws:acm:...` |
| `load-balancer-name` | ALB name (max 32 chars) | `dev-serenity-user-svc` |
| `group.name` | Share one ALB across multiple Ingresses | `dev-serenity` |
| `healthcheck-path` | Health check endpoint | `/actuator/health/readiness` |

### ALB naming limit

AWS ALB names are limited to **32 characters**. If your generated name exceeds this, the controller will fail with:
```
load balancer name cannot be longer than 32 characters
```

Use `alb.ingress.kubernetes.io/load-balancer-name` to set a short, explicit name.

### HTTPS / TLS setup

1. Request an ACM certificate for your domain:
   ```bash
   aws acm request-certificate \
     --domain-name dev-identity.serenitiflow.com \
     --validation-method DNS \
     --region eu-central-1
   ```

2. Add the ACM validation CNAME to your DNS (Route 53 or external provider)

3. Add an ALB alias record (A record pointing to the ALB DNS name)

4. Update the Ingress annotations with `listen-ports`, `ssl-redirect`, and `certificate-arn`

---

## GitHub Actions CI/CD to EKS

The `shared/eks` stack creates a GitHub Actions OIDC provider and IAM role. This enables **keyless authentication** — no long-lived AWS credentials are stored in GitHub.

### How it works

1. GitHub Actions generates a short-lived OIDC token
2. The workflow calls `aws-actions/configure-aws-credentials` with `role-to-assume`
3. AWS validates the token and issues temporary STS credentials
4. The workflow uses `kubectl` to deploy to EKS

### Required repository configuration

Each service repo that deploys to EKS must set:

| Setting | Type | Value | Source |
|---------|------|-------|--------|
| `AWS_ROLE_ARN` | **Repository Variable** | `arn:aws:iam::<account>:role/serenity-github-actions-role` | `terraform output github_actions_role_arn` |

> **Note:** `AWS_ROLE_ARN` is a repository **variable** (`vars`), not a secret. It is passed to the reusable workflow via the `with` block, where the `secrets` context is unavailable.

### Service repo structure

Each microservice should have:

```
.github/workflows/deploy.yml          # Caller workflow
config/k8s/dev/
  ├── deployment.yaml                  # Deployment, Service, PDB, Ingress
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

---

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
- **Auto-Provisioned ALBs**: Kubernetes Ingress resources automatically create AWS ALBs via the AWS Load Balancer Controller
- **HTTPS by Default**: Ingress annotations support ACM certificates and HTTP→HTTPS redirects

## Troubleshooting

### "Error: no matching EC2 Subnet found"
The EKS or Aurora/Redis stack cannot find the VPC/subnets. Make sure `shared/networking/` was applied first and SSM parameters exist.

### "Error: Backend configuration changed"
If you modify `backend.tf`, run `terraform init -reconfigure`.

### "DynamoDB table does not exist"
Run bootstrap first for the target environment.

### "Error: failed to assume role"
If GitHub Actions fails with `AccessDenied` on `sts:AssumeRoleWithWebIdentity`:
1. Verify `AWS_ROLE_ARN` is set as a **repository variable** (not a secret) in the service repo, and matches `terraform output github_actions_role_arn`
2. Check the workflow has `permissions: id-token: write`
3. Ensure the repo is listed in the `allowed_repositories` condition of the IAM role trust policy (current: `repo:serenitiflow/*`)
4. Verify the OIDC provider `token.actions.githubusercontent.com` exists in the AWS account

### "Error: dial tcp ... i/o timeout" (kubectl)
If `kubectl` or the workflow fails to connect to the EKS API server:
1. Verify the cluster endpoint is reachable: `aws eks describe-cluster --name serenity-shared-cluster`
2. If the endpoint is private-only, enable public access by setting `cluster_endpoint_public_access = true` in `shared/eks/terraform.tfvars`
3. If public access is enabled but limited by CIDR, ensure GitHub Actions IPs are allowed (or use `allowed_public_cidrs = ["0.0.0.0/0"]` for dev)
4. The endpoint still requires valid AWS credentials — being publicly reachable does not mean it's publicly accessible

### "load balancer name cannot be longer than 32 characters"
Set `alb.ingress.kubernetes.io/load-balancer-name` to a name under 32 characters. Example: `dev-serenity-user-svc` (22 chars).

### "AccessDenied: ... is not authorized to perform: ec2:GetSecurityGroupsForVpc"
The AWS Load Balancer Controller's base IAM policy (from upstream v2.7.2 JSON) is missing newer permissions. The `alb-controller.tf` file includes a supplementary policy (`alb_controller_supplement`) for this. If you see this error, the supplementary policy may not be attached — verify via AWS Console IAM > Roles > `serenity-alb-controller-role` > Attached policies.

### Ingress ADDRESS field stays empty
1. Check controller pods: `kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller`
2. Check controller logs: `kubectl logs -n kube-system deployment/aws-load-balancer-controller --tail=20`
3. Common causes:
   - Missing subnet tags (`kubernetes.io/cluster/<cluster-name> = shared`)
   - IRSA misconfiguration (wrong OIDC provider or service account)
   - ALB name too long (>32 characters)
   - Missing IAM permissions

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
| **Dev** | **~$145-175/month** |
| **Prod** | **~$350-450/month** |

### Dev cost breakdown

| Component | Monthly Cost (eu-central-1) |
|-----------|----------------------------|
| AWS ALB base (1 ALB, 24/7) | ~$16.43 |
| LCU charges (low dev traffic) | ~$1–6 |
| Route 53 hosted zone | ~$0.50 |
| ACM certificate | $0 (public certs are free) |
| Controller pods | $0 (runs on existing SPOT nodes) |
| IAM/IRSA | $0 |
| **ALB subtotal** | **~$18–26/month** |

The ALB cost is incremental to the base dev infrastructure (~$127–149/month for VPC, EKS, Aurora, Redis). Multiple services sharing the same `group.name` on the ALB do not increase the base cost — only LCU usage.

## Security Compliance

| Requirement | Implementation |
|-------------|----------------|
| SEC-1 | Aurora scheduler IAM policy scoped to specific cluster |
| SEC-2 | EKS public endpoint enabled for dev with IAM-based access control |
| SEC-3 | Separate S3 bucket for access logs |
| SEC-4 | TLS enforcement on all S3 buckets |
| SEC-5 | Restricted KMS key policies (no wildcard kms:*) |
| SEC-6 | Terraform state encrypted with SSE-KMS (not SSE-S3) |
| SEC-7 | NAT instance security group restricted to HTTP/HTTPS/DNS |
| SEC-8 | Sensitive outputs marked with `sensitive = true` |
| SEC-9 | SSM parameters use `overwrite = true` for idempotent recreation |
| SEC-10 | GitHub Actions uses OIDC federation — no long-lived AWS credentials in CI/CD |
| SEC-11 | IRSA roles scope pod permissions per service account |
| SEC-12 | ALB security groups auto-managed by controller with least-privilege ingress |
