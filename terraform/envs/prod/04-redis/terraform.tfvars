project_name             = "serenity"
app                      = "serenity"
environment              = "prod"
aws_region               = "eu-central-1"
# PROD: Larger Redis instance
redis_node_type          = "cache.t4g.small"
# Prod: Longer retention for compliance
snapshot_retention_limit = 7
# Admin access to Redis from local machine
allowed_admin_cidrs      = ["76.147.65.241/32"]
