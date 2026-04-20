output "aurora_endpoint" {
  description = "Aurora cluster endpoint"
  value       = module.aurora.aurora_endpoint
}

output "aurora_reader_endpoint" {
  description = "Aurora reader endpoint"
  value       = module.aurora.aurora_reader_endpoint
}

output "aurora_security_group_id" {
  description = "Aurora security group ID"
  value       = module.aurora.aurora_security_group_id
}

output "aurora_secret_arn" {
  description = "ARN of Secrets Manager secret containing Aurora credentials"
  value       = module.aurora.aurora_secret_arn
  sensitive   = true
}
