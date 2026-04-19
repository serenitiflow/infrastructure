project_name              = "serenity"
app                       = "serenity"
environment               = "dev"
aws_region                = "us-east-1"
kubernetes_version        = "1.35"
capacity_type             = "SPOT"
node_instance_types       = ["t3a.medium", "t3.medium"]
node_desired_size         = 1
node_min_size             = 1
node_max_size             = 2
cloudwatch_retention_days = 1
# Dev: Disable CloudWatch control plane logs to minimize cost
cluster_enabled_log_types = []
# Dev: Public endpoint enabled for local kubectl access
# SECURITY: Restrict to your office IP in production
cluster_endpoint_public_access = true
allowed_public_cidrs           = ["0.0.0.0/0"]
enable_kubernetes_dashboard    = true

# Access Entries - add IAM roles/users that need kubectl access
# Example:
# access_entries = {
#   admin-role = {
#     principal_arn = "arn:aws:iam::123456789012:role/YourSSOAdminRole"
#     type          = "STANDARD"
#     policy_associations = {
#       admin = {
#         policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
#         access_scope = {
#           type = "cluster"
#         }
#       }
#     }
#   }
# }
