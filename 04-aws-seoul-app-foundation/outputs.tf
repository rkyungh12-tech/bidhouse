output "s3_images_bucket_name" {
  description = "S3 bucket for auction product images"
  value       = aws_s3_bucket.auction_images.bucket
}

output "cloudwatch_log_group_name" {
  description = "CloudWatch Log Group for ECS application logs"
  value       = aws_cloudwatch_log_group.auction_app.name
}

output "sns_topic_arn" {
  description = "SNS topic for operational alerts"
  value       = aws_sns_topic.operations_alerts.arn
}


output "ecs_high_cpu_alarm_name" {
  description = "CloudWatch alarm for future ECS high CPU"
  value       = aws_cloudwatch_metric_alarm.ecs_high_cpu.alarm_name
}

output "application_error_alarm_name" {
  description = "CloudWatch alarm for application errors"
  value       = aws_cloudwatch_metric_alarm.application_error.alarm_name
}

output "s3_bucket_name" {
  value = aws_s3_bucket.auction_images.bucket
}

