# =====================================================================
# MONITORING (hub) ACCOUNT
# Per region : OAM sink (cross-account observability) + encrypted alerts topic
# Primary    : SSM transfer bucket, reports bucket, Ansible control-node role
# =====================================================================

# ---- Cross-account observability: member accounts link here -----------------
resource "aws_oam_sink" "this" {
  for_each = local.sink_regions
  region   = each.value
  name     = "disk-monitoring-sink"
}

resource "aws_oam_sink_policy" "this" {
  for_each        = local.sink_regions
  region          = each.value
  sink_identifier = aws_oam_sink.this[each.value].arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = "*"
      Action    = ["oam:CreateLink", "oam:UpdateLink"]
      Resource  = "*"
      Condition = {
        StringEquals                = { "aws:PrincipalOrgID" = local.organization_id }
        "ForAllValues:StringEquals" = { "oam:ResourceTypes" = ["AWS::CloudWatch::Metric"] }
      }
    }]
  })
}

# ---- Alerting: CloudWatch alarms -> SNS (KMS) -> email / Slack / PagerDuty ----
resource "aws_kms_key" "alerts" {
  for_each            = local.regions
  region              = each.value
  description         = "Disk monitoring - alerts topic"
  enable_key_rotation = true
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AccountAdministration"
        Effect    = "Allow"
        Principal = { AWS = "arn:${local.partition}:iam::${local.monitoring_account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowCloudWatchAlarmsToPublish"
        Effect    = "Allow"
        Principal = { Service = "cloudwatch.amazonaws.com" }
        Action    = ["kms:Decrypt", "kms:GenerateDataKey*"]
        Resource  = "*"
      }
    ]
  })
}

resource "aws_sns_topic" "alerts" {
  for_each          = local.regions
  region            = each.value
  name              = local.alerts_topic_name
  kms_master_key_id = aws_kms_key.alerts[each.value].arn
}

resource "aws_sns_topic_policy" "alerts" {
  for_each = local.regions
  region   = each.value
  arn      = aws_sns_topic.alerts[each.value].arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowCloudWatchAlarms"
      Effect    = "Allow"
      Principal = { Service = "cloudwatch.amazonaws.com" }
      Action    = "sns:Publish"
      Resource  = aws_sns_topic.alerts[each.value].arn
      Condition = { StringEquals = { "aws:SourceAccount" = local.monitoring_account_id } }
    }]
  })
}

resource "aws_sns_topic_subscription" "email" {
  for_each  = var.alert_email == "" ? toset([]) : local.regions
  region    = each.value
  topic_arn = aws_sns_topic.alerts[each.value].arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ---- Data key for both buckets ---------------------------------------------
resource "aws_kms_key" "data" {
  description         = "Disk monitoring - SSM transfer and reports buckets"
  enable_key_rotation = true
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Sid       = "AccountAdministration"
        Effect    = "Allow"
        Principal = { AWS = "arn:${local.partition}:iam::${local.monitoring_account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      }],
      # Member-account Ansible roles may use the key only through S3.
      # (Test mode: the role is in this account and is covered by AccountAdministration.)
      [for s in [{
        Sid       = "AllowMemberAnsibleRolesViaS3"
        Effect    = "Allow"
        Principal = { AWS = "*" }
        Action    = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey*"]
        Resource  = "*"
        Condition = {
          StringEquals = {
            "aws:PrincipalOrgID" = local.organization_id
            "kms:ViaService"     = "s3.${var.primary_region}.amazonaws.com"
          }
          ArnLike = { "aws:PrincipalArn" = local.member_role_arn_pattern }
        }
      }] : s if local.org_mode]
    )
  })
}

# ---- Buckets ----------------------------------------------------------------
# ssm     : file transfer for the aws_ssm connection plugin (objects live < 1 day)
# reports : consolidated disk audit reports (90 days)
locals {
  buckets = {
    ssm     = { name = local.ssm_bucket_name, expire_days = 1, versioned = false }
    reports = { name = local.reports_bucket_name, expire_days = 90, versioned = true }
  }
}

resource "aws_s3_bucket" "this" {
  # Empty when manage_s3_buckets = false; every bucket resource below follows it.
  for_each = { for k, v in local.buckets : k => v if var.manage_s3_buckets }
  bucket   = each.value.name
}

