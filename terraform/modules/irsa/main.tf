data "aws_caller_identity" "current" {}

locals {
  oidc_provider = replace(var.oidc_issuer_url, "https://", "")
  role_name     = "${var.project_name}-${var.environment}-services-role"
}

# IAM Role for IRSA
resource "aws_iam_role" "namespace_services" {
  name = local.role_name

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
            "${local.oidc_provider}:sub" = "system:serviceaccount:${var.namespace}:${var.service_account_name}"
          }
        }
      }
    ]
  })

  tags = {
    Name        = local.role_name
    Environment = var.environment
    Project     = var.project_name
    Namespace   = var.namespace
    ManagedBy   = "terraform"
  }
}

# Policy: read env-specific Secrets Manager secrets
resource "aws_iam_role_policy" "secrets_read" {
  name = "${var.project_name}-${var.environment}-secrets-read"
  role = aws_iam_role.namespace_services.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = "arn:aws:secretsmanager:eu-central-1:${data.aws_caller_identity.current.account_id}:secret:${var.project_name}/${var.environment}/*"
      }
    ]
  })
}

# Output
output "role_arn" {
  description = "ARN of the created IRSA role"
  value       = aws_iam_role.namespace_services.arn
}

output "role_name" {
  description = "Name of the created IRSA role"
  value       = aws_iam_role.namespace_services.name
}
