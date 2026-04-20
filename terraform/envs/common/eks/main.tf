module "eks" {
  source = "../../../modules/eks"

  project_name                   = var.project_name
  app                            = var.app
  environment                    = var.environment
  aws_region                     = var.aws_region
  kubernetes_version             = var.kubernetes_version
  cluster_endpoint_public_access = var.cluster_endpoint_public_access
  allowed_public_cidrs           = var.allowed_public_cidrs
  capacity_type                  = var.capacity_type
  node_instance_types            = var.node_instance_types
  node_desired_size              = var.node_desired_size
  node_min_size                  = var.node_min_size
  node_max_size                  = var.node_max_size
  cloudwatch_retention_days      = var.cloudwatch_retention_days
  cluster_enabled_log_types      = var.cluster_enabled_log_types
  access_entries                 = var.access_entries
  networking_environment         = "dev"
}
