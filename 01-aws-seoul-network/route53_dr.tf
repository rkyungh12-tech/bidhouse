# ==========================================================================
# [01-aws-seoul-network/route53_dr.tf] 컴퓨터 및 로드밸런싱 통제소
# ==========================================================================


# 🛡️ 1) ALB 및 EC2 공용 보안 그룹 (80번 웹 포트 + 22번 SSH 포트 대통합)
resource "aws_security_group" "alb_sg" {
  name        = "bidhouse-alb-sg"
  description = "Allow HTTP and SSH outbound/inbound"
  vpc_id      = data.aws_vpc.prod_vpc.id


  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS API endpoint: api.bidhouse.cloud -> ALB
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # 🟢 [★이거 빼먹으셨습니다! 추가해주세요!] VPC 내부 사설 핑 프리패스
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["10.1.0.0/16"] # Prod VPC 집안끼리 날리는 핑은 전면 통과
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

}
# 🛡️ 2) [EC2 전용 보안 그룹] 국경 간 사설 통신망 최종 패치
resource "aws_security_group" "aws_test_sg_2" {
  name        = "bidhouse-aws-test-sg-2"
  description = "Allow HTTP from ALB, SSH and ICMP for AWS and Azure"
  vpc_id      = data.aws_vpc.prod_vpc.id

  # 🌐 [기존] 1번방 ↔ 2번방 AWS 집안끼리 사설 핑 허용
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["10.1.0.0/16", "10.2.0.0/16"]
  }


  # 🟢 [★여기에 이 코드 추가!] 바다 건너 Azure 싱가포르에서 오는 사설 핑(ICMP) 전면 허용!!
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["10.3.0.0/16", "10.4.0.0/16"] # Azure 대역 전부 오픈!
  }

  # 🌐 기존 22번 SSH 포트 (그대로 유지)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # 🌐 기존 80번 웹 포트 (그대로 유지)
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ==========================================================================
# 🎧 [복구 완료] ECS 로드밸런서의 기반이 될 구형 ALB 및 80번 리스너 본체
# ==========================================================================

resource "aws_lb" "aws_alb" {
  name               = "bidhouse-seoul-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [data.aws_subnet.prod_public.id, data.aws_subnet.prod_public_2.id]

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.bucket
    prefix  = "alb"
    enabled = true
  }

  tags = {
    Name        = "bidhouse-seoul-alb"
    Environment = "prod"
    Project     = "bidhouse"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.aws_alb.arn
  port              = "80"
  protocol          = "HTTP"

  # ECS 리스너 룰이 작동하기 전, 기본적으로 응답할 깡통 액션 지정
  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Bidhouse ECS Infrastructure Service Root"
      status_code  = "200"
    }
  }
}

# ==========================================================================
# 🌐 [01번 방 교정] www.bidhouse.cloud - PRIMARY (메인 서울 공장)
# ==========================================================================

data "aws_route53_zone" "main" {
  name         = "bidhouse.cloud."
  private_zone = false
}

# Static frontend record.
# The resource label is intentionally preserved for state compatibility, but
# this is now a SIMPLE alias: www is always served by CloudFront -> S3.
resource "aws_route53_record" "www_primary" {
  zone_id         = data.aws_route53_zone.main.zone_id
  name            = "www.bidhouse.cloud"
  type            = "A"
  allow_overwrite = true

  alias {
    name                   = aws_cloudfront_distribution.cdn.domain_name
    zone_id                = aws_cloudfront_distribution.cdn.hosted_zone_id
    evaluate_target_health = false
  }
}

# PRIMARY ALB health check (01번 방에서 추가하거나 03번 방에서 참조)
resource "aws_route53_health_check" "primary_alb" {
  fqdn              = aws_lb.aws_alb.dns_name
  port              = 80
  type              = "HTTP"
  resource_path     = "/health"
  failure_threshold = 3
  request_interval  = 30

  tags = { Name = "bidhouse-seoul-primary-hc" }
}

# ==========================================================================
# api.bidhouse.cloud - PRIMARY dynamic backend endpoint
# Browser JavaScript and Socket.IO connect here. Route 53 fails over to Azure.
# ==========================================================================
resource "aws_route53_record" "api_primary" {
  zone_id         = data.aws_route53_zone.main.zone_id
  name            = "api.bidhouse.cloud"
  type            = "A"
  set_identifier  = "seoul-api-primary"
  allow_overwrite = true
  health_check_id = aws_route53_health_check.primary_alb.id

  alias {
    name                   = aws_lb.aws_alb.dns_name
    zone_id                = aws_lb.aws_alb.zone_id
    evaluate_target_health = true
  }

  failover_routing_policy {
    type = "PRIMARY"
  }
}

output "primary_health_check_id" {
  description = "서울 ALB Route53 헬스체크 ID - failback/promote Lambda 트리거용"
  value       = aws_route53_health_check.primary_alb.id
}
