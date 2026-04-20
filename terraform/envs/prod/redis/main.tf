module "redis" {
  source = "../../../modules/redis"

  project_name             = var.project_name
  app                      = var.app
  environment              = var.environment
  aws_region               = var.aws_region
  redis_node_type          = var.redis_node_type
  snapshot_retention_limit = var.snapshot_retention_limit
  allowed_admin_cidrs      = var.allowed_admin_cidrs
}
