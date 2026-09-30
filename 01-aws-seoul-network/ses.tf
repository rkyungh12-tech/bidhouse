# ses.tf - 이것만 남기기
resource "aws_sesv2_email_identity" "domain" {
  email_identity = "bidhouse.cloud"
}

resource "aws_route53_record" "ses_dkim" {
  count   = 3
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "${aws_sesv2_email_identity.domain.dkim_signing_attributes[0].tokens[count.index]}._domainkey.bidhouse.cloud"
  type    = "CNAME"
  ttl     = 300
  records = ["${aws_sesv2_email_identity.domain.dkim_signing_attributes[0].tokens[count.index]}.dkim.amazonses.com"]
}

resource "aws_sesv2_email_identity_mail_from_attributes" "domain" {
  email_identity   = aws_sesv2_email_identity.domain.email_identity
  mail_from_domain = "mail.bidhouse.cloud"
}

resource "aws_route53_record" "ses_mail_from_mx" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "mail.bidhouse.cloud"
  type    = "MX"
  ttl     = 300
  records = ["10 feedback-smtp.ap-northeast-2.amazonses.com"]
}

resource "aws_route53_record" "ses_mail_from_spf" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "mail.bidhouse.cloud"
  type    = "TXT"
  ttl     = 300
  records = ["v=spf1 include:amazonses.com ~all"]
}

data "aws_caller_identity" "current_ses" {}

resource "aws_sesv2_email_identity_policy" "cognito_send" {
  email_identity = aws_sesv2_email_identity.domain.email_identity
  policy_name    = "CognitoSendPolicy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowCognitoToSendEmail"
      Effect = "Allow"
      Principal = {
        Service = "cognito-idp.amazonaws.com"
      }
      Action   = "ses:SendEmail"
      Resource = "arn:aws:ses:ap-northeast-2:${data.aws_caller_identity.current_ses.account_id}:identity/bidhouse.cloud"
    }]
  })
}