# Read networking and EKS outputs from SSM Parameter Store
# Decoupled approach - stacks can be destroyed/recreated independently

# Get current AWS account ID
data "aws_caller_identity" "current" {}

# Networking parameters
data "aws_ssm_parameter" "vpc_id" {
  name = "/${var.project_name}/${var.environment}/networking/vpc_id"
}

data "aws_ssm_parameter" "database_subnet_group_name" {
  name = "/${var.project_name}/${var.environment}/networking/database_subnet_group_name"
}

# EKS parameters - shared cluster
data "aws_ssm_parameter" "cluster_security_group_id" {
  name = "/${var.project_name}/shared/eks/cluster_security_group_id"
}
