# ============================================================================
# Azure Container Apps DR application
# ============================================================================

resource "azurerm_container_app_environment" "aca_env" {
  name                       = "${var.prefix}-aca-env"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  infrastructure_subnet_id   = azurerm_subnet.container_app_subnet.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id

  lifecycle {
    ignore_changes = [
      infrastructure_subnet_id,
      infrastructure_resource_group_name
    ]
  }
}

locals {
  azure_app_uses_placeholder = var.azure_app_image_tag == "placeholder"
  azure_app_image            = local.azure_app_uses_placeholder ? "mcr.microsoft.com/azuredocs/aci-helloworld:latest" : "${azurerm_container_registry.acr.login_server}/bidhouse-prod-app:${var.azure_app_image_tag}"
  azure_app_target_port      = local.azure_app_uses_placeholder ? 80 : 3000
}


resource "azurerm_container_app" "app" {
  name                         = "${var.prefix}-app"
  container_app_environment_id = azurerm_container_app_environment.aca_env.id
  resource_group_name          = azurerm_resource_group.rg.name
  revision_mode                = "Multiple"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aca.id]
  }

  registry {
    server   = azurerm_container_registry.acr.login_server
    identity = azurerm_user_assigned_identity.aca.id
  }

  secret {
    name                = "db-user"
    identity            = azurerm_user_assigned_identity.aca.id
    key_vault_secret_id = azurerm_key_vault_secret.mysql_admin_username.versionless_id
  }

  secret {
    name                = "db-password"
    identity            = azurerm_user_assigned_identity.aca.id
    key_vault_secret_id = azurerm_key_vault_secret.mysql_admin_password.versionless_id
  }

  secret {
    name                = "jwt-secret"
    identity            = azurerm_user_assigned_identity.aca.id
    key_vault_secret_id = azurerm_key_vault_secret.jwt_secret.versionless_id
  }

  secret {
    name                = "initial-admin-username"
    identity            = azurerm_user_assigned_identity.aca.id
    key_vault_secret_id = azurerm_key_vault_secret.initial_admin_username.versionless_id
  }

  secret {
    name                = "initial-admin-password"
    identity            = azurerm_user_assigned_identity.aca.id
    key_vault_secret_id = azurerm_key_vault_secret.initial_admin_password.versionless_id
  }

  secret {
    name                = "initial-admin-email"
    identity            = azurerm_user_assigned_identity.aca.id
    key_vault_secret_id = azurerm_key_vault_secret.initial_admin_email.versionless_id
  }
  secret {
    name                 = "aws-access-key-id"
    identity             = azurerm_user_assigned_identity.aca.id
    key_vault_secret_id  = azurerm_key_vault_secret.aws_access_key.versionless_id
  }

  secret {
    name                 = "aws-secret-access-key"
    identity             = azurerm_user_assigned_identity.aca.id
    key_vault_secret_id  = azurerm_key_vault_secret.aws_secret_key.versionless_id
  }

  template {
    container {
      name   = "bidhouse-dr-app"
      image  = local.azure_app_image
      cpu    = "0.25"
      memory = "0.5Gi"

      env {
        name  = "NODE_ENV"
        value = "production"
      }

      env {
        name  = "PORT"
        value = "3000"
      }

      env {
        name  = "DB_HOST"
        value = azurerm_mysql_flexible_server.mysql.fqdn
      }

      env {
        name  = "DB_PORT"
        value = "3306"
      }

      env {
        name  = "DB_NAME"
        value = azurerm_mysql_flexible_database.auction.name
      }

      env {
        name  = "DB_SSL"
        value = "true"
      }

      env {
        name  = "FRONTEND_ORIGIN"
        value = "https://www.bidhouse.cloud,https://dr.bidhouse.cloud"
      }
      # 🔥 [추가] 지역 정보 환경변수
      env {
        name  = "APP_REGION"
        value = "singapore"
      }

      env {
        name        = "DB_USER"
        secret_name = "db-user"
      }

      env {
        name        = "DB_PASSWORD"
        secret_name = "db-password"
      }

      env {
        name        = "JWT_SECRET"
        secret_name = "jwt-secret"
      }

      env {
        name        = "INITIAL_ADMIN_USERNAME"
        secret_name = "initial-admin-username"
      }

      env {
        name        = "INITIAL_ADMIN_PASSWORD"
        secret_name = "initial-admin-password"
      }

      env {
        name        = "INITIAL_ADMIN_EMAIL"
        secret_name = "initial-admin-email"
      }
      env {
        name  = "AUCTION_CLOSE_QUEUE_URL"
        value = "https://sqs.ap-northeast-2.amazonaws.com/811688201568/bidhouse-auction-close.fifo"
      }

      env {
        name        = "AWS_ACCESS_KEY_ID"
        secret_name = "aws-access-key-id"
      }
      env {
        name        = "AWS_SECRET_ACCESS_KEY"
        secret_name = "aws-secret-access-key"
      }
      env {
        name  = "AWS_REGION"
        value = "ap-northeast-2"
      }

      env {
        name  = "COGNITO_CLIENT_ID"
        value = var.cognito_client_id
      }

      env {
        name  = "COGNITO_USER_POOL_ID"
        value = var.cognito_user_pool_id
      }
      

      # 🔥 [추가] 애저가 제대로 된 주소로 건강검진을 하도록 길잡이 침반 장착
      readiness_probe {
        transport        = "HTTP"
        port             = local.azure_app_target_port
        path             = "/health"
        interval_seconds = 10
      }

      liveness_probe {
        transport        = "HTTP"
        port             = local.azure_app_target_port
        path             = "/health"
        interval_seconds = 10
      }

      startup_probe {
        transport               = "HTTP"
        port                    = local.azure_app_target_port
        path                    = "/health"
        interval_seconds        = 15
        failure_count_threshold = 10  # 최초 부팅 시 최대 150초까지 차분히 기다려 줍니다.
      }
    }

    min_replicas = 1
    max_replicas = 1
  }

  ingress {
    allow_insecure_connections = true
    external_enabled           = true
    target_port                = local.azure_app_target_port

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  depends_on = [
    time_sleep.wait_for_aca_rbac,
    azurerm_key_vault_secret.mysql_admin_username,
    azurerm_key_vault_secret.mysql_admin_password,
    azurerm_key_vault_secret.jwt_secret,
    azurerm_mysql_flexible_database.auction
  ]
}
# 도메인 바인딩 설정 추가
#resource "azurerm_container_app_custom_domain" "app_domain" {
#  name                         = "dr.bidhouse.cloud" # DR 환경 도메인
#  container_app_id             = azurerm_container_app.app.id
#  certificate_binding_type     = "SniEnabled"
#  # 인증서 ID가 있다면 이곳에 연결 (없다면 먼저 KeyVault에서 인증서 생성 후 참조)
# certificate_id             = azurerm_container_app_certificate.cert.id 
#}




output "container_app_environment_id" {
  value       = azurerm_container_app_environment.aca_env.id
  description = "Container App Environment ID"
}

output "container_app_fqdn" {
  value       = azurerm_container_app.app.ingress[0].fqdn
  description = "Azure Container App public FQDN"
}

output "container_app_environment_static_ip" {
  value       = azurerm_container_app_environment.aca_env.static_ip_address
  description = "Azure Container Apps Environment static public ingress IPv4"
}

output "container_app_verification_id" {
  value       = azurerm_container_app.app.custom_domain_verification_id
  description = "Domain verification code for Azure Container App"
  sensitive   = true
}

# ⭐ [추가 2] 03번 방이 가져가서 도메인을 묶어줄 컨테이너 앱의 진짜 주민번호 ID
output "container_app_id" {
  value       = azurerm_container_app.app.id
  description = "Azure Container App Resource ID"
}