# ============================================================================
# Failover 승격 자동화 — 서울 장애 시 Azure MySQL을 Master로 승격
# 04-aws-seoul-app-foundation/promote.tf
# ============================================================================

# ── IAM Role ────────────────────────────────────────────────────────────────
resource "aws_iam_role" "lambda_promote" {
  name = "bidhouse-promote-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_promote_policy" {
  role = aws_iam_role.lambda_promote.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = "arn:aws:secretsmanager:ap-northeast-2:*:secret:bidhouse-*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface"
        ]
        Resource = "*"
      }
    ]
  })
}

# ── Lambda 함수 ─────────────────────────────────────────────────────────────
# ── Lambda 패키징 (Terraform이 직접 zip 생성 — 스테이지 무관하게 항상 존재) ──
data "archive_file" "promote_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../promote_lambda"
  output_path = "${path.module}/promote_lambda.zip"
}

# ── Lambda 함수 ─────────────────────────────────────────────────────────────
resource "aws_lambda_function" "promote_singapore" {
  filename         = data.archive_file.promote_zip.output_path
  source_code_hash = data.archive_file.promote_zip.output_base64sha256
  function_name    = "bidhouse-singapore-promote"
  role             = aws_iam_role.lambda_promote.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  timeout          = 120

  vpc_config {
    subnet_ids         = var.lambda_subnet_ids
    security_group_ids = var.lambda_security_group_ids
  }

  environment {
    variables = {
      AZ_MYSQL_HOST = var.az_mysql_host
      AZ_MYSQL_USER = var.az_mysql_user
      AZ_MYSQL_PASS = var.az_mysql_pass
    }
  }

  tags = {
    Name    = "bidhouse-singapore-promote"
    Project = "bidhouse"
  }
}

resource "aws_lambda_permission" "allow_sns_promote" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.promote_singapore.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.promote_trigger.arn
  depends_on    = [aws_lambda_function.promote_singapore]
}

# ── SNS Topic (승격 트리거 전용) ─────────────────────────────────────────────
resource "aws_sns_topic" "promote_trigger" {
  provider = aws.us_east_1
  name     = "bidhouse-promote-trigger"
  tags = {
    Name    = "bidhouse-promote-trigger"
    Project = "bidhouse"
  }
}

resource "aws_sns_topic_subscription" "promote_lambda" {
  provider  = aws.us_east_1
  topic_arn = aws_sns_topic.promote_trigger.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.promote_singapore.arn
}

# ── CloudWatch Alarm — 서울 Route53 헬스체크 장애 감지 ──────────────────────
# HealthCheckStatus: 1 = 정상, 0 = 장애
# 정상 → 장애 전환 시 (1→0) Alarm이 ALARM 상태로 전환되면서 alarm_actions 실행
resource "aws_cloudwatch_metric_alarm" "seoul_failed" {
  provider            = aws.us_east_1
  count               = var.primary_health_check_id != "" ? 1 : 0
  alarm_name          = "bidhouse-seoul-primary-failed"
  alarm_description   = "Seoul PRIMARY failed - trigger Azure MySQL promotion"
  comparison_operator = "LessThanThreshold"
  evaluation_periods   = 2
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = 30
  statistic           = "Minimum"
  threshold           = 1

  dimensions = {
    HealthCheckId = var.primary_health_check_id
  }

  # 장애(ALARM) 시 SNS → Lambda 실행
  alarm_actions = [aws_sns_topic.promote_trigger.arn]

  tags = {
    Name    = "bidhouse-seoul-failed"
    Project = "bidhouse"
  }
}

# ── Outputs ─────────────────────────────────────────────────────────────────
output "promote_lambda_arn" {
  value = aws_lambda_function.promote_singapore.arn
}

output "promote_sns_topic_arn" {
  value = aws_sns_topic.promote_trigger.arn
}