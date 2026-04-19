# NAT Instance Module
# Cost: ~$3.50/month (t4g.nano) vs ~$32.40/month (NAT Gateway)
# Savings: ~$29/month for dev environments

data "aws_ssm_parameter" "ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-${startswith(var.instance_type, "t4g") || startswith(var.instance_type, "m6g") || startswith(var.instance_type, "c6g") || startswith(var.instance_type, "r6g") ? "arm64" : "x86_64"}"
}

locals {
  nat_user_data = <<-EOF
#!/bin/bash
set -e

# Install iptables-services first
yum install -y iptables-services

# Enable IP forwarding
sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf

# Configure NAT masquerade (do not specify interface - AL2023 uses ens5, not eth0)
iptables -t nat -A POSTROUTING -s ${var.private_cidr} -j MASQUERADE

# Save rules so they persist across reboots
iptables-save > /etc/sysconfig/iptables

# Enable and start iptables service
systemctl enable iptables
systemctl start iptables

EOF
}

# Security group for NAT Instance
resource "aws_security_group" "nat" {
  count = var.enabled ? 1 : 0

  name        = "${var.project_name}-${var.environment}-nat-instance"
  description = "Security group for NAT instance"
  vpc_id      = var.vpc_id

  # Allow all traffic from private subnets (NAT instance acts as a router)
  # Security boundary is the CIDR: only private subnet traffic can reach this
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = var.private_subnets_cidr
  }

  # Allow all outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-nat-instance"
  })
}

# IAM role for NAT instance (for SSM access, CloudWatch logs)
resource "aws_iam_role" "nat" {
  count = var.enabled ? 1 : 0

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

  tags = var.tags
}

resource "aws_iam_role_policy" "nat" {
  count = var.enabled ? 1 : 0

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
            "ec2:Vpc" = "arn:aws:ec2:*:*:vpc/${var.vpc_id}"
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
            "ec2:Vpc" = "arn:aws:ec2:*:*:vpc/${var.vpc_id}"
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
  count = var.enabled ? 1 : 0

  name = "${var.project_name}-${var.environment}-nat-profile"
  role = aws_iam_role.nat[0].name
}

# NAT Instance
resource "aws_instance" "nat" {
  count = var.enabled ? 1 : 0

  ami           = data.aws_ssm_parameter.ami.value
  instance_type = var.instance_type

  subnet_id                   = var.public_subnet_id
  vpc_security_group_ids      = [aws_security_group.nat[0].id]
  associate_public_ip_address = true
  source_dest_check           = false # Required for NAT

  iam_instance_profile = aws_iam_instance_profile.nat[0].name

  user_data = base64encode(local.nat_user_data)
  user_data_replace_on_change = true

  tags = merge(var.tags, {
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
  count = var.enabled ? 1 : 0

  instance = aws_instance.nat[0].id
  domain   = "vpc"

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-nat-eip"
  })
}

# Update route table to use NAT instance
resource "aws_route" "nat_route" {
  count = var.enabled ? length(var.private_route_table_ids) : 0

  route_table_id         = var.private_route_table_ids[count.index]
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.nat[0].primary_network_interface_id

  # Only create if NAT Gateway route doesn't exist
  lifecycle {
    create_before_destroy = true
  }
}

# CloudWatch alarm for NAT instance health check
resource "aws_cloudwatch_metric_alarm" "nat_cpu" {
  count = var.enabled ? 1 : 0

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

  tags = var.tags
}
