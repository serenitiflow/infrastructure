# Problem Statement: No External Access to EKS Microservices

## Current State

The EKS cluster (`serenity-shared-cluster`) is deployed with:
- **Public endpoint enabled** (for kubectl/API access)
- **Private subnets** for node groups
- **No Ingress Controller** deployed
- **No LoadBalancer Services** configured
- **No API Gateway** in front of services

Microservices running in the `dev-serenity` and `prod-serenity` namespaces are reachable only from within the cluster or via `kubectl port-forward` from a developer's workstation. There is **no stable, production-grade path for external traffic** to reach individual services.

### Why This Is a Problem

| Stakeholder | Impact |
|-------------|--------|
| **Developers** | Must run `kubectl port-forward` to test EKS-hosted services locally; pods restart and break tunnels |
| **CI/CD** | Cannot run integration tests against EKS-deployed services without brittle port-forward scripts |
| **Frontend / Mobile** | No public URL to target for local development against a remote backend |
| **Third-party integrations** | Cannot receive webhooks or API calls into cluster-hosted services |

## Constraints & Requirements

1. **Must fit the existing multi-stack Terraform architecture** — independent state files, SSM parameter decoupling
2. **Must share the single EKS cluster** across dev and prod namespaces
3. **Must not break existing `cluster_endpoint_public_access_cidrs` security model**
4. **Must be cost-conscious** — dev should not run HA resources unnecessarily
5. **Must support path-based or host-based routing** to multiple microservices from a single entrypoint

---

## Proposed Solution: AWS Load Balancer Controller + ALB Ingress

Deploy the [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/) into the shared EKS cluster and expose services via Kubernetes `Ingress` resources. The controller automatically provisions and manages AWS Application Load Balancers (ALB) based on Ingress definitions.

### Architecture Overview

```
                         Internet
                            |
                            v
              +-------------------------+
              |   AWS ALB (internet-fac. |
              |   or internal + VPN)     |
              +------------+------------+
                           |
              +------------v------------+
              |  Ingress (dev/prod)      |
              |  - host: dev.api...      |
              |  - host: prod.api...     |
              +------------+------------+
                           |
        +------------------+------------------+
        |                  |                  |
   +----v----+      +-----v-----+      +-----v-----+
   |user-svc |      |order-svc  |      |notify-svc |
   |:8080    |      |:8080      |      |:8080      |
   +---------+      +-----------+      +-----------+
```

### Why ALB Instead of NLB / API Gateway / Istio

| Option | Verdict | Reason |
|--------|---------|--------|
| **ALB (chosen)** | Best fit | Native AWS, path/host routing, TLS termination, WAF integration, cost-effective for dev |
| NLB | Rejected | Layer-4 only, no path-based routing, one NLB per Service gets expensive |
| API Gateway | Overkill | Adds $3.50/million requests + latency; unnecessary until we need throttling/usage plans |
| Istio/Gateway | Overkill | Requires sidecar injection, complex ops; reconsider when service mesh is justified |

---

## Terraform Integration Plan

### 1. New Stack: `common/alb-controller`

A new independent stack under `envs/common/alb-controller/` to keep the ALB Controller lifecycle separate from EKS upgrades.

**Responsibilities:**
- Create the IRSA IAM role for the ALB Controller (requires OIDC provider from EKS)
- Deploy the controller via Helm (using the `helm` Terraform provider)
- Write SSM parameters for the ALB security group ID and Ingress class name

**Why a separate stack:**
- The controller can be upgraded independently of the EKS cluster version
- Keeps the `common/eks` stack focused on compute only
- Follows the existing "independent state files" principle

**Inputs (read via SSM):**
- `/serenity/shared/eks/cluster_name`
- `/serenity/shared/eks/cluster_endpoint`
- `/serenity/shared/eks/oidc_provider_arn`

**Outputs (written to SSM):**
- `/serenity/shared/alb-controller/security_group_id`
- `/serenity/shared/alb-controller/ingress_class_name`

