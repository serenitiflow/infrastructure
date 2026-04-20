locals {
  common_tags = {
    Name        = "${var.project_name}-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
    App         = "${var.app}-${var.environment}"
    ManagedBy   = "terraform"
    Stack       = "eks"
  }
}

# KMS Key for EKS Secrets Encryption
resource "aws_kms_key" "eks" {
  description             = "KMS key for EKS secrets encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Allow EKS Service"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:CallerAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "Allow Key Administration"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      }
    ]
  })
}

resource "aws_kms_alias" "eks" {
  name          = "alias/${var.project_name}-${var.environment}-eks"
  target_key_id = aws_kms_key.eks.key_id
}

# EKS Module
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "${var.project_name}-${var.environment}-cluster"
  cluster_version = var.kubernetes_version

  cluster_endpoint_public_access  = var.cluster_endpoint_public_access
  cluster_endpoint_private_access = true

  cluster_endpoint_public_access_cidrs = var.allowed_public_cidrs

  cluster_enabled_log_types = var.cluster_enabled_log_types

  cloudwatch_log_group_retention_in_days = var.cloudwatch_retention_days

  cluster_encryption_config = {
    provider_key_arn = aws_kms_key.eks.arn
    resources        = ["secrets"]
  }

  vpc_id     = data.aws_ssm_parameter.vpc_id.value
  subnet_ids = local.private_subnet_ids

  enable_cluster_creator_admin_permissions = true

  access_entries = var.access_entries

  eks_managed_node_groups = {
    main = {
      name = "main-nodes"

      ami_type       = startswith(var.node_instance_types[0], "t4g") || startswith(var.node_instance_types[0], "m6g") || startswith(var.node_instance_types[0], "c6g") || startswith(var.node_instance_types[0], "r6g") ? "AL2023_ARM_64_STANDARD" : "AL2023_x86_64_STANDARD"
      instance_types = var.node_instance_types
      capacity_type  = var.capacity_type

      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size

      labels = merge(
        { role = "general" },
        var.capacity_type == "SPOT" ? { spot = "true" } : {}
      )

      tags = {
        Environment = var.environment
      }
    }
  }

  tags = local.common_tags
}

# SSM Parameters for cross-stack communication (decoupled approach)
resource "aws_ssm_parameter" "cluster_name" {
  name      = "/${var.project_name}/shared/eks/cluster_name"
  type      = "String"
  value     = module.eks.cluster_name
  overwrite = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-eks-cluster-name"
  })
}

resource "aws_ssm_parameter" "cluster_endpoint" {
  name      = "/${var.project_name}/shared/eks/cluster_endpoint"
  type      = "String"
  value     = module.eks.cluster_endpoint
  overwrite = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-eks-cluster-endpoint"
  })
}

resource "aws_ssm_parameter" "cluster_security_group_id" {
  name      = "/${var.project_name}/shared/eks/cluster_security_group_id"
  type      = "String"
  value     = module.eks.cluster_security_group_id
  overwrite = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-eks-sg-id"
  })
}

resource "aws_ssm_parameter" "cluster_oidc_issuer_url" {
  name      = "/${var.project_name}/shared/eks/cluster_oidc_issuer_url"
  type      = "String"
  value     = module.eks.cluster_oidc_issuer_url
  overwrite = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-eks-oidc-url"
  })
}

resource "aws_ssm_parameter" "oidc_provider_arn" {
  name      = "/${var.project_name}/shared/eks/oidc_provider_arn"
  type      = "String"
  value     = module.eks.oidc_provider_arn
  overwrite = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-eks-oidc-arn"
  })
}

