# terraform/02-azure-singapore-dr/log-analytics.tf

resource "azurerm_log_analytics_workspace" "law" {
  name                = "${var.prefix}-law"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018" # 가장 기본 요금제
  retention_in_days   = 30          # 로그 보관 기간 30일
}