output "lambda_function_arn" {
  description = "ARN of the Aurora scheduler Lambda function"
  value       = aws_lambda_function.aurora_scheduler.arn
}

output "lambda_function_name" {
  description = "Name of the Aurora scheduler Lambda function"
  value       = aws_lambda_function.aurora_scheduler.function_name
}

output "stop_schedule_rule" {
  description = "CloudWatch Event Rule for stopping Aurora"
  value       = aws_cloudwatch_event_rule.aurora_stop.name
}

output "start_schedule_rule" {
  description = "CloudWatch Event Rule for starting Aurora"
  value       = aws_cloudwatch_event_rule.aurora_start.name
}
