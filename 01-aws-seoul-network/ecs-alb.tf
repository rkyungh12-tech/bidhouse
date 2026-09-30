# ==========================================================================
# 🎯 [01-aws-seoul-network/ecs-alb.tf] 타겟 그룹 및 리스너 룰 본진 이사 (중복 제거본)
# ==========================================================================

# 1. ECS 앱 전용 타겟 그룹 생성
resource "aws_lb_target_group" "ecs_app" {
  name        = "bidhouse-prod-ecs-app-tg"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.prod_vpc.id # vpc.tf 본체 다이렉트 참조
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
    matcher             = "200"
  }

  # Socket.IO HTTP long-polling requests must keep reaching the same ECS task.
  # Redis Adapter shares broadcasts between tasks, but it does not replace stickiness.
  stickiness {
    type            = "lb_cookie"
    enabled         = true
    cookie_duration = 86400
  }

  tags = { Name = "bidhouse-prod-ecs-app-tg" }
}

# 2. 방화벽 개통 (구형 ALB SG -> ECS Task SG 통로 연결)
resource "aws_security_group_rule" "alb_to_ecs_3000" {
  type                     = "ingress"
  from_port                = 3000
  to_port                  = 3000
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb_sg.id
  security_group_id        = aws_security_group.ecs_task.id
  description              = "Allow ALB to reach ECS auction app on port 3000"
}

# 3. 기존 HTTP Listener(80번)의 모든 경로를 이 ECS 타겟 그룹으로 토스하는 단일 고속도로 개통
resource "aws_lb_listener_rule" "ecs_app_all_paths" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecs_app.arn
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }
}
# 4. HTTPS listener for api.bidhouse.cloud
# Existing HTTP listener remains for health checks and compatibility.
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.aws_alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.api.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecs_app.arn
  }
}
