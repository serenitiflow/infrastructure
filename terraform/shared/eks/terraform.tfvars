project_name              = "serenity"
app                       = "serenity"
environment               = "shared"
aws_region                = "eu-central-1"
kubernetes_version        = "1.35"
capacity_type             = "SPOT"
node_instance_types       = ["t3a.medium", "t3.medium"]
node_desired_size         = 1
node_min_size             = 1
node_max_size             = 2
cloudwatch_retention_days = 1
# Dev: Disable CloudWatch control plane logs to minimize cost
cluster_enabled_log_types = []
# Dev: Public endpoint enabled for local kubectl / Lens access
# SECURITY: Replace with your public IP (https://checkip.amazonaws.com/)
cluster_endpoint_public_access = true
allowed_public_cidrs           = ["0.0.0.0/0"]

# Dev-only deployment: disable prod IRSA until prod is ready
create_prod_irsa = false

# Access Entries - add IAM roles/users that need kubectl / Lens / AWS Console access
# Required for anyone other than the cluster creator to connect
# SECURITY: Replace with your specific IAM role/user; root is used here for initial setup only
access_entries = {
  root-admin = {
    principal_arn = "arn:aws:iam::692046683886:root"
    type          = "STANDARD"
    policy_associations = {
      admin = {
        policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
        access_scope = {
          type = "cluster"
        }
      }
    }
  }

  github-actions = {
    principal_arn = "arn:aws:iam::692046683886:role/serenity-github-actions-role"
    type          = "STANDARD"
    policy_associations = {
      admin = {
        policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
        access_scope = {
          type = "cluster"
        }
      }
    }
  }
}
