# ============================================================================
# [01-aws-seoul-network/ecr.tf] 애플리케이션 도커 이미지 보관소 (ECR)
# ============================================================================

resource "aws_ecr_repository" "app" {
  name                 = "bidhouse-prod-app"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "bidhouse-prod-app"
  }
}

# 📊 00번 파이프라인(CodeBuild) 및 외부 스크립트가 참조할 수 있도록 주소 출력 추가
output "ecr_repository_url" {
  value       = aws_ecr_repository.app.repository_url
  description = "도커 이미지를 푸시할 AWS ECR 창고 주소 URL"
}

output "aws_region" {
  value       = "ap-northeast-2"
  description = "메인 가동 리전"
}

