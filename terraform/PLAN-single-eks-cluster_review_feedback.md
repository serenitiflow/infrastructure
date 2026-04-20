# Single Shared EKS Cluster — Review Feedback Report

> **Context:** All existing infrastructure has been destroyed. This is a clean new setup.
> **Review Date:** 2026-04-20

---

## Summary

| Category | Critical | Warning | Suggestion | Total |
|----------|----------|---------|------------|-------|
| Terraform Infrastructure | 2 | 5 | 4 | 11 |
| Kubernetes Manifests | 4 | 7 | 7 | 18 |
| CI/CD Workflow | 1 | 2 | 1 | 4 |
| Security & IAM | 4 | 6 | 3 | 13 |
| **Total** | **11** | **20** | **15** | **46** |

---

## 1. Terraform Infrastructure

### Critical Issues

| # | File | Line | Issue | Fix |
|---|------|------|-------|-----|
| TF-1 | `modules/networking/main.tf` | 21-23 | Hardcoded subnet CIDRs (`10.0.1.0/24`, etc.) do not adjust when `vpc_cidr` changes (e.g., prod uses `10.1.0.0/16`) | Derive subnets from `var.vpc_cidr` using `cidrsubnet()` or pass them as variables |
| TF-2 | `modules/networking/main.tf` | 61 | `private_cidr = "10.0.0.0/16"` is hardcoded in NAT instance module | Use `var.vpc_cidr` instead |

### Warning Issues

| # | File | Line | Issue | Fix |
|---|------|------|-------|-----|
| TF-3 | `modules/eks/main.tf` | 63 | Cluster name is `${var.project_name}-${var.environment}-cluster`. With `environment = "shared"`, this becomes `serenity-shared-cluster` | Acceptable, but ensure this name is used consistently in kubeconfig commands |
| TF-4 | `envs/common/eks/main.tf` | 19 | `networking_environment = "dev"` is hardcoded | Parameterize this as a variable with default `"dev"` |
| TF-5 | `envs/common/irsa/main.tf` | 2 | `aws_ssm_parameter` `oidc_issuer_url` does not handle the case where EKS is not yet deployed | Add `depends_on` or document that EKS must be applied before IRSA |
| TF-6 | `envs/dev/vpc-peering-prod/main.tf` | 50-59 | `aws_vpc_peering_connection` has no lifecycle rules; if networking is recreated, routes may need manual cleanup | Document peering dependency chain in README |

### Suggestion Issues

| # | File | Line | Issue | Fix |
|---|------|------|-------|-----|
| TF-7 | `modules/eks/main.tf` | 114-167 | SSM parameters use `/${var.project_name}/shared/eks/*` which is correct, but the `tags` still reference `${var.environment}` (now `"shared"`) | Tags are fine; just verify consumers read from `/shared/` path |
| TF-8 | `modules/networking/main.tf` | 157-177 | `nat_gateway_id` and `nat_instance_id` SSM params may write conflicting values depending on `nat_gateway_enabled` | The `nat_instance_id` param always writes from `module.nat_instance.nat_instance_id` even when disabled — verify NAT instance module handles `enabled = false` gracefully |
| TF-9 | `modules/irsa/main.tf` | 54 | Secrets Manager resource ARN uses `*` region: `arn:aws:secretsmanager:*:` | For single-region setup, lock to `us-east-1` for tighter scoping |

---

## 2. Kubernetes Manifests

### Critical Issues

| # | File | Line | Issue | Fix |
|---|------|------|-------|-----|
| K8S-1 | `platform-user-service/config/k8s/prod/deployment.yaml` | 35 | Production Deployment uses `latest` image tag | Pin to a specific versioned tag (e.g., `v1.2.3`) or use digest |
| K8S-2 | `platform-user-service/config/k8s/prod/deployment.yaml` | 128 | `DATABASE_URL` is a placeholder (`PROD_AURORA_ENDPOINT`) | Replace with actual production Aurora endpoint before deployment |
| K8S-3 | `platform-user-service/config/k8s/prod/deployment.yaml` | 130 | `REDIS_HOST` is a placeholder (`PROD_REDIS_ENDPOINT`) | Replace with actual production Redis endpoint before deployment |
| K8S-4 | Both `deployment.yaml` | 134 | Hardcoded JWT public key in ConfigMap | Move to a Kubernetes Secret or AWS Secrets Manager + External Secrets Operator |

### Warning Issues

| # | File | Line | Issue | Fix |
|---|------|------|-------|-----|
| K8S-5 | Both `deployment.yaml` | 35 | Dev also uses `latest` image tag | Pin to a specific tag or use digest for reproducibility |
| K8S-6 | Both `deployment.yaml` | 52 | `readOnlyRootFilesystem: false` | Set to `true` and mount an `emptyDir` volume for writable paths (e.g., `/tmp`) |
| K8S-7 | Both `deployment.yaml` | — | No NetworkPolicy defined | Add a NetworkPolicy to restrict ingress/egress to necessary ports and namespaces |
| K8S-8 | Both `deployment.yaml` | — | No PodDisruptionBudget defined | Add a PDB to ensure availability during node drains or upgrades |
| K8S-9 | `infrastructure/k8s/*/serviceaccount.yaml` | 10 | Shared IAM role for all services in namespace | Consider per-service SAs/roles for least-privilege access (future enhancement) |

