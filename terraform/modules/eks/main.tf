module "common_tags" {
  source = "../common-tags"

  project_name = var.project_name
  app          = var.app
  environment  = var.environment
  stack        = "eks"
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

  tags = module.common_tags.tags
}

# SSM Parameters for cross-stack communication (decoupled approach)
module "ssm_parameters" {
  source = "../ssm-parameters"

  tags = module.common_tags.tags

  parameters = {
    "/${var.project_name}/shared/eks/cluster_name" = {
      value = module.eks.cluster_name
    }
    "/${var.project_name}/shared/eks/cluster_endpoint" = {
      value = module.eks.cluster_endpoint
    }
    "/${var.project_name}/shared/eks/cluster_security_group_id" = {
      value = module.eks.cluster_security_group_id
    }
    "/${var.project_name}/shared/eks/node_security_group_id" = {
      value = module.eks.node_security_group_id
    }
    "/${var.project_name}/shared/eks/cluster_oidc_issuer_url" = {
      value = module.eks.cluster_oidc_issuer_url
    }
    "/${var.project_name}/shared/eks/oidc_provider_arn" = {
      value = module.eks.oidc_provider_arn
    }
  }
}

