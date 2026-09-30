#!/usr/bin/env bash
set -euo pipefail

# One-time migration helper for an environment that already has:
#   www.bidhouse.cloud PRIMARY  -> CloudFront -> ALB
#   www.bidhouse.cloud SECONDARY -> Azure ACA
#
# Run this ONCE before the first terraform apply of the S3 frontend split patch.
# It removes the old www SECONDARY record so the 01 root can replace the old
# www failover PRIMARY record with a simple CloudFront alias.

ZONE_ID="${ZONE_ID:-}"
if [ -z "$ZONE_ID" ]; then
  ZONE_ID=$(aws route53 list-hosted-zones-by-name \
    --dns-name bidhouse.cloud \
    --query "HostedZones[?Name=='bidhouse.cloud.'].Id | [0]" \
    --output text | sed 's|/hostedzone/||')
fi

if [ -z "$ZONE_ID" ] || [ "$ZONE_ID" = "None" ]; then
  echo "Could not find the bidhouse.cloud hosted zone." >&2
  exit 1
fi

echo "Hosted zone: $ZONE_ID"

OLD_RECORD_JSON=$(aws route53 list-resource-record-sets \
  --hosted-zone-id "$ZONE_ID" \
  --query "ResourceRecordSets[?Name=='www.bidhouse.cloud.' && Type=='A' && SetIdentifier=='singapore-dr'] | [0]" \
  --output json)

if [ "$OLD_RECORD_JSON" != "null" ] && [ -n "$OLD_RECORD_JSON" ]; then
  CHANGE_BATCH=$(jq -n --argjson record "$OLD_RECORD_JSON" \
    '{Changes:[{Action:"DELETE",ResourceRecordSet:$record}]}')

  aws route53 change-resource-record-sets \
    --hosted-zone-id "$ZONE_ID" \
    --change-batch "$CHANGE_BATCH"

  echo "Deleted old www.bidhouse.cloud SECONDARY record."
else
  echo "Old www SECONDARY record was not found. Nothing to delete."
fi

if [ -d "03-cross-cloud" ]; then
  cd 03-cross-cloud
  terraform init -reconfigure
  terraform state rm aws_route53_record.secondary || true
  echo "Removed old secondary DNS record from 03-cross-cloud Terraform state."
else
  echo "Run this script from the project root so 03-cross-cloud state can be updated." >&2
  exit 1
fi
