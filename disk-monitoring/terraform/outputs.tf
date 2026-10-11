output "sink_arns" {
  description = "OAM sink per region (member accounts link to these). Empty in single_account_mode."
  value       = { for r, s in aws_oam_sink.this : r => s.arn }
}

output "alerts_topic_arns" {
  value = { for r, t in aws_sns_topic.alerts : r => t.arn }
}

output "control_node_instance_profile" {
  description = "Attach to the Ansible control-node EC2 instance (private subnet, no public IP)."
  value       = aws_iam_instance_profile.control_node.name
}

output "org_reader_role_arn" {
  value = try(aws_iam_role.org_reader[0].arn, null)
}

locals {
  ansible_group_vars = {
    monitoring_account_id = local.monitoring_account_id
    primary_region        = var.primary_region
    aws_regions           = var.regions
    org_reader_role_arn   = try(aws_iam_role.org_reader[0].arn, "")
    ssm_transfer_bucket   = local.ssm_bucket_name
    reports_bucket        = local.reports_bucket_name
    alerts_topic_name     = local.alerts_topic_name
  }
}

output "ansible_group_vars" {
  description = "Paste into inventory/group_vars/all/main.yml (or save as a file and pass with -e @file)."
  value = var.single_account_mode ? yamlencode(merge(local.ansible_group_vars, {
    single_account_mode = true
    static_accounts     = [{ id = local.monitoring_account_id, name = "test" }]
  })) : yamlencode(local.ansible_group_vars)
}

output "data_key_arn" {
  description = "KMS key for both buckets (input to test/create_s3_buckets.sh when manage_s3_buckets = false)."
  value       = aws_kms_key.data.arn
}
