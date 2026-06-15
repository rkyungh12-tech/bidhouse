# ============================================================================
# 🏛️ [00-pipeline/main.tf] 시차 억까 전면 수술 완료본 (원클릭 제로베이스 전용)
# ============================================================================

provider "aws" {
  region = "ap-northeast-2"
}

# 🔐 외부에서 주입받을 변수 정의
variable "azure_client_id" { type = string }
variable "azure_client_secret" { type = string }
variable "azure_tenant_id" { type = string }
variable "azure_subscription_id" { type = string }

variable "aws_access_key_id" {
  type      = string
  sensitive = true
}
variable "aws_secret_access_key" {
  type      = string
  sensitive = true
}

# 1. AWS Secrets Manager에 '금고방' 생성
resource "aws_secretsmanager_secret" "azure_secret_room" {
  name                    = "bidhouse-azure-secret"
  recovery_window_in_days = 0 
}

# 2. 금고방 안에 변수로 전달받은 값 주입
resource "aws_secretsmanager_secret_version" "azure_secret_values" {
  secret_id     = aws_secretsmanager_secret.azure_secret_room.id
  secret_string = jsonencode({
    client_id       = var.azure_client_id
    client_secret   = var.azure_client_secret
    tenant_id       = var.azure_tenant_id
    subscription_id = var.azure_subscription_id
  })
}

# 3. CodeBuild 기계 설정 (★유령 data 블록 대신 변수 직통 연결로 전면 교체!)
resource "aws_codebuild_project" "pipeline_build" {
  name          = "bidhouse-multi-cloud-build"
  build_timeout = "240"
  service_role  = aws_iam_role.codebuild_role.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    image_pull_credentials_type = "CODEBUILD"
    
    type                        = "LINUX_CONTAINER"
    privileged_mode             = true

    # 🟢 [수술 완료] data.aws_secretsmanager... 찌꺼기를 전부 지우고 var 직통으로 고정했습니다!

  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec.yml"
  }
}

# 4. CodePipeline 설정 (민조님 깃허브 완전 연동)
resource "aws_codepipeline" "multi_cloud_pipeline" {
  name     = "bidhouse-multi-cloud-pipeline"
  role_arn = aws_iam_role.pipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.pipeline_artifact_bucket.id 
    type     = "S3"
  }

  ## [Stage 1]: 소스 가져오기
  stage {
    name = "Source"
    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"               
      provider         = "CodeStarSourceConnection" 
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        FullRepositoryId     = "rkyungh12-tech/bidhouse"
        BranchName           = "main"
        ConnectionArn        = aws_codestarconnections_connection.github_link.arn
      }
    }
  }

  # [Stage 2] 전 자동 연속 슛
  stage {
    name = "Deploy"
    action {
      name            = "MultiCloudDeploy"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      input_artifacts = ["source_output"]
      version         = "1"

      configuration = {
        ProjectName = aws_codebuild_project.pipeline_build.name
      }
    }
  }
}

# 5. 마스터 권한 IAM 및 리소스 설정
resource "aws_iam_role" "codebuild_role" {
  name = "bidhouse-codebuild-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17", Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "codebuild.amazonaws.com" } }]
  })
}
resource "aws_iam_role_policy_attachment" "codebuild_admin" {
  role       = aws_iam_role.codebuild_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
resource "aws_iam_role" "pipeline_role" {
  name = "bidhouse-pipeline-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17", Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "codepipeline.amazonaws.com" } }]
  })
}
resource "aws_codestarconnections_connection" "github_link" {
  name          = "bidhouse-github-link"
  provider_type = "GitHub"
}

resource "aws_iam_role_policy_attachment" "pipeline_admin" {
  role       = aws_iam_role.pipeline_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_role_policy_attachment" "codebuild_secrets" {
  role       = aws_iam_role.codebuild_role.name
  policy_arn = "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
}
resource "aws_iam_policy" "codebuild_s3_backend_policy" {
  name        = "bidhouse-codebuild-s3-backend-policy"
  description = "Allow CodeBuild to fully access the S3 Terraform Backend Bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "${aws_s3_bucket.tf_backend_bucket.arn}",
          "${aws_s3_bucket.tf_backend_bucket.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "codebuild_s3_backend_attach" {
  role       = aws_iam_role.codebuild_role.name
  policy_arn = aws_iam_policy.codebuild_s3_backend_policy.arn
}

# 🟢 파이프라인 전용 독립 버킷 생성
resource "aws_s3_bucket" "pipeline_artifact_bucket" {
  bucket        = "bidhouse-pipeline-artifacts-2026" 
  force_destroy = true 
}

# 🟢 테라폼 상태 저장용 금고 버킷 생성
resource "aws_s3_bucket" "tf_backend_bucket" {
  bucket        = "bidhouse-global-immutable-2026" 
  force_destroy = true 

  tags = {
    Name = "bidhouse-global-immutable"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_backend_encrypt" {
  bucket = aws_s3_bucket.tf_backend_bucket.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

output "global_tfstate_bucket_name" {
  value       = aws_s3_bucket.tf_backend_bucket.bucket
}

resource "aws_s3_bucket_versioning" "tf_backend" {
  bucket = aws_s3_bucket.tf_backend_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "tf_backend" {
  bucket = aws_s3_bucket.tf_backend_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "pipeline_artifacts" {
  bucket = aws_s3_bucket.pipeline_artifact_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 1. AWS 자격 증명을 위한 '시크릿 금고' 추가
resource "aws_secretsmanager_secret" "aws_credentials_room" {
  name                    = "bidhouse-aws-credentials"
  recovery_window_in_days = 0 
}

resource "aws_secretsmanager_secret_version" "aws_credentials_values" {
  secret_id     = aws_secretsmanager_secret.aws_credentials_room.id
  secret_string = jsonencode({
    access_key = var.aws_access_key_id        # ← 변수 참조
    secret_key = var.aws_secret_access_key    # ← 변수 참조
  })
}

resource "aws_secretsmanager_secret" "repl_user_password" {
  name                    = "bidhouse-repl-user-password"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "repl_user_password" {
  secret_id     = aws_secretsmanager_secret.repl_user_password.id
  secret_string = "Repl@bidhouse2026!"  # 고정 비밀번호
}

# Azure DR 컨테이너가 AWS SQS에 접근할 IAM 유저
resource "aws_iam_user" "azure_sqs_user" {
  name = "bidhouse-azure-sqs-user"
  tags = { Purpose = "Azure DR SQS access" }
}

resource "aws_iam_access_key" "azure_sqs_user" {
  user = aws_iam_user.azure_sqs_user.name
}

resource "aws_iam_user_policy" "azure_sqs_policy" {
  name = "bidhouse-azure-sqs-policy"
  user = aws_iam_user.azure_sqs_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl"
        ]
        Resource = "arn:aws:sqs:ap-northeast-2:811688201568:bidhouse-auction-close.fifo"
      }
    ]
  })
}

# 생성된 키를 Secrets Manager에 저장
resource "aws_secretsmanager_secret" "azure_sqs_credentials" {
  name                    = "bidhouse-azure-sqs-credentials"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "azure_sqs_credentials" {
  secret_id = aws_secretsmanager_secret.azure_sqs_credentials.id
  secret_string = jsonencode({
    access_key = aws_iam_access_key.azure_sqs_user.id
    secret_key = aws_iam_access_key.azure_sqs_user.secret
  })
}