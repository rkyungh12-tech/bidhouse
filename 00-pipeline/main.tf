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

    # 🟢 [수술 완료] aws_secretsmanager... 찌꺼기를 전부 지우고 var 직통으로 고정했습니다!

  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec.yml"
  }
  vpc_config {
    vpc_id             = aws_vpc.prod_vpc.id
    subnets            = [aws_subnet.prod_private_a.id, aws_subnet.prod_private_c.id]
    security_group_ids = [aws_security_group.codebuild_sg.id]
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
        FullRepositoryId     = "minjo46/bidhouse"
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
        Resource = [
          "arn:aws:sqs:ap-northeast-2:811688201568:bidhouse-auction-close.fifo",
          "arn:aws:sqs:ap-northeast-2:811688201568:bidhouse-bid-requests.fifo"
        ]
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

# ============================================================================
# [00-pipeline/main.tf 추가분] Prod VPC + NAT + CodeBuild SG
# CodeBuild가 VPC 안에서 실행되어 VPN 터널을 통해 Azure MySQL에 접근 가능
# ============================================================================

# ── Prod VPC ─────────────────────────────────────────────────
resource "aws_vpc" "prod_vpc" {
  cidr_block           = "10.1.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "bidhouse-prod-vpc" }
}

# ── 인터넷 게이트웨이 ──────────────────────────────────────────
resource "aws_internet_gateway" "prod_igw" {
  vpc_id = aws_vpc.prod_vpc.id
  tags   = { Name = "bidhouse-prod-igw" }
}

# ── 퍼블릭 서브넷 ─────────────────────────────────────────────
resource "aws_subnet" "prod_public" {
  vpc_id                  = aws_vpc.prod_vpc.id
  cidr_block              = "10.1.1.0/24"
  availability_zone       = "ap-northeast-2a"
  map_public_ip_on_launch = true
  tags = { Name = "bidhouse-prod-public-sub" }
}

resource "aws_subnet" "prod_public_2" {
  vpc_id                  = aws_vpc.prod_vpc.id
  cidr_block              = "10.1.3.0/24"
  availability_zone       = "ap-northeast-2c"
  map_public_ip_on_launch = true
  tags = { Name = "bidhouse-prod-public-sub-2" }
}

# ── 프라이빗 서브넷 ───────────────────────────────────────────
resource "aws_subnet" "prod_private_a" {
  vpc_id            = aws_vpc.prod_vpc.id
  cidr_block        = "10.1.2.0/24"
  availability_zone = "ap-northeast-2a"
  tags = { Name = "bidhouse-prod-private-sub-a" }
}

resource "aws_subnet" "prod_private_c" {
  vpc_id            = aws_vpc.prod_vpc.id
  cidr_block        = "10.1.4.0/24"
  availability_zone = "ap-northeast-2c"
  tags = { Name = "bidhouse-prod-private-sub-c" }
}

# ── NAT Gateway ───────────────────────────────────────────────
resource "aws_eip" "prod_nat" {
  domain = "vpc"
  tags   = { Name = "bidhouse-prod-nat-eip" }
}

resource "aws_nat_gateway" "prod" {
  allocation_id = aws_eip.prod_nat.id
  subnet_id     = aws_subnet.prod_public.id
  depends_on    = [aws_internet_gateway.prod_igw]
  tags          = { Name = "bidhouse-prod-nat-gateway" }
}

# ── 퍼블릭 라우팅 테이블 (TGW 라우트는 01에서 추가) ───────────
resource "aws_route_table" "prod_public_rt" {
  vpc_id = aws_vpc.prod_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.prod_igw.id
  }
  tags = { Name = "bidhouse-prod-public-rt" }
}

# ── 프라이빗 라우팅 테이블 (TGW 라우트는 01에서 추가) ──────────
resource "aws_route_table" "prod_private_rt" {
  vpc_id = aws_vpc.prod_vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.prod.id
  }
  tags = { Name = "bidhouse-prod-private-rt" }
}

# ── 라우팅 테이블 연결 ─────────────────────────────────────────
resource "aws_route_table_association" "prod_pub" {
  subnet_id      = aws_subnet.prod_public.id
  route_table_id = aws_route_table.prod_public_rt.id
}

resource "aws_route_table_association" "prod_pub_2" {
  subnet_id      = aws_subnet.prod_public_2.id
  route_table_id = aws_route_table.prod_public_rt.id
}

resource "aws_route_table_association" "prod_pri_a" {
  subnet_id      = aws_subnet.prod_private_a.id
  route_table_id = aws_route_table.prod_private_rt.id
}

resource "aws_route_table_association" "prod_pri_c" {
  subnet_id      = aws_subnet.prod_private_c.id
  route_table_id = aws_route_table.prod_private_rt.id
}

# ── CodeBuild 전용 Security Group ─────────────────────────────
resource "aws_security_group" "codebuild_sg" {
  name        = "bidhouse-codebuild-sg"
  description = "CodeBuild VPC access for DB replication via VPN"
  vpc_id      = aws_vpc.prod_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "bidhouse-codebuild-sg" }
}

# ── 출력값 (01-aws-seoul-network에서 data로 참조용) ─────────────
output "prod_vpc_id" {
  value = aws_vpc.prod_vpc.id
}

output "prod_public_subnet_id" {
  value = aws_subnet.prod_public.id
}

output "prod_public_subnet_2_id" {
  value = aws_subnet.prod_public_2.id
}

output "prod_private_subnet_a_id" {
  value = aws_subnet.prod_private_a.id
}

output "prod_private_subnet_c_id" {
  value = aws_subnet.prod_private_c.id
}

output "prod_public_route_table_id" {
  value = aws_route_table.prod_public_rt.id
}

output "prod_private_route_table_id" {
  value = aws_route_table.prod_private_rt.id
}

output "prod_nat_gateway_id" {
  value = aws_nat_gateway.prod.id
}

output "prod_nat_gateway_public_ip" {
  value = aws_eip.prod_nat.public_ip
}

output "nat_gateway_public_ip" {
  value = aws_eip.prod_nat.public_ip
}
