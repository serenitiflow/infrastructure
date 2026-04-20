module "eks" {
  source = "../../modules/eks"

  project_name                   = var.project_name
  app                            = var.app
  environment                    = var.environment
  aws_region                     = var.aws_region
  kubernetes_version             = var.kubernetes_version
  cluster_endpoint_public_access = var.cluster_endpoint_public_access
  allowed_public_cidrs           = var.allowed_public_cidrs
  capacity_type                  = var.capacity_type
  node_instance_types            = var.node_instance_types
  node_desired_size              = var.node_desired_size
  node_min_size                  = var.node_min_size
  node_max_size                  = var.node_max_size
  cloudwatch_retention_days      = var.cloudwatch_retention_days
  cluster_enabled_log_types      = var.cluster_enabled_log_types
  access_entries                 = var.access_entries
}

# ---------------------------------------------------------------------------
# IRSA IAM Roles (merged from eks-irsa stack — eliminates SSM indirection)
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

locals {
  oidc_provider  = replace(module.eks.cluster_oidc_issuer_url, "https://", "")
  dev_role_name  = "${var.project_name}-dev-services-role"
  prod_role_name = "${var.project_name}-prod-services-role"
}

# --- Dev IRSA role (always created) ---

resource "aws_iam_role" "dev_namespace_services" {
  name = local.dev_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.oidc_provider}"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.oidc_provider}:aud" = "sts.amazonaws.com"
            "${local.oidc_provider}:sub" = "system:serviceaccount:dev-serenity:serenity-services"
          }
        }
      }
    ]
  })

  tags = {
    Name        = local.dev_role_name
    Environment = "dev"
    Project     = var.project_name
    Namespace   = "dev-serenity"
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_role_policy" "dev_secrets_read" {
  name = "${var.project_name}-dev-secrets-read"
  role = aws_iam_role.dev_namespace_services.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = "arn:aws:secretsmanager:eu-central-1:${data.aws_caller_identity.current.account_id}:secret:${var.project_name}/dev/*"
      }
    ]
  })
}

# --- Prod IRSA role (conditionally created) ---

resource "aws_iam_role" "prod_namespace_services" {
  count = var.create_prod_irsa ? 1 : 0
  name  = local.prod_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.oidc_provider}"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.oidc_provider}:aud" = "sts.amazonaws.com"
            "${local.oidc_provider}:sub" = "system:serviceaccount:prod-serenity:serenity-services"
          }
        }
      }
    ]
  })

  tags = {
    Name        = local.prod_role_name
    Environment = "prod"
    Project     = var.project_name
    Namespace   = "prod-serenity"
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_role_policy" "prod_secrets_read" {
  count = var.create_prod_irsa ? 1 : 0
  name  = "${var.project_name}-prod-secrets-read"
  role  = aws_iam_role.prod_namespace_services[count.index].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = "arn:aws:secretsmanager:eu-central-1:${data.aws_caller_identity.current.account_id}:secret:${var.project_name}/prod/*"
      }
    ]
  })
}

# Write role ARNs to SSM for CI/CD and K8s manifest reference
resource "aws_ssm_parameter" "dev_irsa_role_arn" {
  name  = "/${var.project_name}/dev/eks/irsa_services_role_arn"
  type  = "String"
  value = aws_iam_role.dev_namespace_services.arn

  tags = {
    Name        = "${var.project_name}-dev-irsa-role-arn"
    Environment = "dev"
    Project     = var.project_name
    ManagedBy   = "terraform"
  }
}

resource "aws_ssm_parameter" "prod_irsa_role_arn" {
  count = var.create_prod_irsa ? 1 : 0

  name  = "/${var.project_name}/prod/eks/irsa_services_role_arn"
  type  = "String"
  value = aws_iam_role.prod_namespace_services[count.index].arn

  tags = {
    Name        = "${var.project_name}-prod-irsa-role-arn"
    Environment = "prod"
    Project     = var.project_name
    ManagedBy   = "terraform"
  }
}

# ---------------------------------------------------------------------------
# Kubernetes Namespaces & ServiceAccounts for IRSA
# ---------------------------------------------------------------------------

resource "kubernetes_namespace_v1" "dev_serenity" {
  metadata {
    name = "dev-serenity"
    labels = {
      Environment = "dev"
      Project     = var.project_name
      ManagedBy   = "terraform"
    }
  }
}

resource "kubernetes_namespace_v1" "prod_serenity" {
  count = var.create_prod_irsa ? 1 : 0

  metadata {
    name = "prod-serenity"
    labels = {
      Environment = "prod"
      Project     = var.project_name
      ManagedBy   = "terraform"
    }
  }
}

resource "kubernetes_service_account_v1" "dev_services" {
  depends_on = [kubernetes_namespace_v1.dev_serenity]

  metadata {
    name      = "serenity-services"
    namespace = kubernetes_namespace_v1.dev_serenity.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.dev_namespace_services.arn
    }
    labels = {
      Environment = "dev"
      Project     = var.project_name
      ManagedBy   = "terraform"
    }
  }
}

resource "kubernetes_service_account_v1" "prod_services" {
  count = var.create_prod_irsa ? 1 : 0

  depends_on = [kubernetes_namespace_v1.prod_serenity]

  metadata {
    name      = "serenity-services"
    namespace = kubernetes_namespace_v1.prod_serenity[count.index].metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.prod_namespace_services[count.index].arn
    }
    labels = {
      Environment = "prod"
      Project     = var.project_name
      ManagedBy   = "terraform"
    }
  }
}
