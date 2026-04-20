project_name = "serenity"
app          = "serenity"
environment  = "dev"
aws_region   = "eu-central-1"
db_username  = "postgres"
# COST OPTIMIZATION: Enable scheduler to stop Aurora at night (~$20-30/mo savings)
# Disable for 24/7 workloads
aurora_scheduler_enabled = true
# Dev: Minimum retention for cost savings
backup_retention_period = 1
# Admin access to databases from local machine
allowed_admin_cidrs = ["76.147.65.241/32"]
# Dev: Expose Aurora publicly for local access (security: restricted to allowed_admin_cidrs)
publicly_accessible = true
