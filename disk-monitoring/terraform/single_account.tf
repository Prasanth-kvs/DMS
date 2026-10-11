# =====================================================================
# SINGLE-ACCOUNT TEST MODE (var.single_account_mode = true)
# One standalone account plays both roles: monitoring account and the only
# workload account. The member baseline is a normal CloudFormation stack in
# the primary region (IAM only, no metrics link - the account monitors itself).
# The multi-account design in org.tf is unchanged and is what you deploy for real.
# =====================================================================
resource "aws_cloudformation_stack" "member_baseline_single" {
  count         = var.single_account_mode ? 1 : 0
  name          = "disk-monitoring-member-baseline"
  capabilities  = ["CAPABILITY_NAMED_IAM"]
  template_body = file("${path.module}/../cloudformation/member-baseline.yml")

  parameters = {
    MonitoringAccountId           = local.monitoring_account_id
    PrimaryRegion                 = var.primary_region
    SinkArn                       = "" # no OAM link to itself
    SsmTransferBucketName         = local.ssm_bucket_name
    DataKeyArn                    = aws_kms_key.data.arn
    AdditionalTrustedPrincipalArn = var.additional_trusted_principal_arn
  }

  # The Ansible role trusts the control-node role, so it must exist first.
  depends_on = [aws_iam_role.control_node]
}
