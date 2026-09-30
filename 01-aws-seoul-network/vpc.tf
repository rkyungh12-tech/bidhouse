# ==========================================================================
# [01-aws-seoul-network/vpc.tf]
# VPC/서브넷/NAT는 00-pipeline에서 생성 → 여기서는 data로 참조
# TGW는 여기서 생성 → 라우트는 aws_route 리소스로 추가
# ==========================================================================

# ==========================================================
# 1. 00-pipeline에서 생성된 VPC/서브넷/라우팅 테이블 참조
# ==========================================================
data "aws_vpc" "prod_vpc" {
  tags = { Name = "bidhouse-prod-vpc" }
}

data "aws_subnet" "prod_public" {
  tags = { Name = "bidhouse-prod-public-sub" }
}

data "aws_subnet" "prod_public_2" {
  tags = { Name = "bidhouse-prod-public-sub-2" }
}

data "aws_subnet" "prod_private_a" {
  tags = { Name = "bidhouse-prod-private-sub-a" }
}

data "aws_subnet" "prod_private_c" {
  tags = { Name = "bidhouse-prod-private-sub-c" }
}

data "aws_route_table" "prod_public_rt" {
  tags = { Name = "bidhouse-prod-public-rt" }
}

data "aws_route_table" "prod_private_rt" {
  tags = { Name = "bidhouse-prod-private-rt" }
}

# ==========================================================
# 2. Transit Gateway (TGW) 생성
# ==========================================================
resource "aws_ec2_transit_gateway" "main_tgw" {
  description                     = "Bidhouse Multi-VPC Central Hub TGW"
  amazon_side_asn                 = 64512
  auto_accept_shared_attachments  = "enable"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  tags                            = { Name = "bidhouse-seoul-tgw" }
}

# ==========================================================
# 3. Prod VPC → TGW 연결
# ==========================================================
resource "aws_ec2_transit_gateway_vpc_attachment" "prod_tgw_attach" {
  transit_gateway_id = aws_ec2_transit_gateway.main_tgw.id
  vpc_id             = data.aws_vpc.prod_vpc.id
  subnet_ids         = [data.aws_subnet.prod_public.id, data.aws_subnet.prod_public_2.id]
  tags               = { Name = "bidhouse-tgw-attach-prod" }
}

# ==========================================================
# 4. Prod 라우팅 테이블에 TGW 라우트 추가
# ==========================================================
resource "aws_route" "prod_public_to_mgmt" {
  route_table_id         = data.aws_route_table.prod_public_rt.id
  destination_cidr_block = "10.2.0.0/16"
  transit_gateway_id     = aws_ec2_transit_gateway.main_tgw.id
}

resource "aws_route" "prod_public_to_azure" {
  route_table_id         = data.aws_route_table.prod_public_rt.id
  destination_cidr_block = "10.3.0.0/16"
  transit_gateway_id     = aws_ec2_transit_gateway.main_tgw.id
}

resource "aws_route" "prod_public_to_azure_mgmt" {
  route_table_id         = data.aws_route_table.prod_public_rt.id
  destination_cidr_block = "10.4.0.0/16"
  transit_gateway_id     = aws_ec2_transit_gateway.main_tgw.id
}

resource "aws_route" "prod_private_to_mgmt" {
  route_table_id         = data.aws_route_table.prod_private_rt.id
  destination_cidr_block = "10.2.0.0/16"
  transit_gateway_id     = aws_ec2_transit_gateway.main_tgw.id
}

resource "aws_route" "prod_private_to_azure" {
  route_table_id         = data.aws_route_table.prod_private_rt.id
  destination_cidr_block = "10.3.0.0/16"
  transit_gateway_id     = aws_ec2_transit_gateway.main_tgw.id
}

resource "aws_route" "prod_private_to_azure_mgmt" {
  route_table_id         = data.aws_route_table.prod_private_rt.id
  destination_cidr_block = "10.4.0.0/16"
  transit_gateway_id     = aws_ec2_transit_gateway.main_tgw.id
}

# ==========================================================
# 5. VPC #2: 관리/개발망 (Mgmt VPC - 10.2.0.0/16)
# 이건 01에서 그대로 생성 (CodeBuild 불필요)
# ==========================================================
resource "aws_vpc" "mgmt_vpc" {
  cidr_block           = "10.2.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = { Name = "bidhouse-mgmt-vpc" }
}

resource "aws_internet_gateway" "mgmt_igw" {
  vpc_id = aws_vpc.mgmt_vpc.id
  tags   = { Name = "bidhouse-mgmt-igw" }
}

resource "aws_subnet" "mgmt_public" {
  vpc_id                  = aws_vpc.mgmt_vpc.id
  cidr_block              = "10.2.1.0/24"
  availability_zone       = "ap-northeast-2a"
  map_public_ip_on_launch = true
  tags                    = { Name = "bidhouse-mgmt-public-sub" }
}

resource "aws_route_table" "mgmt_public_rt" {
  vpc_id = aws_vpc.mgmt_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.mgmt_igw.id
  }
  route {
    cidr_block         = "10.1.0.0/16"
    transit_gateway_id = aws_ec2_transit_gateway.main_tgw.id
  }
  tags = { Name = "bidhouse-mgmt-public-rt" }
}

resource "aws_route_table_association" "mgmt_pub" {
  subnet_id      = aws_subnet.mgmt_public.id
  route_table_id = aws_route_table.mgmt_public_rt.id
}

resource "aws_ec2_transit_gateway_vpc_attachment" "mgmt_tgw_attach" {
  transit_gateway_id = aws_ec2_transit_gateway.main_tgw.id
  vpc_id             = aws_vpc.mgmt_vpc.id
  subnet_ids         = [aws_subnet.mgmt_public.id]
  tags               = { Name = "bidhouse-tgw-attach-mgmt" }
}

# ==========================================================
# 6. 출력값
# ==========================================================
output "aws_vpc_id" {
  value       = data.aws_vpc.prod_vpc.id
  description = "메인 운영 VPC ID"
}

output "prod_private_subnet_a_id" {
  value       = data.aws_subnet.prod_private_a.id
  description = "운영망 Private Subnet A ID (ap-northeast-2a)"
}

output "prod_private_subnet_c_id" {
  value       = data.aws_subnet.prod_private_c.id
  description = "운영망 Private Subnet C ID (ap-northeast-2c)"
}

output "aws_tgw_id" {
  description = "Transit Gateway ID for cross-cloud VPN"
  value       = aws_ec2_transit_gateway.main_tgw.id
}
