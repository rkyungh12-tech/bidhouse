resource "aws_cloudwatch_log_group" "vpn" {
  name              = "/aws/vpn/bidhouse-aws-to-azure"
  retention_in_days = 30

  tags = {
    Name        = "bidhouse-aws-to-azure-vpn-logs"
    Environment = "prod"
    Project     = "bidhouse"
    Purpose     = "AWS to Azure Site-to-Site VPN tunnel logs"
  }
}