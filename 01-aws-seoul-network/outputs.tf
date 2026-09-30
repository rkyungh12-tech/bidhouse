# ============================================================================
# [01-aws-seoul-network/ecs-autoscaling-outputs.tf]
# ECS Service Auto Scaling 확인용 출력값
# ============================================================================

output "ecs_autoscaling_enabled" {
  description = "ECS Service Auto Scaling 활성화 여부"
  value       = var.ecs_autoscaling_enabled
}

output "ecs_autoscaling_resource_id" {
  description = "Application Auto Scaling에 등록된 ECS Service 식별자"
  value       = try(aws_appautoscaling_target.ecs_service[0].resource_id, null)
}

output "ecs_autoscaling_min_capacity" {
  description = "ECS Service 최소 Task 수"
  value       = var.ecs_autoscaling_min_capacity
}

output "ecs_autoscaling_max_capacity" {
  description = "ECS Service 최대 Task 수"
  value       = var.ecs_autoscaling_max_capacity
}

output "ecs_autoscaling_cpu_policy_arn" {
  description = "CPU Target Tracking 정책 ARN"
  value       = try(aws_appautoscaling_policy.ecs_cpu_target_tracking[0].arn, null)
}

output "ecs_autoscaling_memory_policy_arn" {
  description = "메모리 Target Tracking 정책 ARN"
  value       = try(aws_appautoscaling_policy.ecs_memory_target_tracking[0].arn, null)
}




# ============================================================================
# [01-aws-seoul-network/security-outputs.tf]
# Cognito 및 WAF 연동 시 필요한 출력값
# ============================================================================

output "cognito_user_pool_id" {
  description = "웹 애플리케이션 Cognito User Pool ID"
  value       = aws_cognito_user_pool.web.id
}

output "cognito_user_pool_arn" {
  description = "웹 애플리케이션 Cognito User Pool ARN"
  value       = aws_cognito_user_pool.web.arn
}

output "cognito_user_pool_domain" {
  description = "Cognito Hosted UI 또는 Managed Login 도메인 prefix"
  value       = aws_cognito_user_pool_domain.web.domain
}

output "cognito_issuer_url" {
  description = "백엔드에서 Cognito JWT iss claim을 검증할 때 사용할 issuer URL"
  value       = "https://cognito-idp.${data.aws_region.current.name}.amazonaws.com/${aws_cognito_user_pool.web.id}"
}

output "cognito_jwks_url" {
  description = "백엔드에서 Cognito JWT 서명을 검증할 때 사용할 JWKS URL"
  value       = "https://cognito-idp.${data.aws_region.current.name}.amazonaws.com/${aws_cognito_user_pool.web.id}/.well-known/jwks.json"
}

output "cognito_spa_client_id" {
  description = "프론트엔드 직접 연동용 공개 App Client ID"
  value       = aws_cognito_user_pool_client.spa.id
}

output "cognito_spa_login_url" {
  description = "로컬 테스트용 Cognito 로그인 진입 URL. callback URL을 운영 URL로 바꾸면 함께 갱신됩니다."
  value       = "https://${aws_cognito_user_pool_domain.web.domain}.auth.${data.aws_region.current.name}.amazoncognito.com/login?client_id=${aws_cognito_user_pool_client.spa.id}&response_type=code&scope=openid+email+profile&redirect_uri=${urlencode(var.cognito_spa_callback_urls[0])}"
}

output "cognito_alb_client_id" {
  description = "추후 ALB authenticate-cognito 액션에서 사용할 비밀 App Client ID"
  value       = aws_cognito_user_pool_client.alb.id
}

output "cognito_alb_callback_url" {
  description = "추후 HTTPS ALB 인증 연동 시 Cognito에 등록된 callback URL"
  value       = "https://${aws_lb.aws_alb.dns_name}/oauth2/idpresponse"
}

output "waf_web_acl_arn" {
  description = "서울 ALB에 연결된 WAFv2 Web ACL ARN"
  value       = aws_wafv2_web_acl.alb.arn
}

output "waf_log_group_name" {
  description = "WAF 요청 로그가 저장되는 CloudWatch Log Group 이름"
  value       = aws_cloudwatch_log_group.waf.name
}

output "prod_private_subnet_ids" {
  description = "Private subnet IDs for Lambda VPC config"
  value       = [
    data.aws_subnet.prod_private_a.id,
    data.aws_subnet.prod_private_c.id
  ]
}

output "prod_vpc_id" {
  description = "Production VPC ID"
  value       = data.aws_vpc.prod_vpc.id
}

data "aws_eip" "prod_nat" {
  filter {
    name   = "tag:Name"
    values = ["bidhouse-prod-nat-eip"]
  }
  filter {
    name   = "domain"
    values = ["vpc"]
  }
}

output "prod_nat_gateway_public_ip" {
  value = data.aws_eip.prod_nat.public_ip
}