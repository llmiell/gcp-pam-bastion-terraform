variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP Region"
  type        = string
  default     = "asia-southeast1"
}

variable "zone" {
  description = "GCP Zone"
  type        = string
  default     = "asia-southeast1-a"
}

variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "pam-bastion"
}

variable "subnet_cidr" {
  description = "CIDR range for the subnet"
  type        = string
  default     = "10.0.0.0/24"
}

# -----------------------------------------------------------------------------
# Cloud SQL Variables
# -----------------------------------------------------------------------------
variable "db_version" {
  description = "Cloud SQL database version"
  type        = string
  default     = "POSTGRES_15"
}

variable "db_tier" {
  description = "Cloud SQL machine tier"
  type        = string
  default     = "db-f1-micro"
}

variable "db_high_availability" {
  description = "Enable high availability"
  type        = bool
  default     = false
}

variable "db_name" {
  description = "Name of the application database"
  type        = string
  default     = "appdb"
}

variable "db_port" {
  description = "Database port"
  type        = number
  default     = 5432
}

variable "db_deletion_protection" {
  description = "Enable deletion protection for Cloud SQL"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Bastion Variables
# -----------------------------------------------------------------------------
variable "bastion_machine_type" {
  description = "GCE machine type for bastion"
  type        = string
  default     = "e2-medium"
}

variable "cloud_sql_proxy_version" {
  description = "Cloud SQL Proxy version"
  type        = string
  default     = "2.14.0"
}

variable "bastion_users" {
  description = "List of IAM users allowed to access bastion (format: user:email@example.com or group:group@example.com)"
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# PAM Variables
# -----------------------------------------------------------------------------
variable "pam_eligible_users" {
  description = "List of principals eligible for PAM entitlements"
  type        = list(string)
  default     = []
}

variable "pam_approver_emails" {
  description = "List of approver email addresses for PAM requests"
  type        = list(string)
  default     = []
}

variable "pam_approver_groups" {
  description = "List of approver Google Groups for PAM requests"
  type        = list(string)
  default     = []
}

variable "pam_admin_emails" {
  description = "Admin email addresses for PAM notifications"
  type        = list(string)
  default     = []
}

variable "pam_max_request_duration" {
  description = "Maximum duration for PAM access requests"
  type        = string
  default     = "7200s"
}

# -----------------------------------------------------------------------------
# Monitoring Variables
# -----------------------------------------------------------------------------
variable "enable_monitoring" {
  description = "Enable Cloud Monitoring alerts"
  type        = bool
  default     = false
}

variable "monitoring_notification_channels" {
  description = "List of notification channel IDs for alerts"
  type        = list(string)
  default     = []
}