resource "aws_s3_bucket_public_access_block" "this" {
  for_each                = aws_s3_bucket.this
  bucket                  = each.value.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "this" {
  for_each = aws_s3_bucket.this
  bucket   = each.value.id
  rule { object_ownership = "BucketOwnerEnforced" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = aws_s3_bucket.this
  bucket   = each.value.id
  rule {
    bucket_key_enabled = true
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.data.arn
    }
  }
}

resource "aws_s3_bucket_versioning" "reports" {
  count  = var.manage_s3_buckets ? 1 : 0
  bucket = aws_s3_bucket.this["reports"].id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  for_each = aws_s3_bucket.this
  bucket   = each.value.id
  rule {
    id     = "expire"
    status = "Enabled"
    filter {}
    expiration { days = local.buckets[each.key].expire_days }
    noncurrent_version_expiration { noncurrent_days = 7 }
    abort_incomplete_multipart_upload { days_after_initiation = 1 }
  }
}

data "aws_iam_policy_document" "bucket" {
  for_each = aws_s3_bucket.this

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [each.value.arn, "${each.value.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  # Only the transfer bucket is used cross-account (by the member Ansible roles).
  dynamic "statement" {
    for_each = each.key == "ssm" && local.org_mode ? [1] : []
    content {
      sid       = "AllowMemberAnsibleRoles"
      effect    = "Allow"
      actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket", "s3:GetBucketLocation"]
      resources = [each.value.arn, "${each.value.arn}/*"]
      principals {
        type        = "*"
        identifiers = ["*"]
      }
      condition {
        test     = "StringEquals"
        variable = "aws:PrincipalOrgID"
        values   = [local.organization_id]
      }
      condition {
        test     = "ArnLike"
        variable = "aws:PrincipalArn"
        values   = [local.member_role_arn_pattern]
      }
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  for_each   = aws_s3_bucket.this
  bucket     = each.value.id
  policy     = data.aws_iam_policy_document.bucket[each.key].json
  depends_on = [aws_s3_bucket_public_access_block.this]
}

# ---- Ansible control node identity -----------------------------------------
# Runs on a private EC2 instance (no public IP, no SSH); operators reach it via
# Session Manager. It is the ONLY principal trusted by the member roles.
data "aws_iam_policy_document" "control_node_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "control_node" {
  statement {
    sid       = "AssumeMemberRolesInOrgOnly"
    actions   = ["sts:AssumeRole"]
    resources = [local.member_role_arn_pattern]
    # Test mode has no organization; the pattern is then pinned to this account instead.
    dynamic "condition" {
      for_each = local.org_mode ? [local.organization_id] : []
      content {
        test     = "StringEquals"
        variable = "aws:ResourceOrgID"
        values   = [condition.value]
      }
    }
  }
  dynamic "statement" {
    for_each = aws_iam_role.org_reader
    content {
      sid       = "AssumeOrgReader"
      actions   = ["sts:AssumeRole"]
      resources = [statement.value.arn]
    }
  }
  statement {
    sid       = "ManageDiskAlarms"
    actions   = ["cloudwatch:PutMetricAlarm", "cloudwatch:DeleteAlarms"]
    resources = ["arn:${local.partition}:cloudwatch:*:${local.monitoring_account_id}:alarm:disk-*"]
  }
  statement {
    sid       = "ManageDiskDashboard"
    actions   = ["cloudwatch:PutDashboard", "cloudwatch:GetDashboard"]
    resources = ["arn:${local.partition}:cloudwatch::${local.monitoring_account_id}:dashboard/Disk-*"]
  }
  statement {
    sid = "ReadMetricsAndAlarms"
    actions = [
      "cloudwatch:DescribeAlarms", "cloudwatch:GetMetricData", "cloudwatch:ListMetrics",
      "oam:ListSinks", "oam:ListAttachedLinks",
    ]
    resources = ["*"]
  }
  statement {
    # Unreachable-instance count from 10_access.yml (blind-spot alarm).
    # PutMetricData has no resource ARN; scope it to the one namespace instead.
    sid       = "PublishUnmanagedInstanceCount"
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = ["DiskMonitoring"]
    }
  }
  statement {
    sid       = "WriteReports"
    actions   = ["s3:PutObject", "s3:GetObject", "s3:ListBucket"]
    resources = [local.reports_bucket_arn, "${local.reports_bucket_arn}/*"]
  }
  statement {
    sid       = "UseDataKey"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = [aws_kms_key.data.arn]
  }
}

resource "aws_iam_role" "control_node" {
  name               = local.control_node_role_name
  assume_role_policy = data.aws_iam_policy_document.control_node_trust.json
}

resource "aws_iam_role_policy" "control_node" {
  name   = "disk-monitoring-control-node"
  role   = aws_iam_role.control_node.id
  policy = data.aws_iam_policy_document.control_node.json
}

resource "aws_iam_role_policy_attachment" "control_node_ssm" {
  role       = aws_iam_role.control_node.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "control_node" {
  name = local.control_node_role_name
  role = aws_iam_role.control_node.name
}
