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

# 04-aws-seoul-app-foundation/variables.tf 하단에 추가
variable "rds_host" {
  description = "RDS endpoint for failback Lambda"
  type        = string
  default     = ""
}

variable "rds_user" {
  description = "RDS master username for failback Lambda"
  type        = string
  default     = ""
  sensitive   = true
}

variable "rds_pass" {
  description = "RDS master password for failback Lambda"
  type        = string
  default     = ""
  sensitive   = true
}

variable "az_mysql_host" {
  description = "Azure MySQL FQDN for failback Lambda"
  type        = string
  default     = ""
}

variable "az_mysql_user" {
  description = "Azure MySQL admin username"
  type        = string
  default     = ""
  sensitive   = true
}

variable "az_mysql_pass" {
  description = "Azure MySQL admin password"
  type        = string
  default     = ""
  sensitive   = true
}

variable "repl_pass" {
  description = "Replication user password"
  type        = string
  default     = ""
  sensitive   = true
}

variable "primary_health_check_id" {
  description = "Route53 health check ID for Seoul PRIMARY"
  type        = string
  default     = ""
}

variable "lambda_subnet_ids" {
  description = "Subnet IDs for failback Lambda VPC config"
  type        = list(string)
  default     = []
}

variable "lambda_security_group_ids" {
  description = "Security group IDs for failback Lambda VPC config"
  type        = list(string)
  default     = []
}
variable "s3_images_bucket_name" {
  description = "S3 bucket name for auction images (failback 역동기화용)"
  type        = string
  default     = ""
}
