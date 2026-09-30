resource "aws_cloudwatch_log_group" "auction_app" {
  name              = "/ecs/${var.project_name}-${var.environment}"
  retention_in_days = var.log_retention_days

  tags = {
    Name    = "${var.project_name}-${var.environment}-logs"
    Purpose = "Application logs from ECS Fargate"
  }

  lifecycle {
  ignore_changes = all
  }
}