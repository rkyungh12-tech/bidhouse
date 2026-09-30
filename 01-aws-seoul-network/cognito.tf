# ============================================================================
# [01-aws-seoul-network/cognito.tf]
# BidHouse 웹 인증용 Amazon Cognito User Pool
#
# 현재 ALB에는 HTTP 80 리스너만 있으므로 Cognito 리소스만 먼저 생성합니다.
# ALB 레벨 로그인 강제 적용은 ACM 인증서와 HTTPS 443 리스너를 추가한 뒤 진행합니다.
# ============================================================================

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  cognito_domain_prefix = "bidhouse-prod-${data.aws_caller_identity.current.account_id}"
}



resource "aws_cognito_user_pool" "web" {
  
  name = "bidhouse-prod-web-user-pool"
  lifecycle {
    ignore_changes = [
      schema,
      password_policy,
      tags
    ]
  }
  

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
    email_subject        = "[BidHouse] 이메일 인증 코드"
    email_message        = <<-HTML
      <!DOCTYPE html>
      <html lang="ko">
        <body style="font-family:sans-serif;max-width:480px;margin:0 auto;padding:24px">
          <h2 style="color:#1a1a1a">BidHouse 이메일 인증</h2>
          <p style="color:#444">아래 인증 코드를 입력해 주세요.</p>
          <div style="font-size:32px;font-weight:bold;letter-spacing:8px;color:#1D9E75;padding:16px 0">{####}</div>
          <p style="color:#888;font-size:13px">본 메일은 발신 전용입니다.</p>
        </body>
      </html>
    HTML
  }

  password_policy {
    minimum_length                   = 12
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    require_uppercase                = true
    temporary_password_validity_days = 7
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  user_attribute_update_settings {
    attributes_require_verification_before_update = ["email"]
  }

  schema {
  name                = "userId"
  attribute_data_type = "Number"
  mutable             = true
  }

  schema {
    name                = "role"
    attribute_data_type = "String"
    mutable             = true
  }

  tags = {
    Name        = "bidhouse-prod-web-user-pool"
    Environment = "prod"
    Project     = "bidhouse"
  }
}

# Cognito Hosted UI 또는 Managed Login 도메인
resource "aws_cognito_user_pool_domain" "web" {
  domain       = local.cognito_domain_prefix
  user_pool_id = aws_cognito_user_pool.web.id
}

# --------------------------------------------------------------------------
# 1) 브라우저 앱 직접 연동용 공개 클라이언트
# - SPA 또는 프론트엔드에서 Authorization Code + PKCE 방식으로 사용할 수 있습니다.
# - 브라우저에 Client Secret을 노출하면 안 되므로 generate_secret = false 입니다.
# --------------------------------------------------------------------------
resource "aws_cognito_user_pool_client" "spa" {
  name         = "bidhouse-prod-spa-client"
  user_pool_id = aws_cognito_user_pool.web.id

  generate_secret = false

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  callback_urls                        = var.cognito_spa_callback_urls
  logout_urls                          = var.cognito_spa_logout_urls
  supported_identity_providers         = ["COGNITO"]

  explicit_auth_flows = [
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_USER_PASSWORD_AUTH"
  ]


  

  prevent_user_existence_errors = "ENABLED"
  enable_token_revocation       = true
}

# --------------------------------------------------------------------------
# 2) ALB authenticate-cognito 연동용 비밀 클라이언트
# - 추후 HTTPS 443 Listener를 추가한 뒤 ALB Listener Rule에서 사용합니다.
# - ALB 인증 연동은 Client Secret과 Authorization Code Grant가 필요합니다.
# --------------------------------------------------------------------------
resource "aws_cognito_user_pool_client" "alb" {
  name         = "bidhouse-prod-alb-client"
  user_pool_id = aws_cognito_user_pool.web.id

  generate_secret = true

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  callback_urls = [
    "https://${aws_lb.aws_alb.dns_name}/oauth2/idpresponse"
  ]
  logout_urls = [
    "https://${aws_lb.aws_alb.dns_name}/"
  ]
  supported_identity_providers = ["COGNITO"]

  explicit_auth_flows = [
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH"
  ]

  prevent_user_existence_errors = "ENABLED"
  enable_token_revocation       = true
}

