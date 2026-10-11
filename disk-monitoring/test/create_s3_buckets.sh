#!/usr/bin/env bash
# =====================================================================
# TEST HELPER - create and secure the two S3 buckets with the AWS CLI.
# Use with manage_s3_buckets = false (terraform/single-account.tfvars) when a
# TLS-inspecting corporate proxy breaks the Terraform provider's S3 request
# signing (SignatureDoesNotMatch on CreateBucket / 403 on HeadBucket).
# Applies the same settings as terraform/hub.tf for single-account mode:
#   public access block, BucketOwnerEnforced, SSE-KMS (bucket key) with the
#   Terraform data key, versioning on reports, lifecycle, TLS-only policy, tags.
# Idempotent: safe to re-run.
#
#   cd disk-monitoring && test/create_s3_buckets.sh            # after terraform apply
# =====================================================================
set -euo pipefail

REGION="${REGION:-us-east-1}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
KMS_KEY_ARN="${KMS_KEY_ARN:-$(terraform -chdir="$(dirname "$0")/../terraform" output -raw data_key_arn)}"

echo "Account ${ACCOUNT_ID}, region ${REGION}, key ${KMS_KEY_ARN}"

configure_bucket() {
  local bucket="$1" expire_days="$2" versioned="$3"

  if aws s3api head-bucket --bucket "$bucket" >/dev/null 2>&1; then
    echo "[$bucket] exists"
  elif [ "$REGION" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "$bucket" --region "$REGION" >/dev/null
    echo "[$bucket] created"
  else
    aws s3api create-bucket --bucket "$bucket" --region "$REGION" \
      --create-bucket-configuration "LocationConstraint=$REGION" >/dev/null
    echo "[$bucket] created"
  fi

  aws s3api put-public-access-block --bucket "$bucket" --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

  aws s3api put-bucket-ownership-controls --bucket "$bucket" \
    --ownership-controls 'Rules=[{ObjectOwnership=BucketOwnerEnforced}]'

  aws s3api put-bucket-encryption --bucket "$bucket" --server-side-encryption-configuration \
    "{\"Rules\":[{\"ApplyServerSideEncryptionByDefault\":{\"SSEAlgorithm\":\"aws:kms\",\"KMSMasterKeyID\":\"${KMS_KEY_ARN}\"},\"BucketKeyEnabled\":true}]}"

  if [ "$versioned" = "true" ]; then
    aws s3api put-bucket-versioning --bucket "$bucket" --versioning-configuration Status=Enabled
  fi

  aws s3api put-bucket-lifecycle-configuration --bucket "$bucket" --lifecycle-configuration \
    "{\"Rules\":[{\"ID\":\"expire\",\"Status\":\"Enabled\",\"Filter\":{\"Prefix\":\"\"},
      \"Expiration\":{\"Days\":${expire_days}},
      \"NoncurrentVersionExpiration\":{\"NoncurrentDays\":7},
      \"AbortIncompleteMultipartUpload\":{\"DaysAfterInitiation\":1}}]}" >/dev/null

  aws s3api put-bucket-policy --bucket "$bucket" --policy \
    "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"DenyInsecureTransport\",\"Effect\":\"Deny\",
      \"Principal\":\"*\",\"Action\":\"s3:*\",
      \"Resource\":[\"arn:aws:s3:::${bucket}\",\"arn:aws:s3:::${bucket}/*\"],
      \"Condition\":{\"Bool\":{\"aws:SecureTransport\":\"false\"}}}]}"

  aws s3api put-bucket-tagging --bucket "$bucket" \
    --tagging 'TagSet=[{Key=Project,Value=disk-monitoring},{Key=ManagedBy,Value=test-script}]'

  echo "[$bucket] secured (expire ${expire_days}d, versioned=${versioned})"
}

#               bucket                                   expire  versioned
configure_bucket "disk-monitoring-ssm-${ACCOUNT_ID}"      1       false
configure_bucket "disk-monitoring-reports-${ACCOUNT_ID}"  90      true

echo "Done. Verify: aws s3api get-bucket-encryption --bucket disk-monitoring-ssm-${ACCOUNT_ID}"
