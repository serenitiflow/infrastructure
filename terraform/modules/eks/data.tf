# Read networking outputs from SSM Parameter Store
# This approach is decoupled - stacks can be destroyed/recreated independently

data "aws_caller_identity" "current" {}

data "aws_ssm_parameter" "vpc_id" {
  name = "/${var.project_name}/${var.environment}/networking/vpc_id"
}

data "aws_ssm_parameter" "private_subnet_ids" {
  name = "/${var.project_name}/${var.environment}/networking/private_subnet_ids"
}

data "aws_ssm_parameter" "public_subnet_ids" {
  name = "/${var.project_name}/${var.environment}/networking/public_subnet_ids"
}

# Parse JSON arrays from SSM
locals {
  private_subnet_ids = jsondecode(data.aws_ssm_parameter.private_subnet_ids.value)
  public_subnet_ids  = jsondecode(data.aws_ssm_parameter.public_subnet_ids.value)
}
