# Monitoring (hub) account - sinks, alerting, buckets, control-node identity.
provider "aws" {
  region = var.primary_region
  default_tags { tags = var.tags }
}

# Management account (or the CloudFormation StackSets delegated administrator):
# service-managed StackSets, the SCP and the org-reader role must be created here.
# Unused in single_account_mode (no role to assume; every org resource has count = 0).
provider "aws" {
  alias  = "org"
  region = var.primary_region
  dynamic "assume_role" {
    for_each = var.org_admin_role_arn == "" ? [] : [var.org_admin_role_arn]
    content { role_arn = assume_role.value }
  }
  default_tags { tags = var.tags }
}
