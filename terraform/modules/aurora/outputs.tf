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
  value       = module.database_common.secret_arn
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

output "scheduler_lambda_function_arn" {
  description = "ARN of the Aurora scheduler Lambda function"
  value       = var.aurora_scheduler_enabled ? aws_lambda_function.aurora_scheduler[0].arn : null
}

output "scheduler_lambda_function_name" {
  description = "Name of the Aurora scheduler Lambda function"
  value       = var.aurora_scheduler_enabled ? aws_lambda_function.aurora_scheduler[0].function_name : null
}

output "scheduler_stop_schedule_rule" {
  description = "CloudWatch Event Rule for stopping Aurora"
  value       = var.aurora_scheduler_enabled ? aws_cloudwatch_event_rule.aurora_stop[0].name : null
}

output "scheduler_start_schedule_rule" {
  description = "CloudWatch Event Rule for starting Aurora"
  value       = var.aurora_scheduler_enabled ? aws_cloudwatch_event_rule.aurora_start[0].name : null
}
