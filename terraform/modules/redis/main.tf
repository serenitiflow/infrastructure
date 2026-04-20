locals {
  common_tags = {
    Name        = "${var.project_name}-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
    App         = "${var.app}-${var.environment}"
    ManagedBy   = "terraform"
    Stack       = "redis"
  }
}

# KMS Key for Secrets Manager
resource "aws_kms_key" "secrets" {
  description             = "KMS key for Redis Secrets Manager"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow Secrets Manager Service"
        Effect = "Allow"
        Principal = {
          Service = "secretsmanager.amazonaws.com"
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
      }
    ]
  })
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/${var.project_name}-${var.environment}-redis-secrets"
  target_key_id = aws_kms_key.secrets.key_id
}

resource "random_password" "redis_auth_token" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"

  keepers = {
    environment = var.environment
  }
}

# ElastiCache Module
module "elasticache" {
  source  = "terraform-aws-modules/elasticache/aws"
  version = "~> 1.0"

  replication_group_id = "${var.project_name}-${var.environment}-redis"

  engine_version       = "7.0"
  node_type            = var.redis_node_type
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"

  subnet_group_name = "${var.project_name}-${var.environment}-redis-subnet"
  subnet_ids        = local.database_subnet_ids
  vpc_id            = data.aws_ssm_parameter.vpc_id.value

  create_security_group = true
  security_group_rules = {
    eks_ingress = {
      referenced_security_group_id = data.aws_ssm_parameter.cluster_security_group_id.value
      from_port                    = 6379
      to_port                      = 6379
      description                  = "Redis from EKS"
    }
    admin_ingress = {
      cidr_blocks = var.allowed_admin_cidrs
      from_port   = 6379
      to_port     = 6379
      description = "Redis from admin IPs"
    }
  }

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                 = random_password.redis_auth_token.result

  snapshot_retention_limit = var.snapshot_retention_limit
  snapshot_window          = "03:00-04:00"

  tags = local.common_tags
}

# Secrets Manager - Redis
resource "aws_secretsmanager_secret" "redis_credentials" {
  name       = "${var.project_name}/${var.environment}/redis/credentials-v2"
  kms_key_id = aws_kms_key.secrets.arn
}

resource "aws_secretsmanager_secret_version" "redis_credentials" {
  secret_id = aws_secretsmanager_secret.redis_credentials.id
  secret_string = jsonencode({
    endpoint = module.elasticache.replication_group_primary_endpoint_address
    port     = 6379
    password = random_password.redis_auth_token.result
  })
}

# SSM Parameters for application stacks
resource "aws_ssm_parameter" "redis_host" {
  name      = "/${var.project_name}/${var.environment}/redis/host"
  type      = "String"
  value     = module.elasticache.replication_group_primary_endpoint_address
  overwrite = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-redis-host"
  })
}

resource "aws_ssm_parameter" "redis_port" {
  name      = "/${var.project_name}/${var.environment}/redis/port"
  type      = "String"
  value     = "6379"
  overwrite = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-redis-port"
  })
}

resource "aws_ssm_parameter" "redis_secret_arn" {
  name      = "/${var.project_name}/${var.environment}/redis/secret_arn"
  type      = "String"
  value     = aws_secretsmanager_secret.redis_credentials.arn
  overwrite = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-redis-secret-arn"
  })
}