### 2. IAM Permissions (IRSA)

The ALB Controller needs broad permissions to manage ALBs, target groups, and security groups. These are well-documented in the upstream project and should be attached to a dedicated IRSA role:

```
arn:aws:iam::${account}:role/serenity-alb-controller-role
```

Trusted entity: the EKS OIDC provider, restricted to the `kube-system/aws-load-balancer-controller` service account.

### 3. Helm Deployment

Chart: `aws-load-balancer-controller` from EKS Helm repo  
Namespace: `kube-system`

Key values:
```yaml
clusterName: serenity-shared-cluster
serviceAccount:
  create: true
  name: aws-load-balancer-controller
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::...:role/serenity-alb-controller-role
```

### 4. Ingress Resources Per Environment

Each environment (dev, prod) manages its own `Ingress` resources in its respective namespace. Example for dev user-service:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: user-service
  namespace: dev-serenity
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:...:cert-id
spec:
  ingressClassName: alb
  rules:
    - host: dev-api.serenityflow.com
      http:
        paths:
          - path: /users
            pathType: Prefix
            backend:
              service:
                name: user-service
                port:
                  number: 8080
```

**Note:** A single ALB can serve multiple Ingress resources if they share the same group annotation (`alb.ingress.kubernetes.io/group.name`), reducing cost.

---

## Deployment Order

```
# 1. EKS must already exist ( prerequisite)
cd envs/common/eks && terraform apply

# 2. Deploy ALB Controller stack
cd envs/common/alb-controller
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply

# 3. Apply Ingress resources (after microservices are deployed)
kubectl apply -f infrastructure/k8s/dev/ingresses/
kubectl apply -f infrastructure/k8s/prod/ingresses/
```

---

## Security Considerations

| Concern | Mitigation |
|---------|------------|
| **Public ALB exposes dev environment** | Use `scheme: internal` for dev + AWS Client VPN; or restrict via `inbound-cidrs` annotation to office/VPN CIDRs |
| **Certificate management** | Use ACM (AWS Certificate Manager) — free, auto-renewed |
| **WAF / rate limiting** | Attach AWS WAFv2 WebACL to ALB for prod; optional for dev |
| **Controller IAM permissions** | Use the official least-privilege IAM policy from the ALB Controller docs; never use wildcards |

### Dev-Only Recommendation

For the dev environment, consider an **internal ALB** accessible via:
- AWS Client VPN (self-service, ~$0.10/hour + $0.05/connection-hour)
- Or `kubectl port-forward` for ad-hoc access (zero cost, no infra)

This avoids exposing dev microservices to the public internet while still giving developers stable endpoints.

---

## Cost Impact

| Resource | Dev Estimate | Prod Estimate |
|----------|-------------|---------------|
| ALB (Application Load Balancer) | ~$16/mo + LCU charges | ~$16/mo + LCU charges |
| AWS Client VPN (optional dev) | ~$73/mo (always-on) | N/A |
| ACM Certificate | Free | Free |
| WAFv2 (optional) | ~$5/mo + requests | ~$5/mo + requests |

**Total incremental cost:** ~$16-90/mo for dev, ~$21/mo for prod (without WAF).

---

## Acceptance Criteria

- [ ] `envs/common/alb-controller` stack exists with independent state
- [ ] ALB Controller pods are `Running` in `kube-system`
- [ ] A dev microservice (e.g., user-service) is reachable via a stable URL without `kubectl port-forward`
- [ ] Prod microservices are reachable via a separate host/path with TLS
- [ ] IRSA role follows least-privilege and is restricted to the controller service account
- [ ] SSM parameters are written for downstream stacks to consume

---

## Decision Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-04-20 | ALB Controller over NLB | Path-based routing + cost |
| 2026-04-20 | Separate `common/alb-controller` stack | Independent lifecycle from EKS |
| 2026-04-20 | Internal ALB recommended for dev | Security over convenience |
