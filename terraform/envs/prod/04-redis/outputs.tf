output "redis_endpoint" {
  description = "Redis primary endpoint"
  value       = module.redis.redis_endpoint
}

output "redis_security_group_id" {
  description = "Redis security group ID"
  value       = module.redis.redis_security_group_id
}

output "redis_credentials_secret_arn" {
  description = "ARN of Redis credentials secret"
  value       = module.redis.redis_credentials_secret_arn
  sensitive   = true
}
