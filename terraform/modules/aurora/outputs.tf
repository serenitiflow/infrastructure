output "aurora_endpoint" {
  description = "Aurora cluster endpoint"
  value       = module.aurora.cluster_endpoint
}

output "aurora_reader_endpoint" {
  description = "Aurora reader endpoint"
  value       = module.aurora.cluster_reader_endpoint
}

output "aurora_security_group_id" {
  description = "Aurora security group ID"
  value       = module.aurora.security_group_id
}

output "aurora_cluster_port" {
  description = "Aurora PostgreSQL cluster port"
  value       = module.aurora.cluster_port
}

output "aurora_database_name" {
  description = "Aurora PostgreSQL database name"
  value       = module.aurora.cluster_database_name
}

output "aurora_master_username" {
  description = "Aurora PostgreSQL master username"
  value       = module.aurora.cluster_master_username
}

output "aurora_secret_arn" {
  description = "ARN of Secrets Manager secret containing Aurora credentials"
  value       = aws_secretsmanager_secret.aurora_credentials.arn
  sensitive   = true
}

output "aurora_cluster_resource_id" {
  description = "Aurora cluster resource ID for IAM authentication"
  value       = module.aurora.cluster_resource_id
}

output "aurora_cluster_arn" {
  description = "Aurora cluster ARN"
  value       = module.aurora.cluster_arn
}
