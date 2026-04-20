output "kms_key_arn" {
  description = "ARN of the KMS key for secrets encryption"
  value       = aws_kms_key.this.arn
}

output "secret_arn" {
  description = "ARN of the Secrets Manager secret"
  value       = aws_secretsmanager_secret.this.arn
}

output "secret_id" {
  description = "ID of the Secrets Manager secret"
  value       = aws_secretsmanager_secret.this.id
}

output "password" {
  description = "Generated random password"
  value       = random_password.this.result
  sensitive   = true
}
