variable "primary_region" {
  description = "Region for the control-node identity, buckets and dashboard."
  type        = string
  default     = "us-east-1"
}

variable "regions" {
  description = "Every region that runs workloads. Each gets a metrics sink, an alerts topic and StackSet instances."
  type        = list(string)
  default     = ["us-east-1", "us-west-2"]
  validation {
    condition     = length(var.regions) > 0
    error_message = "At least one region is required."
  }
}

variable "single_account_mode" {
  description = "TEST ONLY. One standalone account is both the monitoring and the only workload account: no Organization, StackSet, SCP or OAM sink/link; the member baseline is deployed as a normal stack. Keep false for the real multi-account design."
  type        = bool
  default     = false
}

variable "manage_s3_buckets" {
  description = "TEST ONLY when false. Create and configure the two S3 buckets here. Set false when a TLS-inspecting proxy breaks the provider's S3 request signing (SignatureDoesNotMatch); then create them with test/create_s3_buckets.sh, which applies the same settings."
  type        = bool
  default     = true
}

variable "org_admin_role_arn" {
  description = "Role in the management (or StackSets delegated-admin) account that Terraform assumes for org-level resources. Required unless single_account_mode."
  type        = string
  default     = ""
}

variable "target_ou_ids" {
  description = "OUs whose accounts are monitored. Auto-deployment enrolls accounts that join them later."
  type        = list(string)
  default     = []
}

variable "scp_target_ids" {
  description = "Roots/OUs the protective SCP is attached to (usually the same OUs). Empty = do not attach."
  type        = list(string)
  default     = []
}

variable "alert_email" {
  description = "Optional email subscription for alerts (Slack / PagerDuty can subscribe to the same topics)."
  type        = string
  default     = ""
}

variable "additional_trusted_principal_arn" {
  description = "Optional extra principal allowed to assume DiskMonitoringAnsibleRole (break-glass / PoC laptop role)."
  type        = string
  default     = ""
}

variable "stackset_failure_tolerance_percentage" {
  description = "Percentage of accounts per region that may fail before a StackSet operation stops."
  type        = number
  default     = 10
}

variable "stackset_max_concurrent_percentage" {
  type    = number
  default = 25
}

variable "tags" {
  type = map(string)
  default = {
    Project   = "disk-monitoring"
    ManagedBy = "terraform"
  }
}
