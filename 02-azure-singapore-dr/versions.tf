terraform {
  required_version = ">= 1.0.0"

  backend "s3" {
    bucket  = "bidhouse-global-immutable-2026" # 👈 동일한 S3 버킷 이름
    key     = "singapore-dr/terraform.tfstate" # 🇸🇬 애저 싱가포르 전용 장부 칸
    region  = "ap-northeast-2"
    encrypt = true
  }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }
}