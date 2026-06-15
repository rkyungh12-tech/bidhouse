# ==========================================================================
# [01-aws-seoul-network/vpc.tf] 인프라 네트워크 메인 완공 본진
# ==========================================================================

# ==========================================================
# 1. 중앙 허브 장비: Transit Gateway (TGW) 생성
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
# 2. VPC #1: 운영망 (Prod VPC - 10.1.0.0/16)
# ==========================================================
resource "aws_vpc" "prod_vpc" {
  cidr_block           = "10.1.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = { Name = "bidhouse-prod-vpc" }
}

# 인터넷 게이트웨이 (Prod 퍼블릭용 메인 대문)
resource "aws_internet_gateway" "prod_igw" {
  vpc_id = aws_vpc.prod_vpc.id
  tags   = { Name = "bidhouse-prod-igw" }
}

# 🌐 Prod 퍼블릭 서브넷 1번 (2a 구역)
resource "aws_subnet" "prod_public" {
  vpc_id                  = aws_vpc.prod_vpc.id
  cidr_block              = "10.1.1.0/24"
  availability_zone       = "ap-northeast-2a"
  map_public_ip_on_launch = true
  tags                    = { Name = "bidhouse-prod-public-sub" }
}

# 🌐 Prod 퍼블릭 서브넷 2번 (2c 구역)
resource "aws_subnet" "prod_public_2" {
  vpc_id                  = aws_vpc.prod_vpc.id
  cidr_block              = "10.1.3.0/24"
  availability_zone       = "ap-northeast-2c"
  map_public_ip_on_launch = true
  tags                    = { Name = "bidhouse-prod-public-sub-2" }
}

# 🔒 Prod 프라이빗 서브넷 1번 (2a 구역)
resource "aws_subnet" "prod_private_a" {
  vpc_id            = aws_vpc.prod_vpc.id
  cidr_block        = "10.1.2.0/24"
  availability_zone = "ap-northeast-2a"
  tags               = { Name = "bidhouse-prod-private-sub-a" }
}

# 🔒 Prod 프라이빗 서브넷 2번 (2c 구역)
resource "aws_subnet" "prod_private_c" {
  vpc_id            = aws_vpc.prod_vpc.id
  cidr_block        = "10.1.4.0/24"
  availability_zone = "ap-northeast-2c"
  tags               = { Name = "bidhouse-prod-private-sub-c" }
}

# Prod 퍼블릭 라우팅 테이블 설정
resource "aws_route_table" "prod_public_rt" {
  vpc_id = aws_vpc.prod_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.prod_igw.id
  }
  route {
    cidr_block         = "10.2.0.0/16"
    transit_gateway_id = aws_ec2_transit_gateway.main_tgw.id
  }
  route {
    cidr_block         = "10.3.0.0/16"
    transit_gateway_id = aws_ec2_transit_gateway.main_tgw.id
  }
  route {
    cidr_block         = "10.4.0.0/16"
    transit_gateway_id = aws_ec2_transit_gateway.main_tgw.id
  }
  tags = { Name = "bidhouse-prod-public-rt" }
}

# 3️⃣ 프라이빗 서브넷 전용 라우팅 테이블
resource "aws_route_table" "prod_private_rt" {
  vpc_id = aws_vpc.prod_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.prod.id
  }

  route {
    cidr_block         = "10.2.0.0/16"
    transit_gateway_id = aws_ec2_transit_gateway.main_tgw.id
  }
  route {
    cidr_block         = "10.3.0.0/16"
    transit_gateway_id = aws_ec2_transit_gateway.main_tgw.id
  }
  route {
    cidr_block         = "10.4.0.0/16"
    transit_gateway_id = aws_ec2_transit_gateway.main_tgw.id
  }

  tags = { Name = "bidhouse-prod-private-rt" }
}

# 🔗 라우팅 연결들
resource "aws_route_table_association" "prod_pub" {
  subnet_id      = aws_subnet.prod_public.id
  route_table_id = aws_route_table.prod_public_rt.id
}

resource "aws_route_table_association" "prod_pub_2" {
  subnet_id      = aws_subnet.prod_public_2.id
  route_table_id = aws_route_table.prod_public_rt.id
}

resource "aws_route_table_association" "prod_pri_a" {
  subnet_id      = aws_subnet.prod_private_a.id
  route_table_id = aws_route_table.prod_private_rt.id
}

resource "aws_route_table_association" "prod_pri_c" {
  subnet_id      = aws_subnet.prod_private_c.id
  route_table_id = aws_route_table.prod_private_rt.id
}

resource "aws_ec2_transit_gateway_vpc_attachment" "prod_tgw_attach" {
  transit_gateway_id = aws_ec2_transit_gateway.main_tgw.id
  vpc_id             = aws_vpc.prod_vpc.id
  subnet_ids         = [aws_subnet.prod_public.id, aws_subnet.prod_public_2.id]
  tags               = { Name = "bidhouse-tgw-attach-prod" }
}

# ==========================================================
# 3. VPC #2: 관리/개발망 (Mgmt VPC - 10.2.0.0/16)
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
# 4. 출력 값 (Outputs)
# ==========================================================
output "aws_vpc_id" {
  value       = aws_vpc.prod_vpc.id
  description = "메인 운영 VPC ID"
}

output "prod_private_subnet_a_id" {
  value       = aws_subnet.prod_private_a.id
  description = "운영망 Private Subnet A ID (ap-northeast-2a)"
}

output "prod_private_subnet_c_id" {
  value       = aws_subnet.prod_private_c.id
  description = "운영망 Private Subnet C ID (ap-northeast-2c)"
}