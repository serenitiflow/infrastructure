module "networking" {
  source = "../../../modules/networking"

  project_name        = var.project_name
  app                 = var.app
  environment         = var.environment
  aws_region          = var.aws_region
  nat_gateway_enabled = var.nat_gateway_enabled
  nat_instance_type   = var.nat_instance_type
}