### Suggestion Issues

| # | File | Line | Issue | Fix |
|---|------|------|-------|-----|
| K8S-10 | Both `deployment.yaml` | 30 | Missing `runAsUser` / `runAsGroup` in pod securityContext | Add explicit `runAsUser: 1000` and `runAsGroup: 1000` |
| K8S-11 | Both `deployment.yaml` | — | No HorizontalPodAutoscaler defined | Add an HPA for automatic scaling based on CPU/memory |
| K8S-12 | Both `deployment.yaml` (Ingress) | 149 | Ingress listens on HTTP (port 80) only | Add HTTPS (port 443) listener and configure TLS certificate via ACM |
| K8S-13 | Both `deployment.yaml` (Ingress) | 147 | `alb.ingress.kubernetes.io/scheme: internet-facing` | Confirm this is intentional; for internal APIs use `internal` |
| K8S-14 | Both `deployment.yaml` (Ingress) | 150 | ALB health check path is `/actuator/health` | Consider using `/actuator/health/readiness` for ALB to avoid routing to unready pods |
| K8S-15 | Both `deployment.yaml` | 71-78 | `livenessProbe` initialDelaySeconds is 0 | Add a small `initialDelaySeconds` (e.g., 10) to prevent premature restarts |

---

## 3. CI/CD Workflow

### Critical Issues

| # | File | Line | Issue | Fix |
|---|------|------|-------|-----|
| CI-1 | `microservice-deploy.yml` | 790 | `kubectl apply -f config/k8s/` applies ALL manifests in that directory, but dev and prod manifests are in `config/k8s/dev/` and `config/k8s/prod/` subdirectories | Change to `kubectl apply -f config/k8s/dev/` for dev job and `kubectl apply -f config/k8s/prod/` for prod job |

### Warning Issues

| # | File | Line | Issue | Fix |
|---|------|------|-------|-----|
| CI-2 | `microservice-deploy.yml` | 807 | `kubectl rollout restart` is used, but the Deployment manifest has `imagePullPolicy: Always` and `image: ...:latest` — restarting may pull a different image than the one built in the workflow | Either pin the image tag in the manifest at deploy time (`kubectl set image`) or ensure the manifest references the SHA-tagged image |
| CI-3 | `microservice-deploy.yml` | — | The workflow still references `vars.COOLIFY_*` for Coolify deployment but this is a clean EKS-focused setup | Verify if Coolify is still the primary target; if EKS is primary, prioritize EKS deployment logic |

### Suggestion Issues

| # | File | Line | Issue | Fix |
|---|------|------|-------|-----|
| CI-4 | `microservice-deploy.yml` | — | No `kubectl set image` step to inject the built image SHA into the deployment | Add `kubectl set image deployment/$DEPLOYMENT_NAME -n $NAMESPACE $DEPLOYMENT_NAME=$IMAGE` before rollout restart |

---

## 4. Security & IAM

### Critical Issues

| # | File | Line | Issue | Fix |
|---|------|------|-------|-----|
| SEC-1 | Both `deployment.yaml` | 134 | JWT public key (a sensitive cryptographic material) is in a ConfigMap | Move to a Kubernetes Secret or use AWS Secrets Manager with External Secrets Operator |
| SEC-2 | `modules/databases/main.tf` | 107-111 | Aurora security group uses `source_security_group_id` (module expects SG ID), but `data.aws_ssm_parameter.cluster_security_group_id` reads from `/serenity/shared/eks/cluster_security_group_id` | Verify the SSM parameter value is a valid SG ID and that the Aurora module version supports this key |

### Warning Issues

| # | File | Line | Issue | Fix |
|---|------|------|-------|-----|
| SEC-3 | `modules/irsa/main.tf` | 22-25 | IRSA trust policy `StringEquals` on `sub` is correct but the `aud` condition should also include `sts.amazonaws.com` | Verify the condition is correct; it is: `"${oidc_provider}:aud" = "sts.amazonaws.com"` — this is correct |
| SEC-4 | `modules/networking/main.tf` | 33 | `public_subnet_tags` are applied; ensure ALB Ingress Controller can discover these | Tag public subnets with `kubernetes.io/role/elb: 1` for ALB Ingress Controller auto-discovery |
| SEC-5 | `modules/networking/main.tf` | 36 | `private_subnet_tags` should also include `kubernetes.io/role/internal-elb: 1` for internal ALBs | Add this tag if internal ALBs are needed |
| SEC-6 | Both `deployment.yaml` | 149 | ALB listens on HTTP only; no TLS termination | Add HTTPS listener and ACM certificate annotation |

### Suggestion Issues

