module "common_tags" {
  source = "../common-tags"

  project_name = var.project_name
  app          = var.app
  environment  = var.environment
  stack        = "aurora"
}

locals {
  # Aurora cluster name for referencing in IAM policies
  aurora_cluster_name = "${var.project_name}-${var.environment}-aurora"
}

module "database_common" {
  source = "../database-common"

  alias_name  = "${var.project_name}-${var.environment}-secrets"
  secret_name = "${var.project_name}/${var.environment}/database/credentials"
  environment = var.environment
  service     = "Aurora"
  tags        = module.common_tags.tags
}

# Aurora Module
module "aurora" {
  source  = "terraform-aws-modules/rds-aurora/aws"
  version = "~> 9.0"

  name           = local.aurora_cluster_name
  engine         = "aurora-postgresql"
  engine_version = "16.4"
  engine_mode    = "provisioned"

  instance_class = var.aurora_instance_class

  serverlessv2_scaling_configuration = {
    min_capacity = var.aurora_min_capacity
    max_capacity = var.aurora_max_capacity
  }

  database_name   = "serenity"
  master_username = var.db_username
  master_password = module.database_common.password

  vpc_id               = data.aws_ssm_parameter.vpc_id.value
  db_subnet_group_name = data.aws_ssm_parameter.database_subnet_group_name.value

  create_security_group = true
  security_group_rules = {
    eks_ingress = {
      source_security_group_id = data.aws_ssm_parameter.cluster_security_group_id.value
      from_port                = 5432
      to_port                  = 5432
      description              = "PostgreSQL from EKS"
    }
    admin_ingress = {
      cidr_blocks = var.allowed_admin_cidrs
      from_port   = 5432
      to_port     = 5432
      description = "PostgreSQL from admin IPs"
    }
  }

  instances = {
    writer = {
      instance_class               = var.aurora_instance_class
      publicly_accessible          = false
      performance_insights_enabled = var.environment == "prod"
    }
  }

  backup_retention_period = var.backup_retention_period
  preferred_backup_window = "03:00-04:00"
  skip_final_snapshot     = var.environment != "prod"
  deletion_protection     = var.environment == "prod"

  storage_encrypted = true

  enabled_cloudwatch_logs_exports = var.environment == "prod" ? ["postgresql"] : []
  performance_insights_enabled    = var.environment == "prod"

  tags = module.common_tags.tags
}

# Aurora Scheduled Stop/Start
# Saves $20-30/month by stopping Aurora during off-hours

locals {
  lambda_payload = <<-EOF
const AWS = require('aws-sdk');
const rds = new AWS.RDS();

exports.handler = async (event) => {
  const action = event.action; // 'stop' or 'start'
  const clusterId = process.env.CLUSTER_ID;

  console.log(`$${action}ing Aurora cluster: $${clusterId}`);

  try {
    if (action === 'stop') {
      await rds.stopDBCluster({ DBClusterIdentifier: clusterId }).promise();
      console.log(`Successfully stopped cluster: $${clusterId}`);
    } else if (action === 'start') {
      await rds.startDBCluster({ DBClusterIdentifier: clusterId }).promise();
      console.log(`Successfully started cluster: $${clusterId}`);
    }
    return { statusCode: 200, body: JSON.stringify({ message: 'Success' }) };
  } catch (error) {
    console.error(`Error $${action}ing cluster:`, error);
    return { statusCode: 500, body: JSON.stringify({ error: error.message }) };
  }
};
EOF
}

# Lambda function for Aurora stop/start
data "archive_file" "aurora_scheduler" {
  count = var.aurora_scheduler_enabled ? 1 : 0

  type        = "zip"
  output_path = "${path.module}/aurora-scheduler.zip"

  source {
    content  = local.lambda_payload
    filename = "index.js"
  }
}

resource "aws_lambda_function" "aurora_scheduler" {
  count = var.aurora_scheduler_enabled ? 1 : 0

  filename         = data.archive_file.aurora_scheduler[0].output_path
  function_name    = "${var.project_name}-${var.environment}-aurora-scheduler"
  role             = aws_iam_role.lambda_role[0].arn
  handler          = "index.handler"
  runtime          = "nodejs18.x"
  timeout          = 60
  source_code_hash = data.archive_file.aurora_scheduler[0].output_base64sha256

  environment {
    variables = {
      CLUSTER_ID = module.aurora.cluster_id
    }
  }

  tags = merge(module.common_tags.tags, {
    Name = "${var.project_name}-${var.environment}-aurora-scheduler"
  })
}

