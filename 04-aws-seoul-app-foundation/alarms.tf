resource "aws_cloudwatch_log_metric_filter" "application_error" {
  name           = "${var.project_name}-${var.environment}-application-error-filter"
  log_group_name = aws_cloudwatch_log_group.auction_app.name

  pattern = "?ERROR ?Error ?error ?Exception ?exception"

  metric_transformation {
    name      = "ApplicationErrorCount"
    namespace = "BidHouse/Logs"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "application_error" {
  alarm_name        = "${var.project_name}-${var.environment}-application-error"
  alarm_description = "Application logs contain ERROR or Exception"

  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  datapoints_to_alarm = 1

  metric_name = aws_cloudwatch_log_metric_filter.application_error.metric_transformation[0].name
  namespace   = aws_cloudwatch_log_metric_filter.application_error.metric_transformation[0].namespace

  period    = 60
  statistic = "Sum"
  threshold = 1

  treat_missing_data = "notBreaching"

  alarm_actions = [
    aws_sns_topic.operations_alerts.arn
  ]

  ok_actions = [
    aws_sns_topic.operations_alerts.arn
  ]

  tags = {
    Name    = "${var.project_name}-${var.environment}-application-error"
    Purpose = "Detect application error logs"
  }
}


resource "aws_cloudwatch_metric_alarm" "ecs_high_cpu" {
  alarm_name        = "${var.project_name}-${var.environment}-ecs-high-cpu"
  alarm_description = "ECS service CPU utilization is 80 percent or higher for 3 minutes"

  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 3
  datapoints_to_alarm = 3

  metric_name = "CPUUtilization"
  namespace   = "AWS/ECS"

  period    = 60
  statistic = "Average"
  threshold = 80

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = var.ecs_service_name
  }

  treat_missing_data = "notBreaching"

  alarm_actions = [
    aws_sns_topic.operations_alerts.arn
  ]

  ok_actions = [
    aws_sns_topic.operations_alerts.arn
  ]

  tags = {
    Name    = "${var.project_name}-${var.environment}-ecs-high-cpu"
    Purpose = "Detect sustained ECS CPU pressure"
  }
}