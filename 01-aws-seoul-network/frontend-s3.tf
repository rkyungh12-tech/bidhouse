# ============================================================================
# Static frontend S3 bucket
# - CloudFront is the only intended reader.
# - The bucket is private; public website hosting is intentionally not enabled.
# ============================================================================

resource "aws_s3_bucket" "frontend" {
  bucket        = "bidhouse-prod-frontend-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = {
    Name    = "bidhouse-prod-frontend"
    Purpose = "Static frontend assets for CloudFront"
  }
}

resource "aws_s3_bucket_ownership_controls" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CloudFront OAC signs requests. Only this distribution can read frontend files.
data "aws_iam_policy_document" "frontend_cloudfront_read" {
  statement {
    sid     = "AllowCloudFrontServicePrincipalReadOnly"
    effect  = "Allow"
    actions = ["s3:GetObject"]

    resources = [
      "${aws_s3_bucket.frontend.arn}/*"
    ]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.cdn.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  policy = data.aws_iam_policy_document.frontend_cloudfront_read.json

  depends_on = [
    aws_s3_bucket_public_access_block.frontend
  ]
}

output "frontend_bucket_name" {
  description = "Private S3 bucket that stores index.html and frontend assets"
  value       = aws_s3_bucket.frontend.bucket
}
