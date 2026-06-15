# ============================================================================
# 🏛️ [01-aws-seoul-network/waf.tf] AWS WAFv2 및 CAPTCHA 보안 대통합본
# ============================================================================

resource "aws_cloudwatch_log_group" "waf" {
  name              = "aws-waf-logs-bidhouse-prod-alb"
  retention_in_days = var.waf_log_retention_days

  tags = {
    Name        = "aws-waf-logs-bidhouse-prod-alb"
    Environment = "prod"
    Project     = "bidhouse"
  }
}

resource "aws_wafv2_web_acl" "alb" {
  name        = "bidhouse-prod-alb-web-acl"
  
  description = "BidHouse production ALB protection pack"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  # 🟢 [수정 완료] 회원가입 캡차 규칙
  rule {
    name     = "EnforceCaptchaOnRegister"
    priority = 0 

    action {
      count  {} 
    }

    statement {
      byte_match_statement {
        search_string = "/api/auth/register"
        field_to_match {
          uri_path {}
        }
        text_transformation {
          priority = 0
          type     = "LOWERCASE" 
        }
        positional_constraint = "EXACTLY"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RegisterCaptchaMetric"
      sampled_requests_enabled   = true
    }
  }

  # 알려진 악성 IP 평판 목록
  rule {
    name     = "AWSManagedRulesAmazonIpReputationList"
    priority = 10
    override_action {
      count {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "bidhouse-prod-amazon-ip-reputation"
      sampled_requests_enabled   = true
    }
  }

  # 알려진 비정상 입력 패턴
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 20
    override_action {
      count {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "bidhouse-prod-known-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  # 일반적인 웹 공격 패턴
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 30
    override_action {
      count {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "bidhouse-prod-common-rule-set"
      sampled_requests_enabled   = true
    }
  }

  # IP Rate Limit (초과 시 차단)
  rule {
    name     = "bidhouse-prod-ip-rate-limit"
    priority = 100
    action {
      block {}
    }
    statement {
      rate_based_statement {
        aggregate_key_type = "IP"
        limit              = var.waf_rate_limit_requests_per_5_minutes
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "bidhouse-prod-ip-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "bidhouse-prod-alb-web-acl"
    sampled_requests_enabled   = true
  }

  tags = {
    Name        = "bidhouse-prod-alb-web-acl"
    Environment = "prod"
    Project     = "bidhouse"
  }
}

resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = aws_lb.aws_alb.arn
  web_acl_arn  = aws_wafv2_web_acl.alb.arn
}

resource "aws_wafv2_web_acl_logging_configuration" "alb" {
  log_destination_configs = [replace(aws_cloudwatch_log_group.waf.arn, ":*", "")]
  resource_arn            = aws_wafv2_web_acl.alb.arn
  depends_on              = [aws_cloudwatch_log_group.waf]
}

