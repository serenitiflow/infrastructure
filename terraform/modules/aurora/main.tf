locals {
  common_tags = {
    Name        = "${var.project_name}-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
    App         = "${var.app}-${var.environment}"
    ManagedBy   = "terraform"
    Stack       = "aurora"
  }

  # Aurora cluster name for referencing in IAM policies
  aurora_cluster_name = "${var.project_name}-${var.environment}-aurora"
}

# KMS Key for Secrets Manager
resource "aws_kms_key" "secrets" {
  description             = "KMS key for Secrets Manager"
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
  name          = "alias/${var.project_name}-${var.environment}-secrets"
  target_key_id = aws_kms_key.secrets.key_id
}

resource "random_password" "db_password" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"

  keepers = {
    environment = var.environment
  }
}

# Aurora Module
module "aurora" {
  source  = "terraform-aws-modules/rds-aurora/aws"
  version = "~> 9.0"

  name           = local.aurora_cluster_name
  engine         = "aurora-postgresql"
  engine_version = "16.4"
  engine_mode    = "provisioned"

  instance_class = var.aurora_instance_class

  serverlessv2_scaling_configuration = {
    min_capacity = var.aurora_min_capacity
    max_capacity = var.aurora_max_capacity
  }

  database_name   = "serenity"
  master_username = var.db_username
  master_password = random_password.db_password.result

  vpc_id               = data.aws_ssm_parameter.vpc_id.value
  db_subnet_group_name = data.aws_ssm_parameter.database_subnet_group_name.value

  create_security_group = true
  security_group_rules = {
    eks_ingress = {
      source_security_group_id = data.aws_ssm_parameter.cluster_security_group_id.value
      from_port                = 5432
      to_port                  = 5432
      description              = "PostgreSQL from EKS"
    }
    admin_ingress = {
      cidr_blocks = var.allowed_admin_cidrs
      from_port   = 5432
      to_port     = 5432
      description = "PostgreSQL from admin IPs"
    }
  }

  instances = {
    writer = {
      instance_class               = var.aurora_instance_class
      publicly_accessible          = false
      performance_insights_enabled = var.environment == "prod"
    }
  }

  backup_retention_period = var.backup_retention_period
  preferred_backup_window = "03:00-04:00"
  skip_final_snapshot     = var.environment != "prod"
  deletion_protection     = var.environment == "prod"

  storage_encrypted = true

  enabled_cloudwatch_logs_exports = var.environment == "prod" ? ["postgresql"] : []
  performance_insights_enabled    = var.environment == "prod"

  tags = local.common_tags
}

module "aurora_scheduler" {
  source = "../../../terraform/modules/aurora-scheduler"
  # References original module to avoid drift

  count = var.aurora_scheduler_enabled ? 1 : 0

  project_name = var.project_name
  environment  = var.environment
  cluster_id   = module.aurora.cluster_id

  schedule_enabled = var.aurora_scheduler_enabled

  tags = local.common_tags
}

# Secrets Manager - Aurora
resource "aws_secretsmanager_secret" "aurora_credentials" {
  name       = "${var.project_name}/${var.environment}/database/credentials-v2"
  kms_key_id = aws_kms_key.secrets.arn
}

resource "aws_secretsmanager_secret_version" "aurora_credentials" {
  secret_id = aws_secretsmanager_secret.aurora_credentials.id
  secret_string = jsonencode({
    username        = var.db_username
    password        = random_password.db_password.result
    host            = module.aurora.cluster_endpoint
    port            = 5432
    dbname          = "serenity"
    reader_endpoint = module.aurora.cluster_reader_endpoint
    jdbc_url        = "jdbc:postgresql://${module.aurora.cluster_endpoint}:5432/serenity"
  })
}

# SSM Parameters for application stacks
resource "aws_ssm_parameter" "database_host" {
  name      = "/${var.project_name}/${var.environment}/database/host"
  type      = "String"
  value     = module.aurora.cluster_endpoint
  overwrite = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-database-host"
  })
}

resource "aws_ssm_parameter" "database_reader_endpoint" {
  name      = "/${var.project_name}/${var.environment}/database/reader_endpoint"
  type      = "String"
  value     = module.aurora.cluster_reader_endpoint
  overwrite = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-database-reader-endpoint"
  })
}

resource "aws_ssm_parameter" "database_port" {
  name      = "/${var.project_name}/${var.environment}/database/port"
  type      = "String"
  value     = "5432"
  overwrite = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-database-port"
  })
}

resource "aws_ssm_parameter" "database_name" {
  name      = "/${var.project_name}/${var.environment}/database/name"
  type      = "String"
  value     = "serenity"
  overwrite = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-database-name"
  })
}

resource "aws_ssm_parameter" "database_secret_arn" {
  name      = "/${var.project_name}/${var.environment}/database/secret_arn"
  type      = "String"
  value     = aws_secretsmanager_secret.aurora_credentials.arn
  overwrite = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-database-secret-arn"
  })
}
