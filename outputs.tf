output "vpc_network_id" {
  description = "VPC Network ID"
  value       = google_compute_network.vpc.id
}

output "subnet_id" {
  description = "Subnet ID"
  value       = google_compute_subnetwork.subnet.id
}

output "cloud_sql_instance_name" {
  description = "Cloud SQL instance name"
  value       = google_sql_database_instance.main.name
}

output "cloud_sql_connection_name" {
  description = "Cloud SQL connection name for proxy"
  value       = google_sql_database_instance.main.connection_name
}

output "cloud_sql_private_ip" {
  description = "Cloud SQL private IP address"
  value       = google_sql_database_instance.main.ip_address.0.ip_address
}

output "bastion_instance_name" {
  description = "Bastion GCE instance name"
  value       = google_compute_instance.bastion.name
}

output "bastion_zone" {
  description = "Bastion GCE zone"
  value       = google_compute_instance.bastion.zone
}

output "bastion_service_account" {
  description = "Bastion service account email"
  value       = google_service_account.bastion.email
}

output "pam_entitlement_id" {
  description = "PAM Entitlement ID"
  value       = google_privileged_access_manager_entitlement.db_access.entitlement_id
}

output "iap_ssh_command" {
  description = "Command to SSH into bastion via IAP"
  value       = "gcloud compute ssh ${google_compute_instance.bastion.name} --zone=${var.zone} --tunnel-through-iap"
}

output "iap_tunnel_command" {
  description = "Command to create IAP tunnel to Cloud SQL Proxy"
  value       = "gcloud compute start-iap-tunnel ${google_compute_instance.bastion.name} ${var.db_port} --zone=${var.zone} --local-host-port=localhost:${var.db_port}"
}
