data "aws_caller_identity" "current" {}

# KMS Key for database secrets encryption
resource "aws_kms_key" "this" {
  description             = "KMS key for ${var.service} Secrets Manager"
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

  tags = var.tags
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.alias_name}"
  target_key_id = aws_kms_key.this.key_id
}

# Random password for database
resource "random_password" "this" {
  length           = var.password_length
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"

  keepers = {
    environment = var.environment
  }
}

# Secrets Manager secret (empty — version written by caller to include dynamic endpoints)
resource "aws_secretsmanager_secret" "this" {
  name       = var.secret_name
  kms_key_id = aws_kms_key.this.arn

  tags = var.tags
}
