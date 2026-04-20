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

output "redis_secret_kms_key_arn" {
  description = "ARN of KMS key used for Redis secrets"
  value       = aws_kms_key.secrets.arn
}
