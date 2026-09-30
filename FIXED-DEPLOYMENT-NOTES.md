# BidHouse corrected deployment notes

## Bootstrap prerequisites

1. The public Route 53 hosted zone `bidhouse.cloud` must already exist in the AWS account.
2. The Azure service principal used by `00-pipeline/terraform.tfvars` must be able to create Azure role assignments (`Owner`, or equivalent permissions).
3. Copy `00-pipeline/terraform.tfvars.example` to `00-pipeline/terraform.tfvars` only on the bootstrap operator PC. Never commit the real file.
4. Run `terraform apply` in `00-pipeline`, then complete the GitHub CodeStar connection approval once in the AWS console.

## Automated flow after Git push

- Creates AWS app foundation resources.
- Creates the AWS ECR repository first.
- Builds the Node.js image and pushes an immutable Git SHA tag to ECR.
- Applies AWS Seoul resources with that image tag.
- Starts or rolls the ECS service, waits for stability, and checks `/health`.
- Creates Azure DR resources, including Key Vault, Managed Identity, MySQL, ACR, and a placeholder Container App revision.
- Pushes the same Git SHA image to ACR.
- Applies the Azure DR root again so ACA runs the BidHouse image with Key Vault-backed environment variables.
- Applies cross-cloud VPN and Route 53 DR resources.

## Known remaining DR limitations

- `03-cross-cloud/cross_route53.tf` still uses a fixed secondary IP. Replace it after the Azure custom-domain and ingress design is finalized.
- RDS-to-Azure MySQL binlog replication is not configured yet.
- S3-to-Azure Blob synchronization is not configured yet.
- ECS uses a IP as a temporary bootstrap path. Move tasks to private subnets with NAT or VPC endpoints later.
- Cognito resources exist, but the Node.js login flow still uses its legacy JWT implementation.

## Validation performed in this package build

- JavaScript syntax checks passed for the main application files.
- `buildspec.yml` YAML parsing passed.
- Terraform delimiter structure checks passed.
- Full `terraform init` / `terraform validate` could not be executed in the packaging sandbox because outbound provider downloads were unavailable. Run them from the deployment workstation before pushing.
