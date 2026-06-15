provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "BidHouse"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = "team-member-1"
    }
  }
  
}

data "aws_caller_identity" "current" {}