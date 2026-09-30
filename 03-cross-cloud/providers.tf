terraform {
  required_version = ">= 1.0.0"

  # 🟢 3번 방 자기가 쓸 장부 금고 위치 설정
  backend "s3" {
    bucket  = "bidhouse-global-immutable-2026"
    key     = "cross-cloud/terraform.tfstate"
    region  = "ap-northeast-2"
    encrypt = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
    # 🚀 [추가] Let's Encrypt 무료 인증서 발급기
    acme = {
      source  = "vancluever/acme"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-2"
}

provider "azurerm" {
  # 🔴 [에러 1번 해결] 이 features 블록이 무조건 살아있어야 애저 테라폼이 파업을 안 합니다!
  features {}
}

# 🚀 [추가] Let's Encrypt 실제 운영 환경 URL 연결
provider "acme" {
  server_url = "https://acme-v02.api.letsencrypt.org/directory"
}