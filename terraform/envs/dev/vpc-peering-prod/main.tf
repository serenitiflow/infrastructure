# VPC Peering: dev VPC <-> prod VPC
# Enables cross-VPC routing for shared EKS cluster (in dev VPC) to reach prod databases

locals {
  common_tags = {
    Name        = "${var.project_name}-dev-to-prod"
    Environment = var.environment
    Project     = var.project_name
    App         = var.app
    ManagedBy   = "terraform"
    Stack       = "vpc-peering"
  }
}

# Get current AWS account ID
data "aws_caller_identity" "current" {}

# Dev networking parameters
data "aws_ssm_parameter" "dev_vpc_id" {
  name = "/${var.project_name}/dev/networking/vpc_id"
}

data "aws_ssm_parameter" "dev_vpc_cidr" {
  name = "/${var.project_name}/dev/networking/vpc_cidr"
}

data "aws_ssm_parameter" "dev_private_route_table_ids" {
  name = "/${var.project_name}/dev/networking/private_route_table_ids"
}

# Prod networking parameters
data "aws_ssm_parameter" "prod_vpc_id" {
  name = "/${var.project_name}/prod/networking/vpc_id"
}

data "aws_ssm_parameter" "prod_vpc_cidr" {
  name = "/${var.project_name}/prod/networking/vpc_cidr"
}

data "aws_ssm_parameter" "prod_private_route_table_ids" {
  name = "/${var.project_name}/prod/networking/private_route_table_ids"
}

locals {
  dev_private_route_table_ids  = jsondecode(data.aws_ssm_parameter.dev_private_route_table_ids.value)
  prod_private_route_table_ids = jsondecode(data.aws_ssm_parameter.prod_private_route_table_ids.value)
}

# VPC Peering Connection
resource "aws_vpc_peering_connection" "dev_to_prod" {
  vpc_id        = data.aws_ssm_parameter.dev_vpc_id.value
  peer_vpc_id   = data.aws_ssm_parameter.prod_vpc_id.value
  peer_owner_id = data.aws_caller_identity.current.account_id
  auto_accept   = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-dev-to-prod"
  })
}

# Dev private route tables -> prod CIDR
resource "aws_route" "dev_to_prod" {
  for_each = toset(local.dev_private_route_table_ids)

  route_table_id            = each.value
  destination_cidr_block    = data.aws_ssm_parameter.prod_vpc_cidr.value
  vpc_peering_connection_id = aws_vpc_peering_connection.dev_to_prod.id
}

# Prod private route tables -> dev CIDR
resource "aws_route" "prod_to_dev" {
  for_each = toset(local.prod_private_route_table_ids)

  route_table_id            = each.value
  destination_cidr_block    = data.aws_ssm_parameter.dev_vpc_cidr.value
  vpc_peering_connection_id = aws_vpc_peering_connection.dev_to_prod.id
}
