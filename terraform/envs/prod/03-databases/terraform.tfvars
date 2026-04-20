project_name             = "serenity"
app                      = "serenity"
environment              = "prod"
aws_region               = "eu-central-1"
db_username              = "postgres"
aurora_instance_class    = "db.serverless"
# PROD: Higher capacity for production workloads
aurora_min_capacity      = 1
aurora_max_capacity      = 8
# PROD: Larger Redis instance
redis_node_type          = "cache.t4g.small"
# PROD: Disable scheduler - databases must be 24/7
aurora_scheduler_enabled = false
# Prod: Longer retention for compliance
backup_retention_period  = 30
snapshot_retention_limit = 7
# Admin access to databases from local machine
allowed_admin_cidrs      = ["76.147.65.241/32"]
