# ============================================================================
# [01-aws-seoul-network/nat.tf]
# Private Subnet의 ECS Task가 외부 AWS Endpoint와 통신하기 위한 NAT Gateway
# ============================================================================

# NAT Gateway에 연결할 Elastic IP
resource "aws_eip" "prod_nat" {
  domain = "vpc"

  tags = {
    Name = "bidhouse-prod-nat-eip"
  }
}

# Public Subnet 2a에 NAT Gateway 생성
resource "aws_nat_gateway" "prod" {
  allocation_id = aws_eip.prod_nat.id
  subnet_id     = aws_subnet.prod_public.id

  # Internet Gateway가 연결된 이후 NAT Gateway를 생성합니다.
  depends_on = [
    aws_internet_gateway.prod_igw
  ]

  tags = {
    Name = "bidhouse-prod-nat-gateway"
  }
}

# 확인용 출력값
output "prod_nat_gateway_id" {
  description = "운영망 Private Subnet의 외부 통신용 NAT Gateway ID"
  value       = aws_nat_gateway.prod.id
}

output "prod_nat_gateway_public_ip" {
  description = "NAT Gateway에 연결된 Elastic IP"
  value       = aws_eip.prod_nat.public_ip
}

output "nat_gateway_public_ip" {
  value = aws_eip.prod_nat.public_ip
}