module "common_tags" {
  source = "../common-tags"

  project_name = var.project_name
  app          = var.app
  environment  = var.environment
  stack        = "networking"
}

# VPC Module
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.project_name}-${var.environment}"
  cidr = var.vpc_cidr

  azs              = ["${var.aws_region}a", "${var.aws_region}b"]
  private_subnets  = [cidrsubnet(var.vpc_cidr, 8, 1), cidrsubnet(var.vpc_cidr, 8, 2)]
  public_subnets   = [cidrsubnet(var.vpc_cidr, 8, 101), cidrsubnet(var.vpc_cidr, 8, 102)]
  database_subnets = [
    cidrsubnet(var.vpc_cidr, 8, 201), # dev-db-az1
    cidrsubnet(var.vpc_cidr, 8, 202), # dev-db-az2
    cidrsubnet(var.vpc_cidr, 8, 211), # prod-db-az1
    cidrsubnet(var.vpc_cidr, 8, 212), # prod-db-az2
  ]

  enable_nat_gateway     = var.nat_gateway_enabled
  single_nat_gateway     = var.environment != "prod"
  one_nat_gateway_per_az = var.environment == "prod"

  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnet_tags = {
    Type                       = "public"
    "kubernetes.io/role/elb"   = "1"
  }

  private_subnet_tags = {
    Type                              = "private"
    "kubernetes.io/role/internal-elb" = "1"
  }

  database_subnet_tags = {
    Type             = "database"
    "subnet-purpose" = "database"
  }

  tags = module.common_tags.tags
}

resource "aws_db_subnet_group" "dev" {
  name       = "${var.project_name}-dev-db-subnet-group"
  subnet_ids = [module.vpc.database_subnets[0], module.vpc.database_subnets[1]]
  tags = merge(module.common_tags.tags, {
    Environment = "dev"
    Name        = "${var.project_name}-dev-db-subnet-group"
  })
}

resource "aws_db_subnet_group" "prod" {
  name       = "${var.project_name}-prod-db-subnet-group"
  subnet_ids = [module.vpc.database_subnets[2], module.vpc.database_subnets[3]]
  tags = merge(module.common_tags.tags, {
    Environment = "prod"
    Name        = "${var.project_name}-prod-db-subnet-group"
  })
}

# NAT Instance resources (inlined from nat-instance module)
# Cost: ~$3.50/month (t4g.nano) vs ~$32.40/month (NAT Gateway)
# Savings: ~$29/month for dev environments

data "aws_ssm_parameter" "ami" {
  count = !var.nat_gateway_enabled ? 1 : 0

  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-${startswith(var.nat_instance_type, "t4g") || startswith(var.nat_instance_type, "m6g") || startswith(var.nat_instance_type, "c6g") || startswith(var.nat_instance_type, "r6g") ? "arm64" : "x86_64"}"
}

locals {
  nat_user_data_raw = <<-EOF
#!/bin/bash
set -e

# Install iptables-services first
yum install -y iptables-services

# Enable IP forwarding
sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf

# Configure NAT masquerade (do not specify interface - AL2023 uses ens5, not eth0)
iptables -t nat -A POSTROUTING -s ${var.vpc_cidr} -j MASQUERADE

# Save rules so they persist across reboots
iptables-save > /etc/sysconfig/iptables

# Enable and start iptables service
systemctl enable iptables
systemctl start iptables
EOF

  nat_user_data = var.nat_gateway_enabled ? "" : local.nat_user_data_raw
}

# Security group for NAT Instance
resource "aws_security_group" "nat" {
  count = !var.nat_gateway_enabled ? 1 : 0

  name        = "${var.project_name}-${var.environment}-nat-instance"
  description = "Security group for NAT instance"
  vpc_id      = module.vpc.vpc_id

  # Allow all traffic from private subnets (NAT instance acts as a router)
  # Security boundary is the CIDR: only private subnet traffic can reach this
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = module.vpc.private_subnets_cidr_blocks
  }

  # Allow all outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(module.common_tags.tags, {
    Name = "${var.project_name}-${var.environment}-nat-instance"
  })
}

# IAM role for NAT instance (for SSM access, CloudWatch logs)
resource "aws_iam_role" "nat" {
  count = !var.nat_gateway_enabled ? 1 : 0

  name = "${var.project_name}-${var.environment}-nat-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = module.common_tags.tags
}

