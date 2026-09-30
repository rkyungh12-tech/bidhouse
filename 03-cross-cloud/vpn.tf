# terraform/03-cross-cloud/vpn.tf

# TGW의 세부 정보(라우팅 테이블 ID 등)를 조회하기 위한 데이터 소스
data "aws_ec2_transit_gateway" "selected_tgw" {
  id = data.terraform_remote_state.aws.outputs.aws_tgw_id
}

# ==========================================================
# [AWS 설정] VPN 고속도로 입구 개설 (TGW 버전)
# ==========================================================

# 2. AWS 고객 게이트웨이 (Azure VPN GW의 공인 IP를 바라봄)
resource "aws_customer_gateway" "aws_cgw" {
  bgp_asn    = 65000
  ip_address = data.terraform_remote_state.azure.outputs.azure_vpn_gw_public_ip
  type       = "ipsec.1"
  tags       = { Name = "bidhouse-aws-cgw" }
}

# 3. AWS VPN 연결 (★핵심: vpn_gateway_id 대신 transit_gateway_id 사용!)
resource "aws_vpn_connection" "aws_vpn" {
  customer_gateway_id = aws_customer_gateway.aws_cgw.id
  transit_gateway_id  = data.terraform_remote_state.aws.outputs.aws_tgw_id
  type                = "ipsec.1"
  static_routes_only  = true

  tunnel1_log_options {
    cloudwatch_log_options {
      log_enabled       = true
      log_group_arn     = aws_cloudwatch_log_group.vpn.arn
      log_output_format = "json"
    }
  }

  tunnel2_log_options {
    cloudwatch_log_options {
      log_enabled       = true
      log_group_arn     = aws_cloudwatch_log_group.vpn.arn
      log_output_format = "json"
    }
  }

  tags = {
    Name        = "bidhouse-aws-vpn-to-azure"
    Environment = "prod"
    Project     = "bidhouse"
  }
}

# 4. 환승역(TGW) 라우팅 테이블에 "싱가포르(10.3.0.0/16)로 가려면 이 VPN 터널로 가라"고 이정표 심기
resource "aws_ec2_transit_gateway_route" "to_azure" {
  destination_cidr_block         = "10.3.0.0/16"
  transit_gateway_attachment_id  = aws_vpn_connection.aws_vpn.transit_gateway_attachment_id
  transit_gateway_route_table_id = data.aws_ec2_transit_gateway.selected_tgw.propagation_default_route_table_id
}

# ==========================================================
# [Azure 설정] AWS 터널과 도킹 (듀얼 터널 모두 UP 세팅)
# ==========================================================

# 5-1. Azure 로컬 네트워크 게이트웨이 1 (AWS 1번 터널 목적지)
resource "azurerm_local_network_gateway" "aws_lng1" {
  name                = "bidhouse-azure-lng-to-aws-1"
  location            = "Southeast Asia"
  resource_group_name = data.terraform_remote_state.azure.outputs.resource_group_name
  gateway_address     = aws_vpn_connection.aws_vpn.tunnel1_address
  address_space       = ["10.1.0.0/16", "10.2.0.0/16"]
}

# 5-2. Azure 로컬 네트워크 게이트웨이 2 
resource "azurerm_local_network_gateway" "aws_lng2" {
  name                = "bidhouse-azure-lng-to-aws-2"
  location            = "Southeast Asia"
  resource_group_name = data.terraform_remote_state.azure.outputs.resource_group_name
  gateway_address     = aws_vpn_connection.aws_vpn.tunnel2_address
  address_space       = ["10.1.0.0/16", "10.2.0.0/16"]
}

# 6-1. Azure 1번 터널 최종 연결 플러그
resource "azurerm_virtual_network_gateway_connection" "azure_conn1" {
  name                = "bidhouse-azure-to-aws-connection-1"
  location            = "Southeast Asia"
  resource_group_name = data.terraform_remote_state.azure.outputs.resource_group_name

  type                       = "IPsec"
  virtual_network_gateway_id = data.terraform_remote_state.azure.outputs.azure_vpn_gateway_id
  local_network_gateway_id   = azurerm_local_network_gateway.aws_lng1.id
  shared_key                 = aws_vpn_connection.aws_vpn.tunnel1_preshared_key

  timeouts {
    create = "30m"
    update = "30m"
  }
}

# 6-2. Azure 2번 터널 최종 연결 플러그
resource "azurerm_virtual_network_gateway_connection" "azure_conn2" {
  name                = "bidhouse-azure-to-aws-connection-2"
  location            = "Southeast Asia"
  resource_group_name = data.terraform_remote_state.azure.outputs.resource_group_name

  type                       = "IPsec"
  virtual_network_gateway_id = data.terraform_remote_state.azure.outputs.azure_vpn_gateway_id
  local_network_gateway_id   = azurerm_local_network_gateway.aws_lng2.id
  shared_key                 = aws_vpn_connection.aws_vpn.tunnel2_preshared_key

  timeouts {
    create = "30m"
    update = "30m"
  }
}

# [추가] 환승역(TGW) 라우팅 테이블에 "싱가포르 관리망(10.4) 이정표" 추가
resource "aws_ec2_transit_gateway_route" "to_azure_mgmt" {
  destination_cidr_block         = "10.4.0.0/16"
  transit_gateway_attachment_id  = aws_vpn_connection.aws_vpn.transit_gateway_attachment_id
  transit_gateway_route_table_id = data.aws_ec2_transit_gateway.selected_tgw.propagation_default_route_table_id
}

# ⏳ Azure 백엔드가 터널 정비를 마칠 때까지 1분간 안전하게 대기하는 시간 기계
resource "time_sleep" "wait_for_azure_gateway" {
  depends_on = [
    azurerm_virtual_network_gateway_connection.azure_conn1,
    azurerm_virtual_network_gateway_connection.azure_conn2
  ]

  # 터널 플러그가 완공되면 60초 동안 가만히 대기합니다.
  create_duration = "60s"
}
