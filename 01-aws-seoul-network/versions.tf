# 🛠️ [01-aws-seoul-network/versions.tf] 수정본
terraform {
  required_version = ">= 1.0.0"

  # 🔴 [여기가 치트키] 이제 장부를 내 노트북이나 CodeBuild 디스크에 두지 않고 방금 만든 S3 금고에 저축합니다!
  backend "s3" {
    bucket  = "bidhouse-global-immutable-2026"  # 👈 1단계 아웃풋에서 나온 실제 버킷 이름을 여기에 붙여넣기!
    key     = "seoul-network/terraform.tfstate" # 금고 안의 저장 경로 이름
    region  = "ap-northeast-2"
    encrypt = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
      configuration_aliases = [aws.us_east_1]
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}