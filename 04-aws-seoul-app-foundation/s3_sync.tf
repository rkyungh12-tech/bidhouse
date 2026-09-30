# S3 → Azure Blob 실시간 동기화 Lambda

variable "az_storage_account_name" {
  description = "Azure Storage account name"
  type        = string
  default     = ""
}

variable "az_storage_account_key" {
  description = "Azure Storage account key"
  type        = string
  default     = ""
  sensitive   = true
}


resource "aws_iam_role" "lambda_s3_sync" {
  name = "bidhouse-s3-sync-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow",
      Principal = { Service = "lambda.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy" "lambda_s3_sync_policy" {
  role = aws_iam_role.lambda_s3_sync.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["logs:*"], Resource = "*" },
      { Effect = "Allow", Action = ["s3:GetObject"], Resource = "${aws_s3_bucket.auction_images.arn}/*" }
    ]
  })
}

resource "aws_lambda_function" "s3_sync" {
  filename      = "${path.module}/s3_sync_lambda.zip"
  function_name = "bidhouse-s3-to-azure-sync"
  role          = aws_iam_role.lambda_s3_sync.arn
  handler       = "index.handler"
  runtime       = "nodejs20.x"
  timeout       = 60

  environment {
    variables = {
      AZ_STORAGE_ACCOUNT_NAME = var.az_storage_account_name
      AZ_STORAGE_ACCOUNT_KEY  = var.az_storage_account_key
    }
  }
}

resource "aws_lambda_permission" "allow_s3" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_sync.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.auction_images.arn
}

resource "aws_s3_bucket_notification" "image_upload" {
  bucket = aws_s3_bucket.auction_images.id
  lambda_function {
    lambda_function_arn = aws_lambda_function.s3_sync.arn
    events              = ["s3:ObjectCreated:*"]
  }
  depends_on = [aws_lambda_permission.allow_s3]
}