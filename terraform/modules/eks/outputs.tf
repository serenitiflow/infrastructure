# Outputs for direct consumption
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
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

output "kubernetes_dashboard_token_command" {
  description = "Command to get Kubernetes Dashboard login token"
  value       = var.enable_kubernetes_dashboard ? "kubectl -n kubernetes-dashboard get secret admin-user-token -o jsonpath='{.data.token}' | base64 -d" : null
}

output "kubernetes_dashboard_portforward_command" {
  description = "Command to port-forward Kubernetes Dashboard to localhost"
  value       = var.enable_kubernetes_dashboard ? "kubectl -n kubernetes-dashboard port-forward svc/kubernetes-dashboard 8443:443" : null
}

