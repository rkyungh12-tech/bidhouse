resource "aws_sns_topic" "operations_alerts" {
  name = "${var.project_name}-${var.environment}-operations-alerts"

  tags = {
    Name    = "${var.project_name}-${var.environment}-operations-alerts"
    Purpose = "Operational alerts"
  }
}

resource "aws_sns_topic_subscription" "operations_email" {
  topic_arn = aws_sns_topic.operations_alerts.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}