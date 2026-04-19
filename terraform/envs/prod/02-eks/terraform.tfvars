project_name              = "serenity"
app                       = "serenity"
environment               = "prod"
aws_region                = "us-east-1"
kubernetes_version        = "1.35"
# PROD: Use ON_DEMAND for stability (no Spot interruption risk)
capacity_type             = "ON_DEMAND"
# PROD: Consistent x86_64 architecture - do NOT mix ARM64 (t4g) and x86_64 (t3a/t3)
# The AMI type is determined by the first instance type, so mixing causes NodeCreationFailure
node_instance_types       = ["t3a.medium", "t3.medium"]
# PROD: Min 2 nodes for HA
node_desired_size         = 2
node_min_size             = 2
node_max_size             = 5
# PROD: 30-day retention for compliance
cloudwatch_retention_days = 30
# PROD: Enable all control plane logs for compliance
cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
# PROD: Public endpoint disabled for security; CIDRs irrelevant when disabled
cluster_endpoint_public_access = false
allowed_public_cidrs           = []
