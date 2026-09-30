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

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = "BidHouse"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = "team-member-1"
    }
  }
}