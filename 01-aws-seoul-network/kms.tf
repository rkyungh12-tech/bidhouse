resource "aws_kms_key" "rds" {
  description             = "BidHouse RDS encryption key"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name    = "bidhouse-prod-rds-kms"
    Project = "bidhouse"
  }
}

resource "aws_kms_alias" "rds" {
  name          = "alias/bidhouse-prod-rds-${random_string.rds_hint.result}"
  target_key_id = aws_kms_key.rds.key_id
}

resource "aws_kms_key" "elasticache" {
  description             = "BidHouse ElastiCache encryption key"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name    = "bidhouse-prod-elasticache-kms"
    Project = "bidhouse"
  }
}

resource "aws_kms_alias" "elasticache" {
  name          = "alias/bidhouse-prod-elasticache-${random_string.rds_hint.result}"
  target_key_id = aws_kms_key.elasticache.key_id
}