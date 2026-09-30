# ============================================================================
# SQS FIFO: 경매 종료 처리 큐
# ============================================================================
resource "aws_sqs_queue" "auction_close" {
  name                        = "bidhouse-auction-close.fifo"
  fifo_queue                  = true
  content_based_deduplication = false
  message_retention_seconds   = 3600
  visibility_timeout_seconds  = 60
  tags = { Name = "bidhouse-auction-close", Project = "bidhouse" }
}

# ============================================================================
# SQS FIFO: 실시간 입찰 대기열 (순서 보장 및 중복 방지)
# ============================================================================
resource "aws_sqs_queue" "bid_requests" {
  name                        = "bidhouse-bid-requests.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  visibility_timeout_seconds  = 30
  message_retention_seconds   = 3600
  tags = { Name = "bidhouse-bid-requests", Project = "bidhouse" }
}

resource "aws_sqs_queue_policy" "bid_requests" {
  queue_url = aws_sqs_queue.bid_requests.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
      Action    = "sqs:*"
      Resource  = aws_sqs_queue.bid_requests.arn
    }]
  })
}

output "bid_queue_url" {
  value = aws_sqs_queue.bid_requests.url
}

output "auction_close_queue_url" {
  value = aws_sqs_queue.auction_close.url
}