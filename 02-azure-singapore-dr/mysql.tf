# ============================================================================
# Azure Database for MySQL Flexible Server (DR)
# ============================================================================

# [0번] 메인 서버 (가장 먼저 생성)
resource "azurerm_mysql_flexible_server" "mysql" {
  name                   = "bidhousedrmysql${random_string.global_suffix.result}"
  resource_group_name    = azurerm_resource_group.rg.name
  location               = azurerm_resource_group.rg.location
  administrator_login    = var.azure_mysql_admin_username
  administrator_password = random_password.mysql_admin.result
  backup_retention_days  = 7
  delegated_subnet_id    = azurerm_subnet.mysql_subnet.id      # 전용 서브넷 필요
  private_dns_zone_id    = azurerm_private_dns_zone.mysql.id 
  version                = "8.0.21"
  sku_name               = "GP_Standard_D2ds_v4"
  zone                   = "1"

  depends_on = [
    azurerm_private_dns_zone_virtual_network_link.mysql
  ]

  tags = {
    Environment = "DR"
    Project     = "BidHouse"
  }
  timeouts {
    create = "60m"
    update = "60m"
  }
}

# [1번] 방화벽 규칙 (메인 서버가 만들어진 직후 실행)
resource "azurerm_mysql_flexible_server_firewall_rule" "allow_codebuild" {
  name                = "allow-codebuild-nat"
  resource_group_name = azurerm_resource_group.rg.name
  server_name         = azurerm_mysql_flexible_server.mysql.name
  start_ip_address    = var.nat_gateway_public_ip
  end_ip_address      = var.nat_gateway_public_ip
}

# ⭐ [1-1번] 방화벽 규칙 (메인 서버가 만들어진 직후 실행 - Azure 내부 서비스 접근 허용)
# 컨테이너 앱(Node.js)이 DB에 접근하려면 이 규칙이 반드시 필요합니다!
resource "azurerm_mysql_flexible_server_firewall_rule" "allow_azure_services" {
  name                = "allow-azure-services"
  resource_group_name = azurerm_resource_group.rg.name
  server_name         = azurerm_mysql_flexible_server.mysql.name
  start_ip_address    = "0.0.0.0"
  end_ip_address      = "0.0.0.0"
}

# [2번] 서버 설정 (방화벽 생성이 완전히 끝난 후 실행)
resource "azurerm_mysql_flexible_server_configuration" "max_allowed_packet" {
  name                = "max_allowed_packet"
  resource_group_name = azurerm_resource_group.rg.name
  server_name         = azurerm_mysql_flexible_server.mysql.name
  value               = "1073741824"

  depends_on = [
    azurerm_mysql_flexible_server_firewall_rule.allow_codebuild,
    azurerm_mysql_flexible_server_firewall_rule.allow_azure_services # 👈 이 줄을 꼭 추가해 주세요!
  ]
}

# [3번] 데이터베이스 (서버 설정까지 모두 끝난 후 마지막으로 실행)
resource "azurerm_mysql_flexible_database" "auction" {
  name                = "auction"
  resource_group_name = azurerm_resource_group.rg.name
  server_name         = azurerm_mysql_flexible_server.mysql.name
  charset             = "utf8mb4"
  collation           = "utf8mb4_unicode_ci"

  depends_on = [
    azurerm_mysql_flexible_server_configuration.max_allowed_packet
  ]
}

# ============================================================================
# Outputs
# ============================================================================

output "azure_mysql_fqdn" {
  value       = azurerm_mysql_flexible_server.mysql.fqdn
  description = "Azure DR MySQL FQDN"
}

output "azure_mysql_server_name" {
  value       = azurerm_mysql_flexible_server.mysql.name
  description = "Azure DR MySQL Flexible Server name"
}