#!/bin/bash
# Run this after every terraform apply to refresh SSH config and Ansible group_vars with current IPs.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/../terraform"
ANSIBLE_DIR="$SCRIPT_DIR/../ansible"
KEY_FILE="${SSH_KEY_FILE:-$HOME/.ssh/voting-app-key.pem}"
SSH_CONFIG="$HOME/.ssh/config"
MARKER_START="# --- voting-app managed block (auto-generated) ---"
MARKER_END="# --- end voting-app managed block ---"

# Read IPs from Terraform outputs
echo "Reading Terraform outputs..."
BASTION_IP=$(terraform -chdir="$TF_DIR" output -raw bastion_public_ip)
FRONTEND_PUBLIC_IP=$(terraform -chdir="$TF_DIR" output -raw instance_a_public_ip)
FRONTEND_IP=$(terraform -chdir="$TF_DIR" output -raw instance_a_private_ip)
BACKEND_IP=$(terraform -chdir="$TF_DIR" output -raw instance_b_private_ip)
DB_IP=$(terraform -chdir="$TF_DIR" output -raw instance_c_private_ip)

echo "  Bastion:               $BASTION_IP"
echo "  Instance A (frontend): $FRONTEND_PUBLIC_IP (public) / $FRONTEND_IP (private)"
echo "  Instance B (backend):  $BACKEND_IP"
echo "  Instance C (db):       $DB_IP"

# --- Update ~/.ssh/config ---
NEW_BLOCK="$MARKER_START
Host bastion
  HostName $BASTION_IP
  User ubuntu
  IdentityFile $KEY_FILE
  StrictHostKeyChecking no

Host frontend-instance-1
  HostName $FRONTEND_IP
  User ubuntu
  ProxyJump bastion
  IdentityFile $KEY_FILE
  StrictHostKeyChecking no

Host backend-instance-1
  HostName $BACKEND_IP
  User ubuntu
  ProxyJump bastion
  IdentityFile $KEY_FILE
  StrictHostKeyChecking no

Host db-instance-1
  HostName $DB_IP
  User ubuntu
  ProxyJump bastion
  IdentityFile $KEY_FILE
  StrictHostKeyChecking no
$MARKER_END"

touch "$SSH_CONFIG"
chmod 600 "$SSH_CONFIG"

if grep -q "$MARKER_START" "$SSH_CONFIG"; then
  sed -i "/$MARKER_START/,/$MARKER_END/d" "$SSH_CONFIG"
fi

echo "" >> "$SSH_CONFIG"
echo "$NEW_BLOCK" >> "$SSH_CONFIG"

echo ""
echo "SSH config updated."

# --- Update Ansible group_vars ---
cat > "$ANSIBLE_DIR/group_vars/backend.yml" <<EOF
redis_host: "$BACKEND_IP"
db_host: "$DB_IP"
db_username: "postgres"
db_password: "postgres"
db_name: "postgres"
EOF

cat > "$ANSIBLE_DIR/group_vars/frontend.yml" <<EOF
redis_host: "$BACKEND_IP"
pg_host: "$DB_IP"
pg_user: "postgres"
pg_password: "postgres"
pg_database: "postgres"
EOF

echo "Ansible group_vars updated."
echo ""
echo "Done! New IPs:"
echo "  Bastion:    $BASTION_IP (public)"
echo "  Instance A: $FRONTEND_PUBLIC_IP (public) / $FRONTEND_IP (private)"
echo "  Instance B: $BACKEND_IP (private)"
echo "  Instance C: $DB_IP (private)"
echo ""
echo "App URLs:"
echo "  Vote:   http://$FRONTEND_PUBLIC_IP:8080"
echo "  Result: http://$FRONTEND_PUBLIC_IP:8081"
echo ""
echo "Test SSH: ssh bastion"
echo "          ssh frontend-instance-1"
echo "          ssh backend-instance-1"
echo "          ssh db-instance-1"
