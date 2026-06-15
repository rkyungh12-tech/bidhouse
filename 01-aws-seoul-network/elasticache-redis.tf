# ============================================================
# BidHouse Socket.IO scale-out Redis OSS
# ------------------------------------------------------------
# Purpose:
# - Provide a shared Pub/Sub backend for multiple Socket.IO ECS tasks.
# - Keep Redis private inside the production VPC.
# - Allow TCP/6379 access only from the ECS task security group.
# ============================================================

resource "aws_elasticache_subnet_group" "socketio_redis" {
  name = "bidhouse-prod-socketio-redis-subnets"

  subnet_ids = [
    aws_subnet.prod_private_a.id,
    aws_subnet.prod_private_c.id
  ]

  tags = {
    Name = "bidhouse-prod-socketio-redis-subnets"
  }
}

resource "aws_security_group" "socketio_redis" {
  name        = "bidhouse-prod-socketio-redis-sg"
  description = "Allow Redis OSS access only from BidHouse ECS tasks"
  vpc_id      = aws_vpc.prod_vpc.id

  tags = {
    Name = "bidhouse-prod-socketio-redis-sg"
  }
}

resource "aws_security_group_rule" "ecs_to_socketio_redis_6379" {
  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs_task.id
  security_group_id        = aws_security_group.socketio_redis.id
  description              = "Allow ECS tasks to connect to Socket.IO Redis OSS"
}

resource "random_password" "socketio_redis_auth_token" {
  length  = 64
  special = false
}

resource "aws_secretsmanager_secret" "socketio_redis_auth" {
  name                    = "bidhouse/prod/socketio-redis-auth"
  recovery_window_in_days = 0

  tags = {
    Name = "bidhouse-prod-socketio-redis-auth"
  }
  lifecycle {
    ignore_changes = all
  }
}

resource "aws_secretsmanager_secret_version" "socketio_redis_auth" {
  secret_id = aws_secretsmanager_secret.socketio_redis_auth.id
  secret_string = jsonencode({
    REDIS_AUTH_TOKEN = random_password.socketio_redis_auth_token.result
  })
}

resource "aws_elasticache_replication_group" "socketio_redis" {
  replication_group_id = "bidhouse-prod-socketio-redis"
  description          = "Redis OSS Pub/Sub backend for BidHouse Socket.IO scale-out"

  engine             = "redis"
  node_type          = var.socketio_redis_node_type
  port               = 6379
  num_cache_clusters = 2

  automatic_failover_enabled = true
  multi_az_enabled            = true

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                 = random_password.socketio_redis_auth_token.result

  subnet_group_name  = aws_elasticache_subnet_group.socketio_redis.name
  security_group_ids = [aws_security_group.socketio_redis.id]

  apply_immediately = true

  tags = {
    Name = "bidhouse-prod-socketio-redis"
    Role = "socketio-pubsub"
  }
}

# elasticache-redis.tf에 추가
resource "aws_security_group_rule" "socketio_redis_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.socketio_redis.id
  description       = "Allow outbound traffic from Redis"
}