resource "aws_iam_role_policy" "nat" {
  count = !var.nat_gateway_enabled ? 1 : 0

  name = "${var.project_name}-${var.environment}-nat-policy"
  role = aws_iam_role.nat[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowRouteModificationsInVPC"
        Effect = "Allow"
        Action = [
          "ec2:CreateRoute",
          "ec2:ReplaceRoute",
          "ec2:DeleteRoute"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "ec2:Vpc" = "arn:aws:ec2:*:*:vpc/${module.vpc.vpc_id}"
          }
        }
      },
      {
        Sid    = "AllowDescribeResources"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeRouteTables",
          "ec2:DescribeNetworkInterfaces"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "ec2:Vpc" = "arn:aws:ec2:*:*:vpc/${module.vpc.vpc_id}"
          }
        }
      },
      {
        Sid    = "AllowCloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:*:*:log-group:/${var.project_name}/${var.environment}/nat-instance:*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "nat" {
  count = !var.nat_gateway_enabled ? 1 : 0

  name = "${var.project_name}-${var.environment}-nat-profile"
  role = aws_iam_role.nat[0].name
}

# NAT Instance
resource "aws_instance" "nat" {
  count = !var.nat_gateway_enabled ? 1 : 0

  ami           = data.aws_ssm_parameter.ami[0].value
  instance_type = var.nat_instance_type

  subnet_id                   = module.vpc.public_subnets[0]
  vpc_security_group_ids      = [aws_security_group.nat[0].id]
  associate_public_ip_address = true
  source_dest_check           = false # Required for NAT

  iam_instance_profile = aws_iam_instance_profile.nat[0].name

  user_data = base64encode(local.nat_user_data)
  user_data_replace_on_change = true

  tags = merge(module.common_tags.tags, {
    Name = "${var.project_name}-${var.environment}-nat-instance"
    AutoShutdown = "true"
    ShutdownSchedule = "0 19 * * 1-5"
  })

  root_block_device {
    volume_size           = 8
    volume_type           = "gp3"
    delete_on_termination = true
  }
}

# Elastic IP for NAT instance
resource "aws_eip" "nat" {
  count = !var.nat_gateway_enabled ? 1 : 0

  instance = aws_instance.nat[0].id
  domain   = "vpc"

  tags = merge(module.common_tags.tags, {
    Name = "${var.project_name}-${var.environment}-nat-eip"
  })
}

# Update route table to use NAT instance
resource "aws_route" "nat_route" {
  count = !var.nat_gateway_enabled ? length(module.vpc.private_route_table_ids) : 0

  route_table_id         = module.vpc.private_route_table_ids[count.index]
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.nat[0].primary_network_interface_id

  # Only create if NAT Gateway route doesn't exist
  lifecycle {
    create_before_destroy = true
  }
}

# CloudWatch alarm for NAT instance health check
resource "aws_cloudwatch_metric_alarm" "nat_cpu" {
  count = !var.nat_gateway_enabled ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-nat-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 5
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 90
  alarm_description   = "Alarm when NAT instance CPU is high"

  dimensions = {
    InstanceId = aws_instance.nat[0].id
  }

  tags = module.common_tags.tags
}

# SSM Parameters for cross-stack communication (decoupled approach)
module "ssm_parameters" {
  source = "../ssm-parameters"

  tags = module.common_tags.tags

  parameters = {
    "/${var.project_name}/shared/networking/vpc_id" = {
      value = module.vpc.vpc_id
    }
    "/${var.project_name}/shared/networking/vpc_cidr" = {
      value = module.vpc.vpc_cidr_block
    }
    "/${var.project_name}/shared/networking/private_subnet_ids" = {
      value = jsonencode(module.vpc.private_subnets)
    }
    "/${var.project_name}/shared/networking/public_subnet_ids" = {
      value = jsonencode(module.vpc.public_subnets)
    }
    "/${var.project_name}/shared/networking/private_route_table_ids" = {
      value = jsonencode(module.vpc.private_route_table_ids)
    }
    "/${var.project_name}/shared/networking/public_route_table_ids" = {
      value = jsonencode(module.vpc.public_route_table_ids)
    }
    "/${var.project_name}/shared/networking/database_route_table_ids" = {
      value = jsonencode(module.vpc.database_route_table_ids)
    }
    "/${var.project_name}/shared/networking/nat_gateway_id" = {
      value = var.nat_gateway_enabled ? module.vpc.nat_gateway_ids[0] : "disabled"
    }
    "/${var.project_name}/shared/networking/nat_instance_id" = {
      value = !var.nat_gateway_enabled ? aws_instance.nat[0].id : "disabled"
    }
    "/${var.project_name}/dev/networking/database_subnet_ids" = {
      value = jsonencode([module.vpc.database_subnets[0], module.vpc.database_subnets[1]])
    }
    "/${var.project_name}/dev/networking/database_subnet_group_name" = {
      value = aws_db_subnet_group.dev.name
    }
    "/${var.project_name}/prod/networking/database_subnet_ids" = {
      value = jsonencode([module.vpc.database_subnets[2], module.vpc.database_subnets[3]])
    }
    "/${var.project_name}/prod/networking/database_subnet_group_name" = {
      value = aws_db_subnet_group.prod.name
    }
  }
}
