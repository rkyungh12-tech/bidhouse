# ============================================================================
# 🏛️ [01번 방 단독 마스터] 01-aws-seoul-network/ecs.tf (원클릭 제로베이스 완공본)
# ============================================================================

# 1. ECS Fargate 클러스터 사령부 개설
resource "aws_ecs_cluster" "smoke" {
  name = "bidhouse-prod-cluster"
}

# 2. 컨테이너 명세서 (Task Definition) 장전
resource "aws_ecs_task_definition" "app" {
  family                   = "bidhouse-prod-app"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"

  cpu    = "256"
  memory = "512"

  # 같은 방(01번)에 있는 ecs-iam.tf 권한 직접 상속
  execution_role_arn = aws_iam_role.ecs_task_execution.arn
  task_role_arn      = aws_iam_role.ecs_task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name = "bidhouse-smoke-app"
      # 순정 ecr.tf 저장소 주소 다이렉트 참조
      image     = "${aws_ecr_repository.app.repository_url}:${var.app_image_tag}"
      essential = true

      portMappings = [
        {
          containerPort = 3000
          hostPort      = 3000
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "NODE_ENV"
          value = "production"
        },
        # 🔥 [추가] 지역 정보 환경변수
        {
          name  = "APP_REGION"
          value = "seoul"
        },
        {
          name  = "PORT"
          value = "3000"
        },
        # 🔗 [억까 해결] 원격 장부 대신 같은 방 rds.tf 자산 직접 대입!
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
          value = aws_db_instance.auction_mysql.db_name
        },
        {
          name  = "FRONTEND_ORIGIN"
          value = "https://www.bidhouse.cloud"
        },
        {
          name  = "REDIS_ENABLED"
          value = "true"
        },
        {
          name  = "REDIS_HOST"
          value = aws_elasticache_replication_group.socketio_redis.primary_endpoint_address
        },
        {
          name  = "REDIS_PORT"
          value = tostring(aws_elasticache_replication_group.socketio_redis.port)
        },
        {
          name  = "REDIS_TLS"
          value = "true"
        },
        {
          name  = "AUCTION_CLOSE_QUEUE_URL"
          value = "https://sqs.ap-northeast-2.amazonaws.com/${data.aws_caller_identity.current.account_id}/bidhouse-auction-close.fifo"
        },
        {
          name  = "AWS_REGION"
          value = "ap-northeast-2"
        },
        {
          name  = "COGNITO_USER_POOL_ID"
          value = aws_cognito_user_pool.web.id
        },
        {
          name  = "COGNITO_CLIENT_ID"
          value = aws_cognito_user_pool_client.spa.id
        },
        {
          name  = "DB_SSL"
          value = "true"
        },
        {
          name  = "S3_IMAGES_BUCKET"
          value = var.s3_images_bucket_name
        }
      ]

      # 🔐 AWS Secrets Manager 본진 비밀번호 직접 연동
      secrets = [
        {
          name      = "DB_USER"
          valueFrom = "${local.rds_master_secret_arn}:username::"
        },
        {
          name      = "DB_PASSWORD"
          valueFrom = "${local.rds_master_secret_arn}:password::"
        },
        {
          name      = "JWT_SECRET"
          valueFrom = "${aws_secretsmanager_secret.app_config.arn}:JWT_SECRET::"
        },
        {
          name      = "INITIAL_ADMIN_USERNAME"
          valueFrom = "${aws_secretsmanager_secret.app_config.arn}:INITIAL_ADMIN_USERNAME::"
        },
        {
          name      = "INITIAL_ADMIN_PASSWORD"
          valueFrom = "${aws_secretsmanager_secret.app_config.arn}:INITIAL_ADMIN_PASSWORD::"
        },
        {
          name      = "INITIAL_ADMIN_EMAIL"
          valueFrom = "${aws_secretsmanager_secret.app_config.arn}:INITIAL_ADMIN_EMAIL::"
        },
        {
          name      = "REDIS_AUTH_TOKEN"
          valueFrom = "${aws_secretsmanager_secret.socketio_redis_auth.arn}:REDIS_AUTH_TOKEN::"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/bidhouse-prod"
          awslogs-region        = "ap-northeast-2"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  depends_on = [
    aws_iam_role_policy_attachment.ecs_task_execution_default,
    aws_iam_role_policy_attachment.ecs_task_execution_secrets,
    aws_secretsmanager_secret_version.app_config,
    aws_secretsmanager_secret_version.socketio_redis_auth
  ]
}


# 3. 실시간 컨테이너 기동 사령부 (ECS Service) 완공
resource "aws_ecs_service" "app" {
  name            = "bidhouse-prod-service"
  cluster         = aws_ecs_cluster.smoke.id
  task_definition = aws_ecs_task_definition.app.arn

  desired_count    = 0
  launch_type      = "FARGATE"
  platform_version = "1.4.0"


  lifecycle {
    ignore_changes = [desired_count]
  }

  network_configuration {
    # ECS Task는 외부에 직접 노출하지 않고 Private Subnet에서 실행합니다.
    subnets = [
      aws_subnet.prod_private_a.id,
      aws_subnet.prod_private_c.id
    ]

    # ALB -> ECS:3000 통신과 ECS -> RDS:3306 통신에 사용하는 보안 그룹
    security_groups = [aws_security_group.ecs_task.id]

    # 외부 통신은 Public IP가 아니라 NAT Gateway를 통해 수행합니다.
    assign_public_ip = false
  }

  load_balancer {
    # 🎯 04번 방에 있는 ecs-alb.tf의 진짜 ECS 타겟 그룹 이름표 조준
    target_group_arn = aws_lb_target_group.ecs_app.arn
    container_name   = "bidhouse-smoke-app"
    container_port   = 3000
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # Private Subnet과 NAT 기본 경로가 연결된 후 ECS Service를 생성합니다.
  depends_on = [
    aws_route_table_association.prod_pri_a,
    aws_route_table_association.prod_pri_c
  ]
}

# ============================================================================
# 📊 [출력 장부] 이름표 일치 완공
# ============================================================================

output "ecs_cluster_name" {
  value = aws_ecs_cluster.smoke.name
}

output "ecs_service_name" {
  value = aws_ecs_service.app.name
}

output "ecs_task_definition_arn" {
  value = aws_ecs_task_definition.app.arn
}