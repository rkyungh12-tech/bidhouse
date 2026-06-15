# ============================================================================
# [01-aws-seoul-network/ses.tf] SES 도메인 인증 및 Cognito 연동
# ============================================================================

# SES 도메인 인증
resource "aws_sesv2_email_identity" "domain" {
  email_identity = "bidhouse.cloud"
}

# Route53에 DKIM 레코드 자동 추가
resource "aws_route53_record" "ses_dkim" {
  count   = 3
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "${aws_sesv2_email_identity.domain.dkim_signing_attributes[0].tokens[count.index]}._domainkey.bidhouse.cloud"
  type    = "CNAME"
  ttl     = 300
  records = ["${aws_sesv2_email_identity.domain.dkim_signing_attributes[0].tokens[count.index]}.dkim.amazonses.com"]
}