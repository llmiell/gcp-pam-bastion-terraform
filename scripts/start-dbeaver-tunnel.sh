#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Start IAP tunnel for DBeaver to connect to Cloud SQL Proxy on bastion
# No VPN required — uses Identity-Aware Proxy (IAP) TCP forwarding
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Detect if running from terraform project
if [ -f "$PROJECT_ROOT/terraform.tfstate" ] || [ -f "$PROJECT_ROOT/main.tf" ]; then
  echo "[✓] Detected Terraform project"
  cd "$PROJECT_ROOT"
else
  echo "[!] Not inside Terraform project. Set variables manually or run from repo root."
fi

# Read from terraform outputs if available
if command -v terraform &>/dev/null && [ -f "terraform.tfstate" ]; then
  echo "[✓] Reading outputs from Terraform..."
  BASTION_NAME=$(terraform output -raw bastion_instance_name 2>/dev/null || echo "")
  ZONE=$(terraform output -raw bastion_zone 2>/dev/null || echo "")
  PROJECT_ID=$(terraform output -raw project_id 2>/dev/null || echo "")
  DB_PORT=$(terraform output -raw db_port 2>/dev/null || echo "5432")
else
  BASTION_NAME=""
  ZONE=""
  PROJECT_ID=""
  DB_PORT="5432"
fi

# Fallback to environment variables
BASTION_NAME="${BASTION_NAME:-${BASTION_INSTANCE_NAME:-}}"
ZONE="${ZONE:-${BASTION_ZONE:-asia-southeast1-a}}"
PROJECT_ID="${PROJECT_ID:-${GOOGLE_PROJECT:-}}"
DB_PORT="${DB_PORT:-5432}"
LOCAL_PORT="${LOCAL_PORT:-5433}"

# Validate
if [ -z "$BASTION_NAME" ]; then
  echo "Error: Could not determine bastion instance name."
  echo "Set BASTION_INSTANCE_NAME or run from Terraform project root."
  exit 1
fi

if [ -z "$PROJECT_ID" ]; then
  echo "Error: Could not determine GCP project ID."
  echo "Set GOOGLE_PROJECT or run from Terraform project root."
  exit 1
fi

echo "================================================"
echo "  DBeaver IAP Tunnel — Cloud SQL (No VPN)"
echo "================================================"
echo "Bastion:     $BASTION_NAME"
echo "Zone:        $ZONE"
echo "Project:     $PROJECT_ID"
echo "Local Port:  $LOCAL_PORT"
echo "Remote Port: $DB_PORT"
echo "================================================"
echo ""
echo "DBeaver connection settings:"
echo "  Host:     localhost"
echo "  Port:     $LOCAL_PORT"
echo "  Database: appdb (or your db_name)"
echo ""
echo "Press Ctrl+C to stop the tunnel"
echo ""

# Start tunnel
exec gcloud compute start-iap-tunnel "$BASTION_NAME" "$DB_PORT" \
  --zone="$ZONE" \
  --project="$PROJECT_ID" \
  --local-host-port="localhost:$LOCAL_PORT"
