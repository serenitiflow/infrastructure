module "github_oidc" {
  source = "../../modules/github-oidc"

  project_name = var.project_name

  allowed_repositories = [
    "repo:serenitiflow/*",
  ]

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# Write role ARN to SSM for CI/CD reference
resource "aws_ssm_parameter" "github_actions_role_arn" {
  name  = "/${var.project_name}/shared/eks/github_actions_role_arn"
  type  = "String"
  value = module.github_oidc.github_actions_role_arn

  tags = {
    Name        = "${var.project_name}-github-actions-role-arn"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
