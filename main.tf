terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

# -----------------------------------------------------------------------------
# VPC Network
# -----------------------------------------------------------------------------
resource "google_compute_network" "vpc" {
  name                    = "${var.name_prefix}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  name          = "${var.name_prefix}-subnet"
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.vpc.id

  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# -----------------------------------------------------------------------------
# Cloud SQL Instance (PostgreSQL)
# -----------------------------------------------------------------------------
resource "google_sql_database_instance" "main" {
  name             = "${var.name_prefix}-db"
  database_version = var.db_version
  region           = var.region

  depends_on = [google_service_networking_connection.private_vpc_connection]

  settings {
    tier              = var.db_tier
    availability_type = var.db_high_availability ? "REGIONAL" : "ZONAL"

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.vpc.id
    }

    backup_configuration {
      enabled            = true
      start_time         = "03:00"
      location           = var.region
      point_in_time_recovery_enabled = true
    }

    insights_config {
      query_insights_enabled  = true
      query_string_length     = 1024
      record_application_tags = true
      record_client_address   = true
    }
  }

  deletion_protection = var.db_deletion_protection
}

resource "google_sql_database" "app" {
  name     = var.db_name
  instance = google_sql_database_instance.main.name
}

# -----------------------------------------------------------------------------
# Private Service Access for Cloud SQL
# -----------------------------------------------------------------------------
resource "google_compute_global_address" "private_ip_alloc" {
  name          = "${var.name_prefix}-private-ip-alloc"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc.id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_alloc.name]
}

# -----------------------------------------------------------------------------
# GCE Bastion Host
# -----------------------------------------------------------------------------
resource "google_compute_instance" "bastion" {
  name         = "${var.name_prefix}-bastion"
  machine_type = var.bastion_machine_type
  zone         = var.zone

  tags = ["bastion", "iap-ssh"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 20
      type  = "pd-standard"
    }
  }

  network_interface {
    network    = google_compute_network.vpc.id
    subnetwork = google_compute_subnetwork.subnet.id

    # No external IP - access via IAP only
  }

  metadata = {
    enable-os-login = "TRUE"
    user-data       = templatefile("${path.module}/cloud-init.yaml", {
      db_instance_connection_name = google_sql_database_instance.main.connection_name
      cloud_sql_proxy_version     = var.cloud_sql_proxy_version
      db_port                     = var.db_port
    })
  }

  service_account {
    email  = google_service_account.bastion.email
    scopes = ["cloud-platform"]
  }

  allow_stopping_for_update = true
}

# -----------------------------------------------------------------------------
# Bastion Service Account
# -----------------------------------------------------------------------------
resource "google_service_account" "bastion" {
  account_id   = "${var.name_prefix}-bastion"
  display_name = "Bastion Host Service Account"
  description  = "Service account for the GCE bastion running Cloud SQL Proxy"
}

resource "google_project_iam_member" "bastion_sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.bastion.email}"
}

# -----------------------------------------------------------------------------
# Firewall Rules
# -----------------------------------------------------------------------------
resource "google_compute_firewall" "allow_iap_ssh" {
  name        = "${var.name_prefix}-allow-iap-ssh"
  network     = google_compute_network.vpc.id
  direction   = "INGRESS"
  source_ranges = ["35.235.240.0/20"] # IAP IP range

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  target_tags = ["iap-ssh"]
}

# Allow bastion to reach Cloud SQL (private IP)
resource "google_compute_firewall" "allow_bastion_to_sql" {
  name        = "${var.name_prefix}-allow-bastion-sql"
  network     = google_compute_network.vpc.id
  direction   = "INGRESS"
  source_tags = ["bastion"]

  allow {
    protocol = "tcp"
    ports    = [var.db_port]
  }
}

# -----------------------------------------------------------------------------
# IAP Tunnel IAM Binding
# -----------------------------------------------------------------------------
resource "google_project_iam_member" "iap_tunnel_user" {
  for_each = toset(var.bastion_users)

  project = var.project_id
  role    = "roles/iap.tunnelResourceAccessor"
  member  = each.value
}

resource "google_compute_instance_iam_member" "bastion_iam_binding" {
  for_each = toset(var.bastion_users)

  project       = var.project_id
  zone          = var.zone
  instance_name = google_compute_instance.bastion.name
  role          = "roles/compute.instanceAdmin.v1"
  member        = each.value
}

# -----------------------------------------------------------------------------
# OS Login IAM (for SSH access)
# -----------------------------------------------------------------------------
resource "google_project_iam_member" "os_login_users" {
  for_each = toset(var.bastion_users)

  project = var.project_id
  role    = "roles/compute.osLogin"
  member  = each.value
}

# -----------------------------------------------------------------------------
# Privileged Access Manager (PAM) Entitlement
# -----------------------------------------------------------------------------
resource "google_privileged_access_manager_entitlement" "db_access" {
  provider     = google-beta
  entitlement_id = "${var.name_prefix}-db-access"
  location       = "global"
  parent         = "projects/${var.project_id}"
  max_request_duration = var.pam_max_request_duration

  eligible_users {
    principals = var.pam_eligible_users
  }

  privileged_access {
    gcp_iam_access {
      role_bindings {
        role = "roles/iap.tunnelResourceAccessor"
        condition_expression = "resource.name == 'projects/${var.project_id}/zones/${var.zone}/instances/${google_compute_instance.bastion.name}'"
      }
      role_bindings {
        role = "roles/compute.osLogin"
      }
      resource_type = "cloudresourcemanager.googleapis.com/Project"
      resource      = "projects/${var.project_id}"
    }
  }

  requester_justification_config {
    unstructured {}
  }

  additional_notification_targets {
    admin_email_addresses = var.pam_admin_emails
  }

  approval_workflow {
    manual_approvals {
      require_approver_justification = true
      steps {
        approvals_needed = 1
        approver_email_addresses = var.pam_approver_emails
        approver_groups = var.pam_approver_groups
      }
    }
  }
}

# -----------------------------------------------------------------------------
# Cloud Monitoring (optional)
# -----------------------------------------------------------------------------
resource "google_monitoring_alert_policy" "bastion_cpu" {
  count = var.enable_monitoring ? 1 : 0

  display_name = "${var.name_prefix}-bastion-high-cpu"
  combiner     = "OR"

  conditions {
    display_name = "CPU utilization"
    condition_threshold {
      filter          = "resource.type=\"gce_instance\" AND metric.type=\"compute.googleapis.com/instance/cpu/utilization\" AND resource.labels.instance_name=\"${google_compute_instance.bastion.name}\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0.8

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = var.monitoring_notification_channels
  alert_strategy {
    auto_close = "86400s"
  }
}
