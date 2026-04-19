output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "EKS cluster security group ID"
  value       = module.eks.cluster_security_group_id
}

output "cluster_oidc_issuer_url" {
  description = "EKS OIDC issuer URL"
  value       = module.eks.cluster_oidc_issuer_url
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN for IAM Roles for Service Accounts"
  value       = module.eks.oidc_provider_arn
}

output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = module.eks.configure_kubectl
}

output "kubernetes_dashboard_token_command" {
  description = "Command to get Kubernetes Dashboard login token"
  value       = module.eks.kubernetes_dashboard_token_command
}

output "kubernetes_dashboard_portforward_command" {
  description = "Command to port-forward Kubernetes Dashboard to localhost"
  value       = module.eks.kubernetes_dashboard_portforward_command
}
