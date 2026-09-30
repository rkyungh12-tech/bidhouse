# S3 Frontend Split Patch Notes

## Implemented target architecture

```text
www.bidhouse.cloud
  -> CloudFront
  -> private S3 frontend bucket
  -> app/public/index.html

api.bidhouse.cloud
  -> Route 53 failover
     -> PRIMARY: AWS ALB -> ECS
     -> SECONDARY: Azure Container Apps
```

## Existing ACM certificate

The existing `www.bidhouse.cloud` ACM certificate in `us-east-1` is preserved and remains attached to CloudFront. Only the CloudFront origin changes from ALB to private S3.

A new `api.bidhouse.cloud` ACM certificate is created in `ap-northeast-2` and attached to the ALB HTTPS listener.

## One-time DNS migration for an already deployed environment

The old project used `www.bidhouse.cloud` as a Route 53 failover pair. The final split uses a simple CloudFront alias for `www` and moves failover to `api.bidhouse.cloud`.

Before the first apply of this patch in an existing environment, run:

```bash
bash scripts/prepare-s3-frontend-dns-migration.sh
```

A fresh zero-base deployment does not need this script.

## Changed files

- `01-aws-seoul-network/frontend-s3.tf` (new)
- `01-aws-seoul-network/cloudfront.tf`
- `01-aws-seoul-network/acm.tf`
- `01-aws-seoul-network/route53_dr.tf`
- `01-aws-seoul-network/ecs-alb.tf`
- `01-aws-seoul-network/ecs.tf`
- `02-azure-singapore-dr/container-app.tf`
- `03-cross-cloud/cross_route53.tf`
- `app/public/index.html`
- `app/server.js`
- `buildspec.yml`
- `scripts/prepare-s3-frontend-dns-migration.sh` (new)

## Deployment behavior

CodeBuild now uploads `app/public` to the private frontend bucket and invalidates `/index.html` after applying the Seoul AWS resources.

## Deliberately preserved behavior

The ECS Docker image still includes `app/public` and Express still serves the old static path as a fallback. Production frontend traffic goes through S3 and CloudFront, but the fallback reduces rollback risk during the first migration.

## Deferred work

- Move `/uploads/*` product images from ECS local storage to the existing image S3 bucket.
- Tighten the CodeBuild role, which currently has broad AdministratorAccess in the original project.
