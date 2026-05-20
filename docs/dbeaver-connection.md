# DBeaver Connection Guide

Connect DBeaver (or any PostgreSQL client) to your **private Cloud SQL** instance **without a VPN**, using an **IAP tunnel through the bastion**.

---

## Overview

Traditional access to a private Cloud SQL instance requires:
- A VPN into the VPC
- Or a public IP with SSL (security risk)

This architecture bypasses both by using:
1. **Privileged Access Manager (PAM)** — JIT approval for access
2. **IAP TCP Tunneling** — encrypted tunnel over HTTPS, no VPN needed
3. **Cloud SQL Proxy on Bastion** — secure local proxy inside the VPC

> **No VPN is required.** IAP TCP forwarding creates a TLS tunnel directly from your laptop to the bastion over HTTPS (port 443). The bastion has **no public IP** and lives entirely on the private network. IAP is Google's built-in zero-trust access layer — it replaces the VPN for admin access.

Your connection path:

```
Your Laptop
    |
    |  gcloud start-iap-tunnel (TLS/HTTPS)
    v
Google IAP (35.235.240.0/20)
    |
    |  forwarded TCP
    v
GCE Bastion (private IP only)
    |
    |  localhost:5432
    v
Cloud SQL Auth Proxy
    |
    |  private VPC
    v
Cloud SQL (Private IP)
```

---

## Prerequisites

- PAM access request **approved** (see [README.md](../README.md))
- [gcloud CLI](https://cloud.google.com/sdk/docs/install) authenticated
- DBeaver installed ([download](https://dbeaver.io/download/))
- `roles/iap.tunnelResourceAccessor` granted (via PAM approval)

---

## Step 1: Start the IAP Tunnel

Open a terminal and keep it running:

```bash
# Using the helper script (recommended)
./scripts/start-dbeaver-tunnel.sh

# Or manually:
gcloud compute start-iap-tunnel $(terraform output -raw bastion_instance_name) 5432 \
  --zone=$(terraform output -raw bastion_zone) \
  --local-host-port=localhost:5433 \
  --project=$(terraform output -raw project_id)
```

You should see:
```
Listening on port [5433].
```

**Keep this terminal open.** The tunnel stays alive as long as the process runs.

---

## Step 2: Configure DBeaver

1. Open DBeaver → **New Database Connection** (or Ctrl+N)
2. Select **PostgreSQL** → **Next**
3. Fill in the connection settings:

| Field | Value | Notes |
|-------|-------|-------|
| **Host** | `localhost` | The IAP tunnel listens on your local machine |
| **Port** | `5433` | Matches `--local-host-port` from Step 1 |
| **Database** | `appdb` | Or your configured `db_name` |
| **Username** | `postgres` | Or an IAM database user |
| **Password** | *(your password)* | Or IAM auth OAuth token |

4. Click **Test Connection**

If successful, you’ll see:
```
Connected
```

5. Click **Finish** to save the connection

---

## Step 3: IAM Database Authentication (Optional but Recommended)

Instead of native PostgreSQL passwords, use your Google identity:

### 1. Enable IAM auth on the database user

```bash
gcloud sql users create dba1@yourcompany.com \
  --instance=$(terraform output -raw cloud_sql_instance_name) \
  --type=cloud_iam_user
```

### 2. Get an OAuth token for the password

```bash
gcloud auth print-access-token
```

### 3. In DBeaver

- **Username**: your full IAM email (e.g., `dba1@yourcompany.com`)
- **Password**: paste the token from Step 2
- The token expires in ~1 hour — for long sessions, use a service account key or native auth

---

## Troubleshooting

### "Connection refused" in DBeaver

| Cause | Fix |
|-------|-----|
| Tunnel not running | Check Step 1 terminal is still open |
| Wrong local port | Ensure DBeaver port matches `--local-host-port` |
| PAM access expired | Re-request access in PAM console |
| gcloud not authenticated | Run `gcloud auth login` |

### "Permission denied" from IAP

```bash
# Verify your IAM
gcloud projects get-iam-policy YOUR_PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:user:$(gcloud config get-value account)"
```

Ensure `roles/iap.tunnelResourceAccessor` is present.

### "Cloud SQL Proxy not listening" on bastion

SSH to the bastion and check:
```bash
gcloud compute ssh BASTION_NAME --zone=ZONE --tunnel-through-iap
sudo systemctl status cloud-sql-proxy
sudo journalctl -u cloud-sql-proxy -n 50
```

### Tunnel disconnects after idle

Add `--iap-tunnel-disable-keepalive` if behind a corporate proxy, or use a persistent connection wrapper:
```bash
while true; do
  gcloud compute start-iap-tunnel ...
  sleep 2
done
```

---

## Alternative: Direct VPN Connection

If your organization requires VPN instead of IAP, deploy a Cloud VPN:

```hcl
# Add to terraform.tfvars
enable_vpn = true
vpn_peer_ip = "YOUR_ON_PREM_GATEWAY_IP"
```

Then connect DBeaver directly to the Cloud SQL private IP on port 5432.

See `modules/vpn/` (contributions welcome) for a full VPN module.

---

## Security Notes

- The tunnel is **encrypted end-to-end** (TLS via IAP)
- No Cloud SQL public IP is exposed
- Access is **time-bounded** by PAM approval duration
- All connections are **logged** in Cloud Audit Logs
- The bastion has **no public IP** and runs only the proxy
