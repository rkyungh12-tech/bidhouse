variable "aws_region" {
  description = "AWS Seoul region"
  type        = string
  default     = "ap-northeast-2"
}

variable "project_name" {
  description = "Project prefix"
  type        = string
  default     = "bidhouse"
}

# 🟢 [04-aws-seoul-app-foundation/variables.tf] 수정본

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "prod" # 👈 dev에서 prod로 변경하여 01, 02번 진영과 일치시킵니다!
}

variable "alarm_email" {
  description = "Email address that receives CloudWatch alarm notifications"
  type        = string
  default     = "dkdlemf07@gmail.com"
}

variable "ecs_cluster_name" {
  description = "Future ECS cluster name"
  type        = string
  default     = "bidhouse-prod-cluster" # 👈 prod로 변경
}

variable "ecs_service_name" {
  description = "Future ECS service name"
  type        = string
  default     = "bidhouse-prod-service" # 👈 prod로 변경
}

variable "log_retention_days" {
  description = "CloudWatch log retention period"
  type        = number
  default     = 14
}