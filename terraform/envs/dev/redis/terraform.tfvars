project_name             = "serenity"
app                      = "serenity"
environment              = "dev"
aws_region               = "eu-central-1"
redis_node_type          = "cache.t4g.micro"
# Dev: Minimum retention for cost savings
snapshot_retention_limit = 1
# Admin access to Redis from local machine
allowed_admin_cidrs      = ["76.147.65.241/32"]
