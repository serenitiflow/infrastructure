# Aurora Scheduled Stop/Start Module
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
  type        = "zip"
  output_path = "${path.module}/aurora-scheduler.zip"

  source {
    content  = local.lambda_payload
    filename = "index.js"
  }
}

resource "aws_lambda_function" "aurora_scheduler" {
  filename         = data.archive_file.aurora_scheduler.output_path
  function_name    = "${var.project_name}-${var.environment}-aurora-scheduler"
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.handler"
  runtime          = "nodejs18.x"
  timeout          = 60
  source_code_hash = data.archive_file.aurora_scheduler.output_base64sha256

  environment {
    variables = {
      CLUSTER_ID = var.cluster_id
    }
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-aurora-scheduler"
  })
}

# IAM role for Lambda
resource "aws_iam_role" "lambda_role" {
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

  tags = var.tags
}

# IAM policy for RDS access
resource "aws_iam_role_policy" "lambda_rds_policy" {
  name = "${var.project_name}-${var.environment}-aurora-scheduler-policy"
  role = aws_iam_role.lambda_role.id

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
  name                = "${var.project_name}-${var.environment}-aurora-stop"
  description         = "Stop Aurora cluster during off-hours (7 PM daily)"
  schedule_expression = "cron(0 19 * * ? *)" # 7 PM UTC daily
  state               = var.schedule_enabled ? "ENABLED" : "DISABLED"

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "stop_target" {
  rule      = aws_cloudwatch_event_rule.aurora_stop.name
  target_id = "StopAurora"
  arn       = aws_lambda_function.aurora_scheduler.arn

  input = jsonencode({
    action = "stop"
  })
}

# CloudWatch Event Rule for starting Aurora (8 AM daily)
resource "aws_cloudwatch_event_rule" "aurora_start" {
  name                = "${var.project_name}-${var.environment}-aurora-start"
  description         = "Start Aurora cluster for business hours (8 AM daily)"
  schedule_expression = "cron(0 8 * * ? *)" # 8 AM UTC daily
  state               = var.schedule_enabled ? "ENABLED" : "DISABLED"

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "start_target" {
  rule      = aws_cloudwatch_event_rule.aurora_start.name
  target_id = "StartAurora"
  arn       = aws_lambda_function.aurora_scheduler.arn

  input = jsonencode({
    action = "start"
  })
}

# Lambda permissions for CloudWatch Events
resource "aws_lambda_permission" "allow_cloudwatch_stop" {
  statement_id  = "AllowExecutionFromCloudWatchStop"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.aurora_scheduler.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.aurora_stop.arn
}

resource "aws_lambda_permission" "allow_cloudwatch_start" {
  statement_id  = "AllowExecutionFromCloudWatchStart"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.aurora_scheduler.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.aurora_start.arn
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "aurora_scheduler" {
  name              = "/aws/lambda/${aws_lambda_function.aurora_scheduler.function_name}"
  retention_in_days = 7

  tags = var.tags
}
