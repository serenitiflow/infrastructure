module "aurora" {
  source = "../../../modules/aurora"

  project_name             = var.project_name
  app                      = var.app
  environment              = var.environment
  aws_region               = var.aws_region
  db_username              = var.db_username
  aurora_instance_class    = var.aurora_instance_class
  aurora_min_capacity      = var.aurora_min_capacity
  aurora_max_capacity      = var.aurora_max_capacity
  aurora_scheduler_enabled = var.aurora_scheduler_enabled
  backup_retention_period  = var.backup_retention_period
  allowed_admin_cidrs      = var.allowed_admin_cidrs
}
