module "common_tags" {
  source = "../common-tags"

  project_name = var.project_name
  app          = var.app
  environment  = var.environment
  stack        = "redis"
}

module "database_common" {
  source = "../database-common"

  alias_name  = "${var.project_name}-${var.environment}-redis-secrets"
  secret_name = "${var.project_name}/${var.environment}/redis/credentials"
  environment = var.environment
  service     = "Redis"
  tags        = module.common_tags.tags
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
  security_group_rules = merge({
    eks_ingress = {
      referenced_security_group_id = data.aws_ssm_parameter.node_security_group_id.value
      from_port                    = 6379
      to_port                      = 6379
      description                  = "Redis from EKS nodes"
    }
    }, length(var.allowed_admin_cidrs) > 0 ? {
    admin_ingress = {
      cidr_ipv4   = var.allowed_admin_cidrs[0]
      from_port   = 6379
      to_port     = 6379
      description = "Redis from admin IPs"
    }
  } : {})

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                 = module.database_common.password

  snapshot_retention_limit = var.snapshot_retention_limit
  snapshot_window          = "03:00-04:00"

  tags = module.common_tags.tags
}

# Secrets Manager version (secret created by database-common module)
resource "aws_secretsmanager_secret_version" "redis_credentials" {
  secret_id = module.database_common.secret_id
  secret_string = jsonencode({
    endpoint = module.elasticache.replication_group_primary_endpoint_address
    port     = 6379
    password = module.database_common.password
  })
}

# SSM Parameters for application stacks
module "ssm_parameters" {
  source = "../ssm-parameters"

  tags = module.common_tags.tags

  parameters = {
    "/${var.project_name}/${var.environment}/redis/host" = {
      value = module.elasticache.replication_group_primary_endpoint_address
    }
    "/${var.project_name}/${var.environment}/redis/port" = {
      value = "6379"
    }
    "/${var.project_name}/${var.environment}/redis/secret_arn" = {
      value = module.database_common.secret_arn
    }
  }
}