# IAM role for Lambda
resource "aws_iam_role" "lambda_role" {
  count = var.aurora_scheduler_enabled ? 1 : 0

  name = "${var.project_name}-${var.environment}-aurora-scheduler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = module.common_tags.tags
}

# IAM policy for RDS access
resource "aws_iam_role_policy" "lambda_rds_policy" {
  count = var.aurora_scheduler_enabled ? 1 : 0

  name = "${var.project_name}-${var.environment}-aurora-scheduler-policy"
  role = aws_iam_role.lambda_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "rds:StartDBCluster",
          "rds:StopDBCluster",
          "rds:DescribeDBClusters"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# CloudWatch Event Rule for stopping Aurora (7 PM daily)
resource "aws_cloudwatch_event_rule" "aurora_stop" {
  count = var.aurora_scheduler_enabled ? 1 : 0

  name                = "${var.project_name}-${var.environment}-aurora-stop"
  description         = "Stop Aurora cluster during off-hours (7 PM daily)"
  schedule_expression = "cron(0 19 * * ? *)" # 7 PM UTC daily
  state               = var.aurora_scheduler_enabled ? "ENABLED" : "DISABLED"

  tags = module.common_tags.tags
}

resource "aws_cloudwatch_event_target" "stop_target" {
  count = var.aurora_scheduler_enabled ? 1 : 0

  rule      = aws_cloudwatch_event_rule.aurora_stop[0].name
  target_id = "StopAurora"
  arn       = aws_lambda_function.aurora_scheduler[0].arn

  input = jsonencode({
    action = "stop"
  })
}

# CloudWatch Event Rule for starting Aurora (8 AM daily)
resource "aws_cloudwatch_event_rule" "aurora_start" {
  count = var.aurora_scheduler_enabled ? 1 : 0

  name                = "${var.project_name}-${var.environment}-aurora-start"
  description         = "Start Aurora cluster for business hours (8 AM daily)"
  schedule_expression = "cron(0 8 * * ? *)" # 8 AM UTC daily
  state               = var.aurora_scheduler_enabled ? "ENABLED" : "DISABLED"

  tags = module.common_tags.tags
}

resource "aws_cloudwatch_event_target" "start_target" {
  count = var.aurora_scheduler_enabled ? 1 : 0

  rule      = aws_cloudwatch_event_rule.aurora_start[0].name
  target_id = "StartAurora"
  arn       = aws_lambda_function.aurora_scheduler[0].arn

  input = jsonencode({
    action = "start"
  })
}

# Lambda permissions for CloudWatch Events
resource "aws_lambda_permission" "allow_cloudwatch_stop" {
  count = var.aurora_scheduler_enabled ? 1 : 0

  statement_id  = "AllowExecutionFromCloudWatchStop"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.aurora_scheduler[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.aurora_stop[0].arn
}

resource "aws_lambda_permission" "allow_cloudwatch_start" {
  count = var.aurora_scheduler_enabled ? 1 : 0

  statement_id  = "AllowExecutionFromCloudWatchStart"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.aurora_scheduler[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.aurora_start[0].arn
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "aurora_scheduler" {
  count = var.aurora_scheduler_enabled ? 1 : 0

  name              = "/aws/lambda/${aws_lambda_function.aurora_scheduler[0].function_name}"
  retention_in_days = 7

  tags = module.common_tags.tags
}

# Secrets Manager version (secret created by database-common module)
resource "aws_secretsmanager_secret_version" "aurora_credentials" {
  secret_id = module.database_common.secret_id
  secret_string = jsonencode({
    username        = var.db_username
    password        = module.database_common.password
    host            = module.aurora.cluster_endpoint
    port            = 5432
    dbname          = "serenity"
    reader_endpoint = module.aurora.cluster_reader_endpoint
    jdbc_url        = "jdbc:postgresql://${module.aurora.cluster_endpoint}:5432/serenity"
  })
}

# SSM Parameters for application stacks
module "ssm_parameters" {
  source = "../ssm-parameters"

  tags = module.common_tags.tags

  parameters = {
    "/${var.project_name}/${var.environment}/database/host" = {
      value = module.aurora.cluster_endpoint
    }
    "/${var.project_name}/${var.environment}/database/reader_endpoint" = {
      value = module.aurora.cluster_reader_endpoint
    }
    "/${var.project_name}/${var.environment}/database/port" = {
      value = "5432"
    }
    "/${var.project_name}/${var.environment}/database/name" = {
      value = "serenity"
    }
    "/${var.project_name}/${var.environment}/database/secret_arn" = {
      value = module.database_common.secret_arn
    }
  }
}
