output "aurora_endpoint" {
  description = "Aurora cluster endpoint"
  value       = module.databases.aurora_endpoint
}

output "aurora_reader_endpoint" {
  description = "Aurora reader endpoint"
  value       = module.databases.aurora_reader_endpoint
}

output "aurora_security_group_id" {
  description = "Aurora security group ID"
  value       = module.databases.aurora_security_group_id
}

output "aurora_secret_arn" {
  description = "ARN of Secrets Manager secret containing Aurora credentials"
  value       = module.databases.aurora_secret_arn
  sensitive   = true
}

output "redis_endpoint" {
  description = "Redis primary endpoint"
  value       = module.databases.redis_endpoint
}

output "redis_security_group_id" {
  description = "Redis security group ID"
  value       = module.databases.redis_security_group_id
}

output "redis_credentials_secret_arn" {
  description = "ARN of Redis credentials secret"
  value       = module.databases.redis_credentials_secret_arn
  sensitive   = true
}
