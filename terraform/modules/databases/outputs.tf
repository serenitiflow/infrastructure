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

output "redis_endpoint" {
  description = "Redis primary endpoint"
  value       = module.elasticache.replication_group_primary_endpoint_address
}

output "redis_security_group_id" {
  description = "Redis security group ID"
  value       = module.elasticache.security_group_id
}

output "redis_port" {
  description = "Redis port"
  value       = 6379
}

output "redis_connection_string" {
  description = "Redis connection string (redis://host:port)"
  value       = "redis://${module.elasticache.replication_group_primary_endpoint_address}:6379"
  sensitive   = true
}

output "redis_credentials_secret_arn" {
  description = "ARN of Redis credentials secret"
  value       = aws_secretsmanager_secret.redis_credentials.arn
  sensitive   = true
}

output "redis_cluster_id" {
  description = "ElastiCache Redis cluster ID"
  value       = module.elasticache.replication_group_id
}
