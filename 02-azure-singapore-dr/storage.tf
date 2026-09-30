# terraform/02-azure-singapore-dr/storage.tf

# 1. Azure 스토리지 계정(금고 본체) 생성
resource "azurerm_storage_account" "storage" {
  name                     = "bidhousedr${random_string.global_suffix.result}" # ⚠️ 소문자와 숫자만 가능, 전 세계 고유 이름 필요
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS" # 로컬 단일 리전 복제 (가장 저렴)

  tags = {
    Environment = "DR"
    Project     = "BidHouse"
  }
}

# 2. 스토리지 내부에 실제 파일이 저장될 'uploads' 폴더(컨테이너) 생성
resource "azurerm_storage_container" "container" {
  name                  = "uploads" # 현재 백엔드 소스코드의 uploads 폴더와 이름 매칭
  storage_account_name  = azurerm_storage_account.storage.name
  container_access_type = "blob" # 외부 유출 방지 보안 설정
}

output "azure_storage_account_name" {
  value = azurerm_storage_account.storage.name
}
output "azure_storage_account_key" {
  value     = azurerm_storage_account.storage.primary_access_key
  sensitive = true
}