resource "aws_sns_topic" "operations_alerts" {
  name = "${var.project_name}-${var.environment}-operations-alerts"

  tags = {
    Name    = "${var.project_name}-${var.environment}-operations-alerts"
    Purpose = "Operational alerts"
  }
}

# 기존 이메일 구독 (필요 없으면 삭제해도 됩니다)
resource "aws_sns_topic_subscription" "operations_email" {
  topic_arn = aws_sns_topic.operations_alerts.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# 🚀 람다 구독 추가 (중요: topic_arn을 위 토픽으로 연결!)
resource "aws_sns_topic_subscription" "email_lambda_target" {
  topic_arn = aws_sns_topic.operations_alerts.arn  # <--- 이름 수정 완료
  protocol  = "lambda"
  endpoint  = aws_lambda_function.email_notifier.arn
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../01-aws-seoul-network/index.js"
  output_path = "${path.module}/lambda_email.zip"
}

resource "aws_iam_role" "lambda_sns_ses" {
  name = "bidhouse-email-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  role = aws_iam_role.lambda_sns_ses.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ses:SendEmail", "logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "*"
    }]
  })
}

resource "aws_lambda_function" "email_notifier" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "bidhouse-email-notifier"
  role             = aws_iam_role.lambda_sns_ses.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
}

resource "aws_lambda_permission" "allow_sns" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.email_notifier.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.operations_alerts.arn
}