# ============================================================================
# AWS Secrets Manager: RDS managed secret + application runtime secrets
# ============================================================================

resource "aws_secretsmanager_secret" "app_config" {
  name                    = "bidhouse/prod/app-config-v4"
  recovery_window_in_days = 0
}

resource "random_password" "jwt_secret" {
  length  = 64
  special = false
}

resource "random_password" "initial_admin_password" {
  length           = 24
  special          = true
  override_special = "!#%_-"
}

resource "aws_secretsmanager_secret_version" "app_config" {
  secret_id = aws_secretsmanager_secret.app_config.id
  secret_string = jsonencode({
    JWT_SECRET             = random_password.jwt_secret.result
    INITIAL_ADMIN_USERNAME = "admin"
    INITIAL_ADMIN_PASSWORD = random_password.initial_admin_password.result
    INITIAL_ADMIN_EMAIL    = "admin@bidhouse.local"
  })
}

data "aws_iam_policy_document" "ecs_execution_read_app_secrets" {
  statement {
    sid = "ReadBidhouseRuntimeSecrets"

    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]

    resources = [
      local.rds_master_secret_arn,
      aws_secretsmanager_secret.app_config.arn,
      aws_secretsmanager_secret.socketio_redis_auth.arn
    ]
  }
}

resource "aws_iam_policy" "ecs_execution_read_app_secrets" {
  name        = "${local.bidhouse_rds_name_prefix}-ecs-read-app-secrets"
  description = "Allow ECS task execution role to inject RDS and application secrets"
  policy      = data.aws_iam_policy_document.ecs_execution_read_app_secrets.json
}
