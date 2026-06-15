# ============================================================================
# [01-aws-seoul-network/rds.tf] Bidhouse RDS MySQL 본진 완공 및 통합 출력 장부
# ============================================================================

locals {
  bidhouse_rds_name_prefix = "bidhouse-prod"
  # 🔐 ecs.tf 파일의 Task 실행 역할이 수급해 갈 마스터 암호 고유 주소(ARN) 경로 확정
  rds_master_secret_arn = aws_db_instance.auction_mysql.master_user_secret[0].secret_arn
}

# 🎰 [기존 보존] 기존 자산들과의 완벽한 하위 호환성을 위해 난수 기계를 그대로 유지합니다.
resource "random_string" "rds_hint" {
  length  = 4
  special = false
  upper   = false
}

# 📦 [기존 보존] push할 때 기존에 생성된 서브넷 그룹이 파괴되지 않도록 난수 이름을 유지합니다.
resource "aws_db_subnet_group" "auction_mysql" {
  name = "bidhouse-prod-mysql-subnet-group-${random_string.rds_hint.result}"

  subnet_ids = [
    aws_subnet.prod_public.id,
    aws_subnet.prod_public_2.id
  ]

  tags = {
    name = "bidhouse-prod-mysql-subnet-group-${random_string.rds_hint.result}"
  }
}

# 🛡️ [보안 강화] ECS Task 보안 그룹과 완벽하게 매핑된 데이터베이스 방화벽
resource "aws_security_group" "rds_mysql" {
  name        = "${local.bidhouse_rds_name_prefix}-mysql-sg"
  description = "Allow MySQL traffic from Bidhouse ECS tasks only"
  vpc_id      = aws_vpc.prod_vpc.id

  # 🚀 [추가된 부분] CodeBuild(외부)에서 MySQL 명령어를 칠 수 있도록 3306 포트 전면 개방
  ingress {
    description = "Allow public access for CodeBuild pipeline"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description     = "MySQL from ECS tasks"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_task.id] # ecs-task-security-group.tf와 직결
  }

  
  ingress {
    description     = "MySQL from Bastion EC2"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }

  # Azure MySQL Flexible Server가 VPN을 통해 AWS RDS binlog를 읽도록 허용
  ingress {
    description = "MySQL replication from Azure MySQL delegated subnet"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["10.3.0.0/16"]
  }

  egress {
    description = "Allow outbound traffic from RDS"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.bidhouse_rds_name_prefix}-mysql-sg"
  }
}

# 🎯 [★핵심 결착] identifier(식별자 ID)와 주소가 더 이상 배포마다 바뀌지 않도록 완전히 고정합니다!
# 이 조치를 통해 앞으로 아무리 push를 연타해도 테라폼이 기존 DB를 파괴하지 않고 안전하게 유지합니다.
resource "aws_db_instance" "auction_mysql" {
  identifier = "${local.bidhouse_rds_name_prefix}-mysql"

  engine         = "mysql"
  engine_version = "8.0"   
  instance_class = var.rds_instance_class

  allocated_storage = var.rds_allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true
  kms_key_id = aws_kms_key.rds.arn

  db_name  = var.rds_db_name
  username = var.rds_master_username

  # RDS가 마스터 비밀번호를 생성하고 Secrets Manager에서 관리합니다.
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.auction_mysql.name
  vpc_security_group_ids = [aws_security_group.rds_mysql.id]
  publicly_accessible    = true  

  multi_az                  = var.rds_multi_az
  parameter_group_name = aws_db_parameter_group.mysql_binlog.name
  backup_retention_period   = 7
  deletion_protection       = var.rds_deletion_protection
  skip_final_snapshot       = var.rds_skip_final_snapshot
  final_snapshot_identifier = var.rds_skip_final_snapshot ? null : "${local.bidhouse_rds_name_prefix}-mysql-final"

  apply_immediately = true

  tags = {
    Name = "${local.bidhouse_rds_name_prefix}-mysql"
  }
}

resource "aws_db_parameter_group" "mysql_binlog" {
  name   = "bidhouse-prod-mysql-binlog"
  family = "mysql8.0"   

  parameter {
    name  = "binlog_format"
    value = "ROW"
    apply_method = "immediate"
  }

  parameter {
    name  = "binlog_row_image"
    value = "FULL"
    apply_method = "immediate"
  }

  parameter {
    name  = "log_bin_trust_function_creators"
    value = "1"
    apply_method = "immediate"
  }
}

# ============================================================================
# 📊 [통합 출력 장부] ECS Task Definition과 애플리케이션에서 사용할 출력값
# ============================================================================

output "rds_endpoint" {
  description = "Node.js DB_HOST 값"
  value       = aws_db_instance.auction_mysql.address
}

output "rds_port" {
  description = "Node.js DB_PORT 값"
  value       = aws_db_instance.auction_mysql.port
}

output "rds_database_name" {
  description = "Node.js DB_NAME 값"
  value       = var.rds_db_name
}

output "rds_master_secret_arn" {
  description = "RDS가 Secrets Manager에서 관리하는 마스터 계정 Secret ARN"
  value       = local.rds_master_secret_arn
}

output "ecs_task_security_group_id" {
  description = "ECS Service의 Task ENI에 연결할 Security Group ID"
  value       = aws_security_group.ecs_task.id
}

output "ecs_execution_read_app_secrets_policy_arn" {
  description = "ECS Task Execution Role에 연결할 IAM Policy ARN"
  value       = aws_iam_policy.ecs_execution_read_app_secrets.arn
}

output "ecs_container_environment" {
  description = "ECS Task Definition containerDefinitions.environment에 넣을 일반 환경 변수"
  value = [
    {
      name  = "DB_HOST"
      value = aws_db_instance.auction_mysql.address
    },
    {
      name  = "DB_PORT"
      value = tostring(aws_db_instance.auction_mysql.port)
    },
    {
      name  = "DB_NAME"
      value = var.rds_db_name
    }
  ]
}

output "ecs_container_secrets" {
  description = "ECS Task Definition containerDefinitions.secrets에 넣을 Secret 참조"
  value = [
    {
      name      = "DB_USER"
      valueFrom = "${local.rds_master_secret_arn}:username::"
    },
    {
      name      = "DB_PASSWORD"
      valueFrom = "${local.rds_master_secret_arn}:password::"
    }
  ]
}