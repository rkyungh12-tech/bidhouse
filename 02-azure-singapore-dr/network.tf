# ==========================================================================
# [02-azure-singapore-dr/network.tf] 네트워크 및 테스트 VM 대통합 장부
# ==========================================================================

# 🌐 1) 가상 네트워크 (VNet)
resource "azurerm_virtual_network" "vnet" {
  name                = "${var.prefix}-vnet"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.3.0.0/16"]
}

# 📦 2) Container Apps 전용 서브넷
resource "azurerm_subnet" "container_app_subnet" {
  name                 = "container-apps-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.3.1.0/24"]

  delegation {
    name = "aca-delegation"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# 📦 3) MySQL Flexible Server 전용 서브넷
resource "azurerm_subnet" "mysql_subnet" {
  name                 = "mysql-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.3.2.0/24"]

  delegation {
    name = "mysql-delegation"
    service_delegation {
      name    = "Microsoft.DBforMySQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# 🔒 MySQL Private DNS Zone
resource "azurerm_private_dns_zone" "mysql" {
  name                = "bidhouse.mysql.database.azure.com"
  resource_group_name = azurerm_resource_group.rg.name
}

# 🔗 DNS Zone ↔ VNet 연결
resource "azurerm_private_dns_zone_virtual_network_link" "mysql" {
  name                  = "mysql-dns-vnet-link"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.mysql.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
  registration_enabled  = false
}

# 🔗 DNS Zone ↔ Mgmt VNet 연결 (테스트 VM에서 DB 주소를 찾기 위한 필수 설정!)
resource "azurerm_private_dns_zone_virtual_network_link" "mysql_mgmt" {
  name                  = "mysql-dns-mgmt-vnet-link"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.mysql.name
  virtual_network_id    = azurerm_virtual_network.mgmt_vnet.id  # <--- 테스트 VM이 있는 관리망 연결
  registration_enabled  = false
}

# 🚇 4) VPN Gateway 전용 서브넷 (이름 고정 필수)
resource "azurerm_subnet" "azure_vpn_gw" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.3.255.0/27"]
}

# 🖥️ 5) Azure Mgmt VNet (관리망 - 10.4.0.0/16)
resource "azurerm_virtual_network" "mgmt_vnet" {
  name                = "bidhouse-mgmt-vnet"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.4.0.0/16"]
}

# 📡 6) Mgmt 서브넷 (테스트 가상머신용)
resource "azurerm_subnet" "mgmt_subnet" {
  name                 = "bidhouse-mgmt-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.mgmt_vnet.name
  address_prefixes     = ["10.4.1.0/24"]
}

# 🤝 7) VNet Peering (Prod VNet ↔ Mgmt VNet 터널 연결)
resource "azurerm_virtual_network_peering" "prod_to_mgmt" {
  name                         = "prod-to-mgmt"
  resource_group_name          = azurerm_resource_group.rg.name
  virtual_network_name         = azurerm_virtual_network.vnet.name
  remote_virtual_network_id    = azurerm_virtual_network.mgmt_vnet.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
}

resource "azurerm_virtual_network_peering" "mgmt_to_prod" {
  name                         = "mgmt-to-prod"
  resource_group_name          = azurerm_resource_group.rg.name
  virtual_network_name         = azurerm_virtual_network.mgmt_vnet.name
  remote_virtual_network_id    = azurerm_virtual_network.vnet.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  use_remote_gateways          = true
}

# 🚨 8) 진짜 Azure VPN 게이트웨이 기계 및 공인 IP 세팅
resource "azurerm_public_ip" "vpn_gw_pip" {
  name                = "${var.prefix}-vpn-gw-pip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
}

resource "azurerm_virtual_network_gateway" "azure_vpn_gw" {
  name                = "${var.prefix}-vpn-gw"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  type     = "Vpn"
  vpn_type = "RouteBased"

  active_active = false
  enable_bgp    = false
  sku           = "VpnGw1AZ"

  ip_configuration {
    name                          = "vnetGatewayConfig"
    public_ip_address_id          = azurerm_public_ip.vpn_gw_pip.id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.azure_vpn_gw.id
  }
}

# ==========================================================================
# 🛡️ 9) Azure VM 전용 방화벽 (22번 SSH 포트 완벽 장전)
# ==========================================================================
resource "azurerm_network_security_group" "azure_test_nsg" {
  name                = "bidhouse-azure-test-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  # 🔓 내 노트북에서 서버로 바로 들어올 수 있게 22번(SSH) 전면 허용!
  security_rule {
    name                       = "allow-ssh-inbound"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # 🔓 AWS 서울 대역(10.1.0.0/16, 10.2.0.0/16)에서 터널 타고 오는 핑 허용
  security_rule {
    name                       = "allow-icmp-from-aws"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Icmp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefixes    = ["10.1.0.0/16", "10.2.0.0/16"]
    destination_address_prefix = "*"
  }

  # ← 여기 추가
  security_rule {
    name                       = "allow-mysql-from-aws"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3306"
    source_address_prefixes    = ["10.1.0.0/16", "10.2.0.0/16"]
    destination_address_prefix = "*"
  }
}

# 🔥 [추가] 9-2) 가상 머신에 연결해 줄 '진짜 외부 인터넷용 공인 IP 주소판' 발급
resource "azurerm_public_ip" "azure_test_vm_pip" {
  name                = "bidhouse-az-test-vm-pip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# 📳 10) Azure 가상 랜선(NIC) 생성 및 '공인 IP' 합체 수리 완료
resource "azurerm_network_interface" "azure_test_nic" {
  name                = "bidhouse-azure-test-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.mgmt_subnet.id # 6번 관리망 서브넷 직결!
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.azure_test_vm_pip.id # 🔥 새로 만든 공인 IP 카드 결합!
  }
}

# 🔗 11) 랜선에 방화벽(NSG) 결합
resource "azurerm_network_interface_security_group_association" "test" {
  network_interface_id      = azurerm_network_interface.azure_test_nic.id
  network_security_group_id = azurerm_network_security_group.azure_test_nsg.id
}

# 🔥 [핵심 억까 해제] 생성한 방화벽(NSG)을 VM이 진짜 살고 있는 '관리망 대문(mgmt_subnet)'에 강제 본드칠!
resource "azurerm_subnet_network_security_group_association" "vm_subnet_assoc" {
  subnet_id                 = azurerm_subnet.mgmt_subnet.id
  network_security_group_id = azurerm_network_security_group.azure_test_nsg.id
}

resource "azurerm_subnet_network_security_group_association" "mysql_subnet_assoc" {
  subnet_id                 = azurerm_subnet.mysql_subnet.id
  network_security_group_id = azurerm_network_security_group.azure_test_nsg.id
}

# 🖥️ 12) Azure 싱가포르 테스트 가상 머신 정상 생성 (내부 꼬임 제거)
resource "azurerm_linux_virtual_machine" "azure_test_vm" {
  name                            = "bidhouse-az-test-vm"
  resource_group_name             = azurerm_resource_group.rg.name
  location                        = azurerm_resource_group.rg.location
  size                            = "Standard_D2s_v4"
  admin_username                  = "adminuser"
  disable_password_authentication = true

  custom_data = base64encode(<<-EOF
    #!/bin/bash
    sudo apt update -y
    sudo apt install -y mysql-client
  EOF
  )

  # ✅ 키파일 등록은 이렇게
  admin_ssh_key {
    username   = "adminuser"
    public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC8WtBxVXIOx5lt/Dqieut0BWIPL9Sv3Y9ae+jSURrTPCdo3p1S6t/j/rnG16oUESJQpYaUlPslHrHjJxZ3rk4EmEZcHhacMWZgSbQr9c0D373hm8RF+Zadx7CGVY7LQqROUttSFxUlIbqVclAveXbcwNE6scXYo/lCDWSCo5yav39QZqmItdHnMT7NWOF43wWMj2bx8Pg++/+RUrzaZP4FytK2k7iQQYjE1Gr/EhV8A3FwUvMBq86LFJL8eRTjV3YICvOXmRbBXtOaxQ91W7JT2aZ6TYp9hfn+58FIpMMFVFA9wP9kWraqSoOrisY5DZaUB2t4k8YXgJrDryaVmlzRxTNhtc+ngCuO+GZLdpdgyj+fQw4fpjB0Bv7s4Jdd3aLTfIG5D7k7xvK9MRci388uJ0Rt+vh5YL5rhEYr7Idgwew3/tqMBNG0al1TXCygEmXaJ2fb4B1Pqen5Syd4GGyqOiyr3MkiWS8yo98PIgc63XJj7ouxavKFxw1dPP68bRU="  # .pub 파일 경로
  }

  network_interface_ids = [azurerm_network_interface.azure_test_nic.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  
}

# ==========================================================================
# 📊 13) 완공 후 화면에 보여줄 출력 장부 (Outputs)
# ==========================================================================
output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "vnet_id" {
  value = azurerm_virtual_network.vnet.id
}

output "azure_mgmt_subnet_target_id" {
  value = azurerm_subnet.mgmt_subnet.id
}

output "azure_vpn_gw_public_ip" {
  value = azurerm_public_ip.vpn_gw_pip.ip_address
}

output "azure_vpn_gateway_id" {
  value = azurerm_virtual_network_gateway.azure_vpn_gw.id
}

# ⭐ [추가 영수증] 완공 즉시 노트북 터미널에서 한방에 들어갈 수 있게 진짜 외부 공인 IP를 출력!
output "test_vm_public_ip" {
  value       = azurerm_public_ip.azure_test_vm_pip.ip_address
  description = "The direct Public IP of Azure Test VM for SSH access"
}