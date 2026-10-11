data "aws_caller_identity" "hub" {}
data "aws_partition" "current" {}
data "aws_organizations_organization" "this" {
  count    = var.single_account_mode ? 0 : 1
  provider = aws.org
}

locals {
  org_mode              = !var.single_account_mode
  partition             = data.aws_partition.current.partition
  monitoring_account_id = data.aws_caller_identity.hub.account_id
  organization_id       = local.org_mode ? data.aws_organizations_organization.this[0].id : ""
  regions               = toset(var.regions)
  # Cross-account observability needs a separate monitoring account; one account monitors itself.
  sink_regions = local.org_mode ? local.regions : toset([])

  # Names shared with the Ansible side (inventory/group_vars/all/main.yml) - keep in sync.
  control_node_role_name = "DiskMonitoringControlNode"
  member_role_name       = "DiskMonitoringAnsibleRole"
  alerts_topic_name      = "disk-monitoring-alerts"
  ssm_bucket_name        = "disk-monitoring-ssm-${local.monitoring_account_id}"
  reports_bucket_name    = "disk-monitoring-reports-${local.monitoring_account_id}"
  reports_bucket_arn     = "arn:${local.partition}:s3:::${local.reports_bucket_name}"

  # Org mode: the role in any account (scoped by aws:ResourceOrgID). Test mode: this account only.
  member_role_arn_pattern = "arn:${local.partition}:iam::${local.org_mode ? "*" : local.monitoring_account_id}:role/${local.member_role_name}"
}
