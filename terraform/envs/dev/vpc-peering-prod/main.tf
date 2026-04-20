# VPC Peering: dev VPC <-> prod VPC
# OPTIONAL: Enable only when prod networking is deployed
# For dev-only deployments, skip this stack entirely

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

data "aws_ssm_parameter" "dev_database_route_table_ids" {
  name = "/${var.project_name}/dev/networking/database_route_table_ids"
}

# Prod networking parameters — only read when enabled
data "aws_ssm_parameter" "prod_vpc_id" {
  count = var.enabled ? 1 : 0
  name  = "/${var.project_name}/prod/networking/vpc_id"
}

data "aws_ssm_parameter" "prod_vpc_cidr" {
  count = var.enabled ? 1 : 0
  name  = "/${var.project_name}/prod/networking/vpc_cidr"
}

data "aws_ssm_parameter" "prod_database_route_table_ids" {
  count = var.enabled ? 1 : 0
  name  = "/${var.project_name}/prod/networking/database_route_table_ids"
}

locals {
  dev_database_route_table_ids  = jsondecode(data.aws_ssm_parameter.dev_database_route_table_ids.value)
  prod_database_route_table_ids = var.enabled ? jsondecode(data.aws_ssm_parameter.prod_database_route_table_ids[0].value) : []
}

# VPC Peering Connection
resource "aws_vpc_peering_connection" "dev_to_prod" {
  count = var.enabled ? 1 : 0

  vpc_id        = data.aws_ssm_parameter.dev_vpc_id.value
  peer_vpc_id   = var.enabled ? data.aws_ssm_parameter.prod_vpc_id[0].value : ""
  peer_owner_id = data.aws_caller_identity.current.account_id
  auto_accept   = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-dev-to-prod"
  })
}

# Dev database route tables -> prod CIDR
resource "aws_route" "dev_to_prod" {
  for_each = var.enabled ? toset(local.dev_database_route_table_ids) : []

  route_table_id            = each.value
  destination_cidr_block    = var.enabled ? data.aws_ssm_parameter.prod_vpc_cidr[0].value : ""
  vpc_peering_connection_id = aws_vpc_peering_connection.dev_to_prod[0].id
}

# Prod database route tables -> dev CIDR
resource "aws_route" "prod_to_dev" {
  for_each = var.enabled ? toset(local.prod_database_route_table_ids) : []

  route_table_id            = each.value
  destination_cidr_block    = data.aws_ssm_parameter.dev_vpc_cidr.value
  vpc_peering_connection_id = aws_vpc_peering_connection.dev_to_prod[0].id
}
