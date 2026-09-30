# terraform/02-azure-singapore-dr/acr.tf

resource "azurerm_container_registry" "acr" {
  # ⚠️ 주의: 전 세계에서 중복 안 되는 고유한 소문자+숫자 조합이어야 합니다! (예: bidhousedracr0602)
  name                = "bidhousedracr${random_string.global_suffix.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Basic" # 학생/팀 프로젝트용 가장 저렴하고 기본 옵션
  admin_enabled       = false   # ACA는 Managed Identity + AcrPull로 이미지를 가져옵니다.

  tags = {
    Environment = "DR"
    Project     = "BidHouse"
  }
}

# 3번 파일(cross-cloud)이나 터미널에서 창고 주소를 바로 알 수 있게 출력 설정
output "acr_login_server" {
  value       = azurerm_container_registry.acr.login_server
  description = "도커 이미지를 푸시할 창고 주소 URL"
}