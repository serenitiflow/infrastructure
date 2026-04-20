# Read shared EKS OIDC issuer URL from SSM
data "aws_ssm_parameter" "oidc_issuer_url" {
  name = "/${var.project_name}/shared/eks/cluster_oidc_issuer_url"
}

# IRSA for dev namespace
module "irsa_dev" {
  source = "../../../modules/irsa"

  project_name    = var.project_name
  environment     = "dev"
  namespace       = "dev-serenity"
  oidc_issuer_url = data.aws_ssm_parameter.oidc_issuer_url.value
}

# IRSA for prod namespace
module "irsa_prod" {
  source = "../../../modules/irsa"

  project_name    = var.project_name
  environment     = "prod"
  namespace       = "prod-serenity"
  oidc_issuer_url = data.aws_ssm_parameter.oidc_issuer_url.value
}

# Write role ARNs to SSM for CI/CD and K8s manifest reference
resource "aws_ssm_parameter" "dev_irsa_role_arn" {
  name  = "/${var.project_name}/dev/eks/irsa_services_role_arn"
  type  = "String"
  value = module.irsa_dev.role_arn

  tags = {
    Name        = "${var.project_name}-dev-irsa-role-arn"
    Environment = "dev"
    Project     = var.project_name
    ManagedBy   = "terraform"
  }
}

resource "aws_ssm_parameter" "prod_irsa_role_arn" {
  name  = "/${var.project_name}/prod/eks/irsa_services_role_arn"
  type  = "String"
  value = module.irsa_prod.role_arn

  tags = {
    Name        = "${var.project_name}-prod-irsa-role-arn"
    Environment = "prod"
    Project     = var.project_name
    ManagedBy   = "terraform"
  }
}
