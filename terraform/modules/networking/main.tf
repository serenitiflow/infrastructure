locals {
  common_tags = {
    Name        = "${var.project_name}-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
    App         = "${var.app}-${var.environment}"
    ManagedBy   = "terraform"
    Stack       = "networking"
  }
}

# VPC Module
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.project_name}-${var.environment}"
  cidr = "10.0.0.0/16"

  azs              = ["${var.aws_region}a", "${var.aws_region}b"]
  private_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets   = ["10.0.101.0/24", "10.0.102.0/24"]
  database_subnets = ["10.0.201.0/24", "10.0.202.0/24"]

  enable_nat_gateway     = var.nat_gateway_enabled
  single_nat_gateway     = var.environment != "prod"
  one_nat_gateway_per_az = var.environment == "prod"

  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnet_tags = {
    Type = "public"
  }

  private_subnet_tags = {
    Type = "private"
  }

  database_subnet_tags = {
    Type = "database"
  }

  tags = local.common_tags
}

# NAT Instance Module (optional)
module "nat_instance" {
  source = "../../../terraform/modules/nat-instance"
  # Note: References original module to avoid drift

  enabled = !var.nat_gateway_enabled

  project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.vpc.vpc_id

  public_subnet_id        = module.vpc.public_subnets[0]
  private_subnets_cidr    = module.vpc.private_subnets_cidr_blocks
  private_route_table_ids = module.vpc.private_route_table_ids
  private_cidr            = "10.0.0.0/16"

  instance_type = var.nat_instance_type

  tags = local.common_tags
}

# SSM Parameters for cross-stack communication (decoupled approach)
resource "aws_ssm_parameter" "vpc_id" {
  name      = "/${var.project_name}/${var.environment}/networking/vpc_id"
  type      = "String"
  value     = module.vpc.vpc_id
  overwrite = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-vpc-id"
  })
}

resource "aws_ssm_parameter" "vpc_cidr" {
  name      = "/${var.project_name}/${var.environment}/networking/vpc_cidr"
  type      = "String"
  value     = module.vpc.vpc_cidr_block
  overwrite = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-vpc-cidr"
  })
}

resource "aws_ssm_parameter" "private_subnet_ids" {
  name      = "/${var.project_name}/${var.environment}/networking/private_subnet_ids"
  type      = "String"
  value     = jsonencode(module.vpc.private_subnets)
  overwrite = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-private-subnet-ids"
  })
}

resource "aws_ssm_parameter" "public_subnet_ids" {
  name      = "/${var.project_name}/${var.environment}/networking/public_subnet_ids"
  type      = "String"
  value     = jsonencode(module.vpc.public_subnets)
  overwrite = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-public-subnet-ids"
  })
}

resource "aws_ssm_parameter" "database_subnet_ids" {
  name      = "/${var.project_name}/${var.environment}/networking/database_subnet_ids"
  type      = "String"
  value     = jsonencode(module.vpc.database_subnets)
  overwrite = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-database-subnet-ids"
  })
}

resource "aws_ssm_parameter" "database_subnet_group_name" {
  name      = "/${var.project_name}/${var.environment}/networking/database_subnet_group_name"
  type      = "String"
  value     = module.vpc.database_subnet_group_name
  overwrite = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-database-subnet-group"
  })
}

resource "aws_ssm_parameter" "private_route_table_ids" {
  name      = "/${var.project_name}/${var.environment}/networking/private_route_table_ids"
  type      = "String"
  value     = jsonencode(module.vpc.private_route_table_ids)
  overwrite = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-private-rt-ids"
  })
}

resource "aws_ssm_parameter" "public_route_table_ids" {
  name      = "/${var.project_name}/${var.environment}/networking/public_route_table_ids"
  type      = "String"
  value     = jsonencode(module.vpc.public_route_table_ids)
  overwrite = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-public-rt-ids"
  })
}

resource "aws_ssm_parameter" "nat_gateway_id" {
  name      = "/${var.project_name}/${var.environment}/networking/nat_gateway_id"
  type      = "String"
  value     = var.nat_gateway_enabled ? module.vpc.nat_gateway_ids[0] : "disabled"
  overwrite = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-nat-gateway-id"
  })
}

resource "aws_ssm_parameter" "nat_instance_id" {
  name      = "/${var.project_name}/${var.environment}/networking/nat_instance_id"
  type      = "String"
  value     = module.nat_instance.nat_instance_id
  overwrite = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-nat-instance-id"
  })
}
