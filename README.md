# GCP PAM + GCE Bastion + Cloud SQL Proxy (Terraform)

Terraform configuration to deploy a secure database access architecture on Google Cloud Platform using:

- **Privileged Access Manager (PAM)** — Just-in-time access approval workflow
- **GCE Bastion Host** — Hardened VM running Cloud SQL Auth Proxy
- **Cloud SQL (PostgreSQL)** — Private IP only, no public exposure
- **IAP Tunneling** — Identity-Aware Proxy for SSH and TCP forwarding
- **OS Login** — IAM-based SSH authentication

## Architecture

```
+-------------------------------------------------------------+
|                        User (DBeaver)                        |
|                          |                                   |
|              gcloud compute start-iap-tunnel               |
|                          |                                   |
+------------+-------------+----------------------------------+
             | IAP (35.235.240.0/20)
             v
+------------+----------------------------------+
|         GCE Bastion (no public IP)            |
|  +-----------------------------------------+  |
|  |     Cloud SQL Auth Proxy (localhost)    |  |
|  |         --private-ip --port 5432         |  |
|  +-----------------------------------------+  |
+----------------------+------------------------+
                       | Private VPC
                       v
+------------+----------------------------------+
|     Cloud SQL (PostgreSQL) - Private IP       |
+-----------------------------------------------+
```

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.5
- [gcloud CLI](https://cloud.google.com/sdk/docs/install)
- GCP Project with billing enabled
- APIs enabled:
  ```bash
  gcloud services enable compute.googleapis.com
  gcloud services enable sqladmin.googleapis.com
  gcloud services enable iam.googleapis.com
  gcloud services enable cloudresourcemanager.googleapis.com
  gcloud services enable privilegedaccessmanager.googleapis.com
  gcloud services enable iap.googleapis.com
  gcloud services enable monitoring.googleapis.com
  ```

## Quick Start

### 1. Clone and configure

```bash
git clone https://github.com/llmiell/gcp-pam-bastion-terraform.git
cd gcp-pam-bastion-terraform
```

Create `terraform.tfvars`:

```hcl
project_id = "your-gcp-project-id"
region     = "asia-southeast1"
zone       = "asia-southeast1-a"

bastion_users = [
  "user:dba1@yourcompany.com",
  "user:dba2@yourcompany.com",
]

pam_eligible_users = [
  "user:dba1@yourcompany.com",
  "user:dba2@yourcompany.com",
  "group:db-admins@yourcompany.com",
]

pam_approver_emails = [
  "manager@yourcompany.com",
]

pam_admin_emails = [
  "security@yourcompany.com",
]
```

### 2. Deploy

```bash
terraform init
terraform plan
terraform apply
```

### 3. Request access via PAM

Users must request access through **Privileged Access Manager** before connecting:

1. Go to [Google Cloud Console → Privileged Access Manager](https://console.cloud.google.com/security/pam)
2. Find the entitlement: `{name-prefix}-db-access`
3. Click **Request Access**
4. Fill justification and submit
5. Wait for approver (e.g., manager) to approve

### 4. Connect via IAP Tunnel

After PAM approval is granted:

```bash
# Option A: Create TCP tunnel to Cloud SQL Proxy
gcloud compute start-iap-tunnel BASTION_NAME 5432 \
  --zone=ZONE \
  --local-host-port=localhost:5433

# Option B: SSH into bastion directly
gcloud compute ssh BASTION_NAME \
  --zone=ZONE \
  --tunnel-through-iap
```

Then connect DBeaver to `localhost:5433`.

### 5. Connect DBeaver (No VPN Required)

See the detailed guide: [`docs/dbeaver-connection.md`](docs/dbeaver-connection.md)

Quick start:
```bash
# Start the tunnel helper
./scripts/start-dbeaver-tunnel.sh

# In DBeaver: Host=localhost, Port=5433, Database=appdb
```

This uses **IAP TCP forwarding** to reach the private Cloud SQL instance — no VPN, no public IP, no exposed firewall rules.

#### Why No VPN?

IAP TCP forwarding creates an encrypted tunnel over HTTPS directly from your laptop to the bastion. Google handles the tunnel — your traffic never touches the public internet unencrypted, and the bastion has no public IP at all.

| Approach | VPN | IAP Tunnel |
|----------|-----|------------|
| Client software | VPN client required | Only `gcloud` CLI |
| Network route | Into VPC subnet | Direct HTTPS tunnel |
| Bastion public IP | Sometimes needed | **Never needed** |
| Encryption | IPsec/SSL VPN | TLS 1.3 over HTTPS |
| Audit & control | Limited | Full IAM + PAM |

```
Your Laptop → gcloud start-iap-tunnel → Google IAP (TLS/443) → Bastion (private IP only)
   → Cloud SQL Proxy (localhost) → Cloud SQL (private IP)
```

The bastion lives entirely on the private network. IAP acts as the secure entrypoint.

## Variables

| Name | Description | Default |
|------|-------------|---------|
| `project_id` | GCP Project ID | (required) |
| `region` | GCP Region | `asia-southeast1` |
| `zone` | GCP Zone | `asia-southeast1-a` |
| `name_prefix` | Resource name prefix | `pam-bastion` |
| `db_version` | Cloud SQL version | `POSTGRES_15` |
| `db_tier` | Machine tier | `db-f1-micro` |
| `db_name` | Database name | `appdb` |
| `bastion_machine_type` | Bastion machine type | `e2-medium` |
| `bastion_users` | IAM principals allowed SSH access | `[]` |
| `pam_eligible_users` | PAM eligible principals | `[]` |
| `pam_approver_emails` | PAM approver emails | `[]` |
| `pam_max_request_duration` | Max PAM request duration | `7200s` |

See `variables.tf` for the complete list.

## Outputs

| Output | Description |
|--------|-------------|
| `cloud_sql_connection_name` | Connection name for Cloud SQL Proxy |
| `cloud_sql_private_ip` | Private IP of Cloud SQL |
| `bastion_instance_name` | Bastion GCE instance name |
| `iap_tunnel_command` | gcloud command to create IAP tunnel |
| `pam_entitlement_id` | PAM entitlement ID |

## Security Features

- ✅ **No public IP** on bastion or Cloud SQL
- ✅ **Private Google Access** for Cloud SQL private IP
- ✅ **IAP Tunneling** instead of open firewall rules
- ✅ **OS Login** with IAM-based SSH (no SSH keys to manage)
- ✅ **PAM Just-in-Time Access** with manual approval workflow
- ✅ **Cloud SQL Auth Proxy** with structured logging
- ✅ **Hardened SSH** (no password auth, no root login)
- ✅ **VPC Flow Logs** enabled on subnet

## Cost Optimization

For non-production or dev environments:

```hcl
# terraform.tfvars
db_tier              = "db-f1-micro"
db_high_availability = false
bastion_machine_type = "e2-small"
enable_monitoring    = false
```

## Troubleshooting

### IAP tunnel fails

```bash
# Verify IAM permissions
gcloud projects get-iam-policy PROJECT_ID \
  --flatten="bindings[].members" \
  --format='table(bindings.role)' \
  --filter="bindings.members:user:YOUR_EMAIL"

# Test IAP directly
gcloud compute ssh BASTION_NAME --zone=ZONE --tunnel-through-iap --dry-run
```

### Cloud SQL Proxy not starting

```bash
# SSH to bastion and check logs
gcloud compute ssh BASTION_NAME --zone=ZONE --tunnel-through-iap
sudo journalctl -u cloud-sql-proxy -f
```

### PAM request pending

- Ensure approver email is correct in `pam_approver_emails`
- Check PAM console for pending requests
- Approver must have `roles/privilegedaccessmanager.admin` or be listed in the entitlement

## License

MIT
