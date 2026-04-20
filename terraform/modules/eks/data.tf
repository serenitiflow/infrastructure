# Read networking outputs from SSM Parameter Store
# This approach is decoupled - stacks can be destroyed/recreated independently

data "aws_caller_identity" "current" {}

variable "networking_environment" {
  description = "Environment whose VPC/subnets to use for the cluster"
  type        = string
  default     = "dev"
}

data "aws_ssm_parameter" "vpc_id" {
  name = "/${var.project_name}/${var.networking_environment}/networking/vpc_id"
}

data "aws_ssm_parameter" "private_subnet_ids" {
  name = "/${var.project_name}/${var.networking_environment}/networking/private_subnet_ids"
}

data "aws_ssm_parameter" "public_subnet_ids" {
  name = "/${var.project_name}/${var.networking_environment}/networking/public_subnet_ids"
}

# Parse JSON arrays from SSM
locals {
  private_subnet_ids = jsondecode(data.aws_ssm_parameter.private_subnet_ids.value)
  public_subnet_ids  = jsondecode(data.aws_ssm_parameter.public_subnet_ids.value)
}
