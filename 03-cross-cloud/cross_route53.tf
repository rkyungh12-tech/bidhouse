# ============================================================================
# Route 53 SECONDARY record for Azure DR
# ============================================================================

data "aws_route53_zone" "main" {
  name         = "bidhouse.cloud."
  private_zone = false
}

resource "aws_route53_health_check" "secondary_aca" {
  fqdn              = data.terraform_remote_state.azure.outputs.container_app_fqdn
  port              = 443
  type              = "HTTPS"
  resource_path     = "/health"
  failure_threshold = 3
  request_interval  = 30

  tags = { Name = "bidhouse-azure-secondary-hc" }
}

resource "aws_route53_record" "secondary" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "api.bidhouse.cloud"
  type    = "A"
  ttl     = 60
  records = [
    data.terraform_remote_state.azure.outputs.container_app_environment_static_ip
  ]
  set_identifier  = "singapore-dr"
  health_check_id = aws_route53_health_check.secondary_aca.id

  failover_routing_policy {
    type = "SECONDARY"
  }
}

# 3. AWS Route 53에 애저 소유권 증명용 TXT 레코드 생성
resource "aws_route53_record" "azure_domain_verification" {
  zone_id         = data.aws_route53_zone.main.zone_id
  name            = "asuid.api.bidhouse.cloud"
  type            = "TXT"
  ttl             = 300
  allow_overwrite = true
  records         = [data.terraform_remote_state.azure.outputs.container_app_verification_id]
}

# ⏳ [안전장치 추가] TXT 레코드가 생성된 후, DNS가 전파될 때까지 30초 동안 대기
resource "time_sleep" "wait_for_dns_propagation" {
  depends_on = [aws_route53_record.azure_domain_verification]

  create_duration = "30s"
}

# ============================================================================
# 🔐 [필살기] Let's Encrypt DNS-01 기반 무중단 SSL 인증서 자동 발급
# ============================================================================

# 1. Let's Encrypt 가입용 개인키 생성
resource "tls_private_key" "acme_reg_key" {
  algorithm = "RSA"
}

# 2. Let's Encrypt 계정 등록
resource "acme_registration" "reg" {
  account_key_pem = tls_private_key.acme_reg_key.private_key_pem
  email_address   = "admin@bidhouse.cloud"
}

# 3. DNS-01 챌린지로 무료 인증서 발급 (Route 53 자동 조작)
resource "acme_certificate" "api_cert" {
  account_key_pem           = acme_registration.reg.account_key_pem
  common_name               = "api.bidhouse.cloud"
  certificate_p12_password  = "Bidhouse2026!#"

  dns_challenge {
    provider = "route53"
  }

  depends_on = [time_sleep.wait_for_dns_propagation]
}

# 4. 발급받은 완벽한 인증서를 Azure Container Apps 환경에 영구 등록
resource "azurerm_container_app_environment_certificate" "aca_cert" {
  name                         = "bidhouse-api-cert-letsencrypt"
  container_app_environment_id = data.terraform_remote_state.azure.outputs.container_app_environment_id
  certificate_blob_base64      = acme_certificate.api_cert.certificate_p12
  certificate_password         = acme_certificate.api_cert.certificate_p12_password
}

# 5. 최종 바인딩: 이제 인증서가 있으므로 애저가 군말 없이 도메인을 묶어줍니다!
resource "azurerm_container_app_custom_domain" "api_domain" {
  name                                     = "api.bidhouse.cloud"
  container_app_id                         = data.terraform_remote_state.azure.outputs.container_app_id
  container_app_environment_certificate_id = azurerm_container_app_environment_certificate.aca_cert.id

  # 🚀 [추가된 필수 옵션] SNI 방식으로 인증서 바인딩 명시
  certificate_binding_type                 = "SniEnabled"
}