# ============================================================================
# CloudWatch Logs - VPC Flow Logs
# ============================================================================

resource "aws_cloudwatch_log_group" "vpc_flow_prod" {
  name              = "/aws/vpc-flow/bidhouse-prod-vpc"
  retention_in_days = 30

  tags = {
    Name        = "bidhouse-prod-vpc-flow-logs"
    Environment = "prod"
    Project     = "bidhouse"
    Purpose     = "Network traffic audit for production VPC"
  }
}

resource "aws_cloudwatch_log_group" "vpc_flow_mgmt" {
  name              = "/aws/vpc-flow/bidhouse-mgmt-vpc"
  retention_in_days = 30

  tags = {
    Name        = "bidhouse-mgmt-vpc-flow-logs"
    Environment = "prod"
    Project     = "bidhouse"
    Purpose     = "Network traffic audit for management VPC"
  }
}

resource "aws_iam_role" "vpc_flow_logs" {
  name = "bidhouse-vpc-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "vpc_flow_logs" {
  name = "bidhouse-vpc-flow-logs-policy"
  role = aws_iam_role.vpc_flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_flow_log" "prod_vpc" {
  log_destination          = aws_cloudwatch_log_group.vpc_flow_prod.arn
  iam_role_arn             = aws_iam_role.vpc_flow_logs.arn
  traffic_type             = "ALL"
  vpc_id                   = data.aws_vpc.prod_vpc.id
  max_aggregation_interval = 60

  tags = {
    Name        = "bidhouse-prod-vpc-flow-log"
    Environment = "prod"
    Project     = "bidhouse"
  }
}

resource "aws_flow_log" "mgmt_vpc" {
  log_destination          = aws_cloudwatch_log_group.vpc_flow_mgmt.arn
  iam_role_arn             = aws_iam_role.vpc_flow_logs.arn
  traffic_type             = "ALL"
  vpc_id                   = aws_vpc.mgmt_vpc.id
  max_aggregation_interval = 60

  tags = {
    Name        = "bidhouse-mgmt-vpc-flow-log"
    Environment = "prod"
    Project     = "bidhouse"
  }
}


# ============================================================================
# CloudWatch Logs - RDS MySQL Logs
# ============================================================================

resource "aws_cloudwatch_log_group" "rds_error" {
  name              = "/aws/rds/instance/bidhouse-prod-mysql/error"
  retention_in_days = 30

  tags = {
    Name        = "bidhouse-rds-error-logs"
    Environment = "prod"
    Project     = "bidhouse"
    Purpose     = "RDS MySQL error logs"
  }
}

resource "aws_cloudwatch_log_group" "rds_slowquery" {
  name              = "/aws/rds/instance/bidhouse-prod-mysql/slowquery"
  retention_in_days = 30

  tags = {
    Name        = "bidhouse-rds-slowquery-logs"
    Environment = "prod"
    Project     = "bidhouse"
    Purpose     = "RDS MySQL slow query logs"
  }
}


# ============================================================================
# CloudWatch Logs - Route 53 Public Hosted Zone Query Logs
# Route 53 public query logs require us-east-1 CloudWatch Logs.
# ============================================================================

resource "aws_cloudwatch_log_group" "route53_public_query" {
  provider          = aws.us_east_1
  name              = "/aws/route53/bidhouse-cloud"
  retention_in_days = 30

  tags = {
    Name        = "bidhouse-route53-public-query-logs"
    Environment = "prod"
    Project     = "bidhouse"
    Purpose     = "Public DNS query logs for bidhouse.cloud"
  }
}

resource "aws_cloudwatch_log_resource_policy" "route53_public_query" {
  provider    = aws.us_east_1
  policy_name = "bidhouse-route53-query-logging-policy"

  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "route53.amazonaws.com"
        }
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "${aws_cloudwatch_log_group.route53_public_query.arn}",
          "${aws_cloudwatch_log_group.route53_public_query.arn}:*"
        ]
      }
    ]
  })
}

resource "aws_route53_query_log" "main_zone" {
  zone_id                  = data.aws_route53_zone.main.zone_id
  cloudwatch_log_group_arn = aws_cloudwatch_log_group.route53_public_query.arn

  depends_on = [
    aws_cloudwatch_log_resource_policy.route53_public_query
  ]
}