# ============================================================================
# SQS FIFO: 경매 자동 종료 처리 (정확히 한 번 보장)
# ============================================================================

resource "aws_sqs_queue" "auction_close" {
  name                        = "bidhouse-auction-close.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  visibility_timeout_seconds  = 60
  message_retention_seconds   = 3600

  tags = {
    Name    = "bidhouse-auction-close"
    Project = "bidhouse"
  }
}

resource "aws_sqs_queue_policy" "auction_close" {
  queue_url = aws_sqs_queue.auction_close.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
      Action    = "sqs:*"
      Resource  = aws_sqs_queue.auction_close.arn
    }]
  })
}

output "auction_close_queue_url" {
  value = aws_sqs_queue.auction_close.url
}

output "auction_close_queue_arn" {
  value = aws_sqs_queue.auction_close.arn
}