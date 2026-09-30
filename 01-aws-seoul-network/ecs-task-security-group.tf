# ============================================================================
# ECS Task 기본 Security Group
# RDS SG가 허용할 출발지 SG입니다.
# ALB -> ECS:3000 인바운드 규칙은 ALB SG가 작성된 뒤 추가합니다.
# ============================================================================

resource "aws_security_group" "ecs_task" {
  name        = "bidhouse-prod-ecs-task-sg"
  description = "Base security group for Bidhouse ECS tasks"
  vpc_id      = data.aws_vpc.prod_vpc.id

  egress {
    description = "Allow outbound traffic from ECS tasks"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "bidhouse-prod-ecs-task-sg"
  }
}
