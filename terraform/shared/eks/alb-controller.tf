# ---------------------------------------------------------------------------
# AWS Load Balancer Controller
# ---------------------------------------------------------------------------
# Provides ALB/NLB provisioning for Kubernetes Ingress/Service resources.
# Required for alb.ingress.kubernetes.io/* annotations to work.

# Fetch the official AWS Load Balancer Controller IAM policy
data "http" "alb_iam_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.2/docs/install/iam_policy.json"
}

resource "aws_iam_policy" "alb_controller" {
  name   = "${var.project_name}-alb-controller-policy"
  policy = data.http.alb_iam_policy.response_body

  tags = {
    Name        = "${var.project_name}-alb-controller-policy"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# Supplementary policy for permissions missing in v2.7.2 policy JSON
resource "aws_iam_policy" "alb_controller_supplement" {
  name   = "${var.project_name}-alb-controller-supp"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:GetSecurityGroupsForVpc"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-alb-controller-supp"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# IRSA role for ALB Controller
module "alb_controller_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.project_name}-alb-controller-role"

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }

  role_policy_arns = {
    alb  = aws_iam_policy.alb_controller.arn
    supp = aws_iam_policy.alb_controller_supplement.arn
  }

  tags = {
    Name        = "${var.project_name}-alb-controller-role"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# Service account for ALB Controller
resource "kubernetes_service_account_v1" "alb_controller" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = module.alb_controller_irsa.iam_role_arn
    }
    labels = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# VPC ID for Helm chart values
data "aws_ssm_parameter" "vpc_id" {
  name = "/${var.project_name}/shared/networking/vpc_id"
}

# Helm release for AWS Load Balancer Controller
resource "helm_release" "alb_controller" {
  depends_on = [kubernetes_service_account_v1.alb_controller]

  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version = "1.8.2"

  set = [
    {
      name  = "clusterName"
      value = module.eks.cluster_name
    },
    {
      name  = "serviceAccount.create"
      value = "false"
    },
    {
      name  = "serviceAccount.name"
      value = "aws-load-balancer-controller"
    },
    {
      name  = "region"
      value = var.aws_region
    },
    {
      name  = "vpcId"
      value = data.aws_ssm_parameter.vpc_id.value
    },
  ]
}
