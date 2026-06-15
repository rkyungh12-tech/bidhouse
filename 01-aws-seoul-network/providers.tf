provider "aws" {
  region = "ap-northeast-2" # 대한민국 서울 리전 고정
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}