| # | File | Line | Issue | Fix |
|---|------|------|-------|-----|
| SEC-7 | `envs/dev/vpc-peering-prod/main.tf` | 62-77 | VPC peering allows all traffic between dev and prod private subnets | Consider adding NACLs or security group rules to restrict peering traffic to database ports only (5432, 6379) |
| SEC-8 | `modules/irsa/main.tf` | 54 | IAM policy allows `secretsmanager:*` actions in `*` region | Lock to `us-east-1` for tighter scoping |

---

## 5. Clean Slate Considerations

Since all existing infrastructure has been destroyed, the following ordering is recommended for a fresh apply:

1. **Networking first:** Apply `dev/01-networking` and `prod/01-networking` simultaneously (no dependencies)
2. **VPC Peering:** Apply `dev/vpc-peering-prod` after both networkings complete
3. **Shared EKS:** Apply `common/eks` after dev networking (it reads dev VPC/subnets)
4. **Databases:** Apply `dev/03-databases` and `prod/03-databases` after EKS (they need the shared EKS cluster SG)
5. **IRSA:** Apply `common/irsa` after EKS (needs OIDC issuer URL)
6. **K8s resources:** Apply namespaces and service accounts after cluster is ready
7. **Applications:** Deploy after all infra is ready and endpoints are known

---

## 6. Must-Fix Before Deployment

1. **TF-1 / TF-2:** Fix hardcoded subnet CIDRs and NAT instance `private_cidr` to use `var.vpc_cidr`
2. **K8S-1:** Pin production image tag
3. **K8S-2 / K8S-3:** Replace placeholder database/Redis endpoints with actual values
4. **K8S-4 / SEC-1:** Move JWT public keys out of ConfigMaps
5. **CI-1:** Fix kubectl apply paths to use `config/k8s/dev/` and `config/k8s/prod/`
6. **CI-4:** Add `kubectl set image` to inject the correct built image
7. **SEC-NEW-1:** Enable HTTPS on ALB ingress (add ACM certificate, HTTPS listener, HTTP-to-HTTPS redirect)
8. **SEC-NEW-2:** Remove/replace `docker-registry-secret.yaml` — use External Secrets, Sealed Secrets, or CI/CD injection; never commit credentials
9. **SEC-NEW-3:** Add default-deny NetworkPolicies in both namespaces
10. **SEC-NEW-4:** Add Pod Security Admission labels (`pod-security.kubernetes.io/enforce: restricted`) to both namespaces
11. **SEC-NEW-5:** Dev ConfigMap references external DB host (`postgres-dev.serenitiflow.com`) instead of Terraform-managed Aurora — align with infrastructure
12. **SEC-NEW-6:** Dev and prod use the same JWT public key — use different key pairs per environment

---

## 7. Additional Security Findings (from dedicated security review)

| # | File | Line | Severity | Issue | Fix |
|---|------|------|----------|-------|-----|
| SEC-A1 | `infrastructure/k8s/dev/docker-registry-secret.yaml` | 10-20 | **Critical** | Placeholder credentials in manifest; risk of committing real credentials to Git | Remove file from repo; manage via External Secrets or CI/CD |
| SEC-A2 | `platform-user-service/config/k8s/*/deployment.yaml` | 147-149 | **Critical** | Internet-facing ALB on HTTP only — no HTTPS/TLS | Add ACM certificate, HTTPS listener, HTTP-to-HTTPS redirect |
| SEC-A3 | `infrastructure/k8s/dev/namespace.yaml` | — | Warning | No Pod Security Admission labels | Add `pod-security.kubernetes.io/enforce: restricted` |
| SEC-A4 | `infrastructure/k8s/prod/namespace.yaml` | — | Warning | No Pod Security Admission labels | Add `pod-security.kubernetes.io/enforce: restricted` |
| SEC-A5 | `platform-user-service/config/k8s/dev/deployment.yaml` | 128 | Warning | Dev ConfigMap references external DB host `postgres-dev.serenitiflow.com` instead of Aurora | Align with Terraform-managed Aurora endpoint |
| SEC-A6 | `platform-user-service/config/k8s/*/deployment.yaml` | 134 | Suggestion | Same JWT public key in dev and prod | Use different key pairs per environment |
| SEC-A7 | `modules/irsa/main.tf` | 9-38 | Warning | Single shared IRSA role per namespace — all services can read all env secrets | Consider per-service IRSA roles with scoped secret paths |
| SEC-A8 | `envs/dev/vpc-peering-prod/main.tf` | 62-77 | Warning | Full VPC CIDR bidirectional routing via peering | Scope to specific route tables; add SG/NACL restrictions |
| SEC-A9 | `modules/databases/main.tf` | 106-171 | Suggestion | Missing explicit `from_port`/`to_port` in SG rules | Add explicit ports (5432 for Aurora, 6379 for Redis) |
| SEC-A10 | `platform-user-service/config/k8s/*/deployment.yaml` | 150 | Warning | Health check `/actuator/health` exposed on public ALB | Restrict actuator endpoints via Spring Security |
