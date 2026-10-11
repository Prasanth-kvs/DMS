# =====================================================================
# ORGANIZATION LEVEL (management or StackSets delegated-admin account)
# =====================================================================

variable "stackset_call_as" {
  description = "SELF when Terraform runs as the management account, DELEGATED_ADMIN when it runs as a StackSets delegated administrator."
  type        = string
  default     = "SELF"
  validation {
    condition     = contains(["SELF", "DELEGATED_ADMIN"], var.stackset_call_as)
    error_message = "stackset_call_as must be SELF or DELEGATED_ADMIN."
  }
}

# ---- Member-account baseline, deployed to every account in the target OUs ----
# Service-managed + auto-deployment: an account that is created in, or moved into,
# a target OU (e.g. after an acquisition) gets the Ansible role, the instance
# profile and the metrics link automatically - no Terraform run, no ticket.
resource "aws_cloudformation_stack_set" "member_baseline" {
  count            = local.org_mode ? 1 : 0
  provider         = aws.org
  name             = "disk-monitoring-member-baseline"
  description      = "Disk monitoring: Ansible execution role, instance profile, CloudWatch OAM link"
  permission_model = "SERVICE_MANAGED"
  call_as          = var.stackset_call_as
  capabilities     = ["CAPABILITY_NAMED_IAM"]
  template_body    = file("${path.module}/../cloudformation/member-baseline.yml")

  auto_deployment {
    enabled                          = true
    retain_stacks_on_account_removal = false
  }

  operation_preferences {
    region_concurrency_type      = "PARALLEL"
    failure_tolerance_percentage = var.stackset_failure_tolerance_percentage
    max_concurrent_percentage    = var.stackset_max_concurrent_percentage
  }

  managed_execution { active = true }

  parameters = {
    MonitoringAccountId           = local.monitoring_account_id
    PrimaryRegion                 = var.primary_region
    SinkArn                       = aws_oam_sink.this[var.primary_region].arn # overridden per region below
    SsmTransferBucketName         = local.ssm_bucket_name
    DataKeyArn                    = aws_kms_key.data.arn
    AdditionalTrustedPrincipalArn = var.additional_trusted_principal_arn
  }

  lifecycle {
    # AWS fills this in for service-managed StackSets; ignoring avoids perpetual diffs.
    ignore_changes = [administration_role_arn]

    precondition {
      condition     = var.org_admin_role_arn != "" && length(var.target_ou_ids) > 0
      error_message = "org_admin_role_arn and target_ou_ids are required unless single_account_mode = true."
    }
  }

  # The member roles trust the control-node role, so it must exist first.
  depends_on = [aws_iam_role.control_node, aws_oam_sink_policy.this]
}

# One instance per region so each region's link points at THAT region's sink.
resource "aws_cloudformation_stack_set_instance" "member_baseline" {
  provider       = aws.org
  for_each       = local.org_mode ? local.regions : toset([])
  stack_set_name = aws_cloudformation_stack_set.member_baseline[0].name
  call_as        = var.stackset_call_as

  stack_set_instance_region = each.value

  deployment_targets {
    organizational_unit_ids = var.target_ou_ids
  }

  parameter_overrides = {
    SinkArn = aws_oam_sink.this[each.value].arn
  }

  operation_preferences {
    failure_tolerance_percentage = var.stackset_failure_tolerance_percentage
    max_concurrent_percentage    = var.stackset_max_concurrent_percentage
  }
}

# ---- Read-only role for account discovery (playbooks/00_discover.yml) ---------
resource "aws_iam_role" "org_reader" {
  count                = local.org_mode ? 1 : 0
  provider             = aws.org
  name                 = "DiskMonitoringOrgReader"
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = aws_iam_role.control_node.arn }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "org_reader" {
  count    = local.org_mode ? 1 : 0
  provider = aws.org
  name     = "list-accounts"
  role     = aws_iam_role.org_reader[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "organizations:ListAccounts",
        "organizations:ListAccountsForParent",
        "organizations:ListChildren",
        "organizations:DescribeOrganization",
        "organizations:DescribeAccount",
      ]
      Resource = "*"
    }]
  })
}

# ---- Guardrail: workload admins cannot remove or weaken the monitoring plumbing --
resource "aws_organizations_policy" "protect_disk_monitoring" {
  count       = local.org_mode ? 1 : 0
  provider    = aws.org
  name        = "protect-disk-monitoring"
  description = "Prevents tampering with disk-monitoring roles, metrics links, agent config and self-healing"
  type        = "SERVICE_CONTROL_POLICY"
  content     = file("${path.module}/policies/scp-protect-disk-monitoring.json")
}

resource "aws_organizations_policy_attachment" "protect_disk_monitoring" {
  provider  = aws.org
  for_each  = local.org_mode ? toset(var.scp_target_ids) : toset([])
  policy_id = aws_organizations_policy.protect_disk_monitoring[0].id
  target_id = each.value
}
