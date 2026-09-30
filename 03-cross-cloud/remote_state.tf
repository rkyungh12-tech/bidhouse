# 03-cross-cloud/remote_state.tf 파일 수정

# 🟢 1번 AWS 서울 네트워크 방의 영수증 장부 훔쳐오기 설정
data "terraform_remote_state" "aws" {
  backend = "s3"
  config = {
    bucket = "bidhouse-global-immutable-2026" # 🔴 민조님 진짜 버킷 주소 장전!
    key    = "seoul-network/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

# 🟢 2번 애저 싱가포르 방의 영수증 장부 훔쳐오기 설정
data "terraform_remote_state" "azure" {
  backend = "s3"
  config = {
    bucket = "bidhouse-global-immutable-2026" # 🔴 민조님 진짜 버킷 주소 장전!
    key    = "singapore-dr/terraform.tfstate"
    region = "ap-northeast-2"
  }
}