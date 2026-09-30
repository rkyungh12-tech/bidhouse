# ============================================================================
# [01-aws-seoul-network/security-variables.tf]
# Cognito 및 WAF 초기 배포용 조정값
# ============================================================================

variable "cognito_spa_callback_urls" {
  type    = list(string)
  default = ["https://www.bidhouse.cloud/auth/callback"] # 🟢 민조님 찐 도메인으로 교체!
}

variable "cognito_spa_logout_urls" {
  type    = list(string)
  default = ["https://www.bidhouse.cloud/"] # 🟢 민조님 찐 도메인으로 교체!
}

variable "waf_rate_limit_requests_per_5_minutes" {
  description = "단일 IP가 5분 동안 보낼 수 있는 최대 요청 수. 초과 요청은 차단합니다."
  type        = number
  default     = 2000

  validation {
    condition     = var.waf_rate_limit_requests_per_5_minutes >= 100
    error_message = "WAF rate limit은 100 이상이어야 합니다."
  }
}

variable "waf_log_retention_days" {
  description = "WAF CloudWatch 로그 보존 일수"
  type        = number
  default     = 30
}

# ============================================================================
# [01-aws-seoul-network/ecs-autoscaling-variables.tf]
# ECS Service Auto Scaling 조정값
# ============================================================================

variable "ecs_autoscaling_enabled" {
  description = "ECS Service Auto Scaling 활성화 여부"
  type        = bool
  default     = true  
}

variable "ecs_autoscaling_min_capacity" {
  description = "ECS Service 최소 Task 수. 웹 서비스 가용성을 위해 기본값은 1입니다."
  type        = number
  default     = 1

  validation {
    condition     = var.ecs_autoscaling_min_capacity >= 1
    error_message = "ecs_autoscaling_min_capacity는 1 이상이어야 합니다."
  }
}

variable "ecs_autoscaling_max_capacity" {
  description = "ECS Service 최대 Task 수. 초기 팀 프로젝트 기본값은 4입니다."
  type        = number
  default     = 4
}

variable "ecs_autoscaling_cpu_target_percent" {
  description = "ECS Service 평균 CPU 사용률 목표값(%)"
  type        = number
  default     = 70

  validation {
    condition     = var.ecs_autoscaling_cpu_target_percent > 0 && var.ecs_autoscaling_cpu_target_percent <= 100
    error_message = "ecs_autoscaling_cpu_target_percent는 0 초과 100 이하여야 합니다."
  }
}

variable "ecs_autoscaling_memory_target_percent" {
  description = "ECS Service 평균 메모리 사용률 목표값(%)"
  type        = number
  default     = 70

  validation {
    condition     = var.ecs_autoscaling_memory_target_percent > 0 && var.ecs_autoscaling_memory_target_percent <= 100
    error_message = "ecs_autoscaling_memory_target_percent는 0 초과 100 이하여야 합니다."
  }
}

variable "ecs_autoscaling_scale_out_cooldown_seconds" {
  description = "scale-out 이후 다음 확장 판단까지 기다리는 시간(초)"
  type        = number
  default     = 60

  validation {
    condition     = var.ecs_autoscaling_scale_out_cooldown_seconds >= 0
    error_message = "ecs_autoscaling_scale_out_cooldown_seconds는 0 이상이어야 합니다."
  }
}

variable "ecs_autoscaling_scale_in_cooldown_seconds" {
  description = "scale-in 이후 다음 축소 판단까지 기다리는 시간(초). 가용성 보호를 위해 길게 설정합니다."
  type        = number
  default     = 300

  validation {
    condition     = var.ecs_autoscaling_scale_in_cooldown_seconds >= 0
    error_message = "ecs_autoscaling_scale_in_cooldown_seconds는 0 이상이어야 합니다."
  }
}


# ============================================================================
# RDS 조정값
# VPC와 Private Subnet ID는 변수로 받지 않고 vpc.tf 리소스를 직접 참조합니다.
# ============================================================================

variable "rds_db_name" {
  description = "애플리케이션 MySQL 데이터베이스 이름"
  type        = string
  default     = "auction"
}

variable "rds_master_username" {
  description = "RDS 마스터 사용자명"
  type        = string
  default     = "auction_admin"
}

variable "rds_instance_class" {
  description = "RDS 인스턴스 클래스"
  type        = string
  default     = "db.t4g.micro"
}

variable "rds_allocated_storage" {
  description = "RDS 스토리지 크기(GB)"
  type        = number
  default     = 20
}

variable "rds_multi_az" {
  description = "RDS Multi-AZ 사용 여부. 실습 비용을 줄이려면 false, 운영이면 true 검토"
  type        = bool
  default     = false
}

variable "rds_deletion_protection" {
  description = "RDS 삭제 방지 여부. 운영이면 true 권장"
  type        = bool
  default     = false
}

variable "rds_skip_final_snapshot" {
  description = "RDS 삭제 시 최종 스냅샷 생략 여부. 운영이면 false 권장"
  type        = bool
  default     = true
}

variable "app_image_tag" {
  description = "ECS Task가 실행할 ECR 이미지 태그. CodeBuild가 Git Commit SHA를 전달합니다."
  type        = string
  default     = "bootstrap"
}

variable "s3_images_bucket_name" {
  description = "S3 bucket name for auction images"
  type        = string
  default     = ""
}