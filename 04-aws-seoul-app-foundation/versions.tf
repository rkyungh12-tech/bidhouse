terraform {
  required_version = ">= 1.0.0"

  backend "s3" {
    bucket  = "bidhouse-global-immutable-2026" # 👈 동일한 S3 버킷 이름
    key     = "seoul-app-foundation/terraform.tfstate" # 🚀 앱 인프라 전용 장부 칸
    region  = "ap-northeast-2"
    encrypt = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"  
      version = "~> 3.0"
    }
  }
}