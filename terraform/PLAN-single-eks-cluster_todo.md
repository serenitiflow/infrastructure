# Single Shared EKS Cluster — Consolidated Action Plan

> **Context:** All existing infrastructure has been destroyed. This is a clean new setup.
> **Review Date:** 2026-04-20

---

## Phase 1: Terraform Foundation (Must-Do First)

These fixes must be applied **before** any `terraform apply` on the clean setup.

### Task 1.1: Fix Hardcoded Subnet CIDRs in Networking Module
- [ ] Update `modules/networking/main.tf` line 21-23 to derive subnets from `var.vpc_cidr` using `cidrsubnet()`
- [ ] Dev VPC (`10.0.0.0/16`) → private: `10.0.1.0/24`, `10.0.2.0/24`; public: `10.0.101.0/24`, `10.0.102.0/24`; database: `10.0.201.0/24`, `10.0.202.0/24`
- [ ] Prod VPC (`10.1.0.0/16`) → private: `10.1.1.0/24`, `10.1.2.0/24`; public: `10.1.101.0/24`, `10.1.102.0/24`; database: `10.1.201.0/24`, `10.1.202.0/24`

### Task 1.2: Fix NAT Instance `private_cidr`
- [ ] Update `modules/networking/main.tf` line 61: change `private_cidr = "10.0.0.0/16"` to `private_cidr = var.vpc_cidr`

### Task 1.3: Add ALB Ingress Controller Subnet Tags
- [ ] Add `kubernetes.io/role/elb: 1` tag to public subnets in `modules/networking/main.tf`
- [ ] Add `kubernetes.io/role/internal-elb: 1` tag to private subnets if internal ALBs are needed

### Task 1.4: Parameterize `networking_environment`
- [ ] Convert `networking_environment = "dev"` in `envs/common/eks/main.tf` to a variable with default `"dev"`

### Task 1.5: Fix IRSA Region Scoping
- [ ] Lock Secrets Manager IAM policy region in `modules/irsa/main.tf` from `*` to `eu-central-1`

---

## Phase 2: Security Hardening (Critical Before Deployment)

### Task 2.1: Enable HTTPS on ALB Ingress
- [ ] Add ACM certificate ARN annotation to both dev and prod ingresses
- [ ] Update `listen-ports` to include HTTPS (443)
- [ ] Add HTTP-to-HTTPS redirect annotation
- [ ] Consider using `internal` ALB scheme for dev if external access is not required

### Task 2.2: Remove `docker-registry-secret.yaml`
- [ ] Delete `infrastructure/k8s/dev/docker-registry-secret.yaml` from repo
- [ ] Implement CI/CD injection or External Secrets for `ghcr-secret`
- [ ] Create corresponding prod secret strategy

### Task 2.3: Add NetworkPolicies
- [ ] Create default-deny NetworkPolicy for `dev-serenity` namespace
- [ ] Create default-deny NetworkPolicy for `prod-serenity` namespace
- [ ] Add explicit allow policies for required traffic (ingress from ALB, egress to DB/DNS)

### Task 2.4: Add Pod Security Admission Labels
- [ ] Add `pod-security.kubernetes.io/enforce: restricted` to `dev-serenity` namespace
- [ ] Add `pod-security.kubernetes.io/enforce: restricted` to `prod-serenity` namespace

### Task 2.5: Move JWT Public Keys
- [ ] Move JWT public keys from ConfigMaps to Kubernetes Secrets (or use AWS Secrets Manager + External Secrets)
- [ ] Use different JWT key pairs for dev and prod environments

### Task 2.6: Scope VPC Peering Routes
- [ ] Verify only database subnet route tables participate in peering
- [ ] Add NACL restrictions to limit peering traffic to DB ports (5432, 6379)

---

## Phase 3: Kubernetes Manifest Fixes

### Task 3.1: Fix Dev ConfigMap Database Endpoint
- [ ] Update `platform-user-service/config/k8s/dev/deployment.yaml` line 128
- [ ] Replace `postgres-dev.serenitiflow.com` with Terraform-managed Aurora endpoint
- [ ] Use environment variable injection from SSM/Secrets Manager instead of hardcoded host

### Task 3.2: Fix Prod ConfigMap Placeholder Endpoints
- [ ] Replace `PROD_AURORA_ENDPOINT` in prod deployment with actual Aurora endpoint
- [ ] Replace `PROD_REDIS_ENDPOINT` in prod deployment with actual Redis endpoint

