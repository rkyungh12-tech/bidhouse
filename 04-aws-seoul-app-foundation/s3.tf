resource "random_string" "bucket_suffix" {
  length  = 8
  upper   = false
  special = false
}

resource "aws_s3_bucket" "auction_images" {
  bucket = "${var.project_name}-${var.environment}-images-${random_string.bucket_suffix.result}"

  tags = {
    Name    = "${var.project_name}-${var.environment}-images"
    Purpose = "Auction product image storage"
  }
}

resource "aws_s3_bucket_ownership_controls" "auction_images" {
  bucket = aws_s3_bucket.auction_images.id 

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "auction_images" {
  bucket = aws_s3_bucket.auction_images.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "auction_images" {
  bucket = aws_s3_bucket.auction_images.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "auction_images" {
  bucket = aws_s3_bucket.auction_images.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "auction_images_tls_only" {
  bucket = aws_s3_bucket.auction_images.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"

        Action = "s3:*"

        Resource = [
          aws_s3_bucket.auction_images.arn,
          "${aws_s3_bucket.auction_images.arn}/*"
        ]

        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })

  depends_on = [
    aws_s3_bucket_public_access_block.auction_images
  ]
}