# BidHouse ECS + RDS + Secrets Manager smoke test

This isolated test stack verifies the following path without modifying the existing multi-cloud Terraform state:

1. Terraform creates an Amazon RDS for MySQL instance.
2. RDS creates and manages the master password in AWS Secrets Manager.
3. Terraform creates an ECS task execution role that can read only that RDS-managed secret.
4. The ECS task definition injects `username` and `password` JSON keys into the container as `DB_USER` and `DB_PASSWORD`.
5. The Node.js application reads `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, and `DB_PASSWORD`, connects to RDS, creates its tables, and serves `/health` through an ALB.

## Prerequisites

- AWS CLI authenticated to a test AWS account or test role
- Terraform >= 1.5
- Docker
- Permissions to create VPC, NAT Gateway, ALB, ECR, RDS, ECS, IAM role, CloudWatch Logs, and Secrets Manager resources

## Important cost note

This smoke test creates paid resources, including an RDS instance, a NAT Gateway, an ALB, and a Fargate task. Destroy the stack after testing.

## Phase 1: create infrastructure but do not start the ECS service

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply
```

The default is:

```hcl
deploy_ecs_service = false
```

This avoids starting an ECS task before the ECR image exists.

## Phase 2: build and push the application image

Linux:

```bash
cd ..
./scripts/push-image.sh smoke
```

Windows PowerShell:

```powershell
cd ..
.\scripts\push-image.ps1 smoke
```

## Phase 3: start the ECS service

Edit `terraform/terraform.tfvars`:

```hcl
deploy_ecs_service = true
```

Then apply again:

```bash
cd terraform
terraform plan
terraform apply
```

## Phase 4: verify

```bash
terraform output -raw rds_master_secret_arn
terraform output -raw health_url
curl "$(terraform output -raw health_url)"
```

Expected response:

```json
{"status":"ok","database":"connected"}
```

You can also inspect the ECS service and logs:

```bash
aws ecs list-clusters --region ap-northeast-2
aws logs describe-log-streams \
  --log-group-name "$(terraform output -raw cloudwatch_log_group_name 2>/dev/null || true)" \
  --region ap-northeast-2
```

## Phase 5: destroy immediately after the test

```bash
cd terraform
terraform destroy
```

## What is intentionally excluded

- Azure resources
- Route 53 failover
- Existing remote Terraform state
- GitHub, CodeBuild, and CodePipeline
- S3 image upload migration

The smoke test isolates only the AWS application execution path.