### Task 3.3: Pin Image Tags
- [ ] Change `latest` to a specific version/digest in prod deployment
- [ ] Consider pinning dev to a specific tag or build SHA

### Task 3.4: Harden Container Security Context
- [ ] Set `readOnlyRootFilesystem: true` in both dev and prod deployments
- [ ] Mount `emptyDir` volume at `/tmp` if needed
- [ ] Add `runAsUser: 1000` and `runAsGroup: 1000` to pod securityContext

### Task 3.5: Add Missing K8s Resources
- [ ] Add PodDisruptionBudget for both dev and prod deployments
- [ ] Add HorizontalPodAutoscaler for production
- [ ] Consider adding resource quotas per namespace

### Task 3.6: Fix ALB Health Check Path
- [ ] Consider using `/actuator/health/readiness` instead of `/actuator/health` for ALB
- [ ] Ensure Spring Security restricts actuator endpoints

---

## Phase 4: CI/CD Workflow Fixes

### Task 4.1: Fix kubectl Apply Paths
- [ ] Change `kubectl apply -f config/k8s/` to `kubectl apply -f config/k8s/dev/` for dev job
- [ ] Change `kubectl apply -f config/k8s/` to `kubectl apply -f config/k8s/prod/` for prod job

### Task 4.2: Add `kubectl set image`
- [ ] Add step to inject built image SHA into deployment before rollout restart
- [ ] Example: `kubectl set image deployment/$DEPLOYMENT_NAME -n $NAMESPACE $DEPLOYMENT_NAME=$IMAGE`

### Task 4.3: Verify Coolify vs EKS Priority
- [ ] Confirm if Coolify is still needed alongside EKS
- [ ] If EKS is primary, update workflow logic accordingly

---

## Phase 5: Terraform Security Improvements

### Task 5.1: Fix Database Security Group Rules
- [ ] Add explicit `from_port` and `to_port` to Aurora SG rules (5432)
- [ ] Add explicit `from_port` and `to_port` to Redis SG rules (6379)

### Task 5.2: Verify SG Rule Parameter Names
- [ ] Confirm Aurora module uses `source_security_group_id` (correct for v9.x)
- [ ] Confirm Redis module uses `referenced_security_group_id` (correct for v1.x)

### Task 5.3: VPC Peering Tagging
- [ ] Ensure peering connection tags clearly indicate cross-environment link

---

## Phase 6: Deployment Order (Clean Slate)

Apply in this order after all fixes are coded:

1. [ ] `dev/01-networking` and `prod/01-networking` (parallel)
2. [ ] `dev/vpc-peering-prod`
3. [ ] `common/eks`
4. [ ] `dev/03-databases` and `prod/03-databases` (parallel, after EKS SG exists)
5. [ ] `common/irsa`
6. [ ] Apply K8s namespaces and service accounts (`kubectl apply -f infrastructure/k8s/`)
7. [ ] Update ConfigMaps with real Aurora/Redis endpoints
8. [ ] Deploy applications

---

## Quick Checklist

| # | Task | Phase | Priority |
|---|------|-------|----------|
| 1 | Fix subnet CIDRs | 1 | P0 |
| 2 | Fix NAT instance `private_cidr` | 1 | P0 |
| 3 | Add ALB subnet tags | 1 | P0 |
| 4 | Parameterize `networking_environment` | 1 | P1 |
| 5 | Fix IRSA region | 1 | P1 |
| 6 | Enable HTTPS on ALB | 2 | P0 |
| 7 | Remove `docker-registry-secret.yaml` | 2 | P0 |
| 8 | Add NetworkPolicies | 2 | P1 |
| 9 | Add PSA labels | 2 | P1 |
| 10 | Move JWT keys to Secrets | 2 | P2 |
| 11 | Scope VPC peering routes | 2 | P1 |
| 12 | Fix dev DB endpoint | 3 | P0 |
| 13 | Fix prod placeholder endpoints | 3 | P0 |
| 14 | Pin image tags | 3 | P0 |
| 15 | Harden container security context | 3 | P1 |
| 16 | Add PDB/HPA | 3 | P2 |
| 17 | Fix ALB health check path | 3 | P1 |
| 18 | Fix kubectl apply paths in CI/CD | 4 | P0 |
| 19 | Add `kubectl set image` | 4 | P0 |
| 20 | Fix DB SG explicit ports | 5 | P1 |
