# ============================================================================
# Failback 자동화 — 서울 복구 시 Azure MySQL → RDS 역동기화 + 복제 재연결
# 04-aws-seoul-app-foundation/failback.tf
# ============================================================================


# ── IAM Role ────────────────────────────────────────────────────────────────
resource "aws_iam_role" "lambda_failback" {
  name = "bidhouse-failback-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_failback_policy" {
  role = aws_iam_role.lambda_failback.id
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
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject"
        ]
        Resource = "arn:aws:s3:::${var.s3_images_bucket_name}/*"
      }
    ]
  })
}

# ── Lambda 패키징 (Terraform이 직접 zip 생성 — 스테이지 무관하게 항상 존재) ──
data "archive_file" "failback_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../failback_lambda"
  output_path = "${path.module}/failback_lambda.zip"
}

# ── Lambda 함수 ─────────────────────────────────────────────────────────────
resource "aws_lambda_function" "failback_sync" {
  filename         = data.archive_file.failback_zip.output_path
  source_code_hash = data.archive_file.failback_zip.output_base64sha256
  function_name    = "bidhouse-failback-sync"
  role             = aws_iam_role.lambda_failback.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  timeout          = 300

  vpc_config {
    subnet_ids         = var.lambda_subnet_ids
    security_group_ids = var.lambda_security_group_ids
  }

  environment {
    variables = {
      RDS_HOST                = var.rds_host
      RDS_USER                = var.rds_user
      RDS_PASS                = var.rds_pass
      AZ_MYSQL_HOST            = var.az_mysql_host
      AZ_MYSQL_USER            = var.az_mysql_user
      AZ_MYSQL_PASS            = var.az_mysql_pass
      REPL_PASS                = var.repl_pass
      AZ_STORAGE_ACCOUNT_NAME  = var.az_storage_account_name
      AZ_STORAGE_ACCOUNT_KEY   = var.az_storage_account_key
      S3_IMAGES_BUCKET         = var.s3_images_bucket_name
    }
  }

  tags = {
    Name    = "bidhouse-failback-sync"
    Project = "bidhouse"
  }
}

# Lambda가 SNS에서 호출될 수 있도록 권한 부여
resource "aws_lambda_permission" "allow_sns_failback" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.failback_sync.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.failback_trigger.arn
  depends_on    = [aws_lambda_function.failback_sync]
}

# ── SNS Topic (복구 트리거 전용) ─────────────────────────────────────────────
resource "aws_sns_topic" "failback_trigger" {
  provider = aws.us_east_1
  name     = "bidhouse-failback-trigger"
  tags = {
    Name    = "bidhouse-failback-trigger"
    Project = "bidhouse"
  }
}

resource "aws_sns_topic_subscription" "failback_lambda" {
  provider  = aws.us_east_1
  topic_arn = aws_sns_topic.failback_trigger.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.failback_sync.arn
}

# ── CloudWatch Alarm — 서울 Route53 헬스체크 복구 감지 ──────────────────────
# HealthCheckStatus: 1 = 정상, 0 = 장애
# 장애 → 복구 시 (0→1) Alarm이 ALARM 상태로 전환되면서 alarm_actions 실행
resource "aws_cloudwatch_metric_alarm" "seoul_recovered" {
  provider            = aws.us_east_1
  count = var.primary_health_check_id != "" ? 1 : 0
  alarm_name          = "bidhouse-seoul-primary-recovered"
  alarm_description   = "Seoul PRIMARY recovered - trigger failback Lambda"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = 30
  statistic           = "Minimum"
  threshold           = 1

  dimensions = {
    HealthCheckId = var.primary_health_check_id
  }

  # 복구(OK) 시 SNS → Lambda 실행
  alarm_actions = [aws_sns_topic.failback_trigger.arn]

  tags = {
    Name    = "bidhouse-seoul-recovered"
    Project = "bidhouse"
  }
}

# ── Outputs ─────────────────────────────────────────────────────────────────
output "failback_lambda_arn" {
  value = aws_lambda_function.failback_sync.arn
}

output "failback_sns_topic_arn" {
  value = aws_sns_topic.failback_trigger.arn
}
