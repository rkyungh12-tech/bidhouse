# ============================================================================
# CloudFront distribution for static frontend
# www.bidhouse.cloud -> CloudFront -> private S3 frontend bucket
# ============================================================================

resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "bidhouse-frontend-oac"
  description                       = "OAC for BidHouse private frontend S3 bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
  lifecycle {
    ignore_changes = all
  }
}
resource "aws_cloudfront_origin_access_control" "images" {
  name                              = "bidhouse-images-oac"
  description                       = "OAC for BidHouse auction images S3 bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

resource "aws_cloudfront_distribution" "cdn" {
  enabled             = true
  aliases             = ["www.bidhouse.cloud"]
  default_root_object = "index.html"

  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id                = "bidhouse-frontend-s3-origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  origin {
    domain_name              = "${var.s3_images_bucket_name}.s3.ap-northeast-2.amazonaws.com"
    origin_id                = "bidhouse-images-s3-origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.images.id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "bidhouse-frontend-s3-origin"
    viewer_protocol_policy = "redirect-to-https"
    cache_policy_id        = data.aws_cloudfront_cache_policy.caching_optimized.id
    compress               = true
  }
  ordered_cache_behavior {
    path_pattern           = "/images/*"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "bidhouse-images-s3-origin"
    viewer_protocol_policy = "redirect-to-https"
    cache_policy_id        = data.aws_cloudfront_cache_policy.caching_optimized.id
    compress               = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    # Existing us-east-1 certificate remains valid because the viewer domain
    # is still www.bidhouse.cloud. Only the origin changes from ALB to S3.
    acm_certificate_arn      = aws_acm_certificate_validation.cdn.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = { Name = "bidhouse-frontend-cdn" }
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.cdn.domain_name
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.cdn.id
}

output "cloudfront_images_base_url" {
  description = "CloudFront base URL for auction images"
  value       = "https://${aws_cloudfront_distribution.cdn.domain_name}/images"
}