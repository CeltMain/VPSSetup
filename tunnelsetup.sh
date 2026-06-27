#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# --- SETTINGS ---
USERNAME="sshtunneluser"
# ------------------

echo "=== Starting SSH Tunnel User Configuration ==="

# 1. Check root privileges
if [ "$EUID" -ne 0 ]; then
  echo "Error: This script must be run as root or via sudo!"
  exit 1
fi

# 2. Create user if it doesn't exist
if id "$USERNAME" &>/dev/null; then
  echo "User '$USERNAME' already exists. Skipping creation."
else
  echo "Creating user '$USERNAME' with blocked shell..."
  useradd -m -s /bin/false "$USERNAME"
fi

# 3. Setup .ssh directory
SSH_DIR="/home/$USERNAME/.ssh"

if [ -d "$SSH_DIR" ]; then
  echo "Directory $SSH_DIR already exists. Updating ownership..."
else
  echo "Creating directory $SSH_DIR..."
  mkdir -p "$SSH_DIR"
fi

# [FIXED] Force correct ownership for the entire home directory and all moved files
echo "Fixing ownership and permissions for $USERNAME home directory..."
chown -R "$USERNAME:$USERNAME" "/home/$USERNAME"

# Set strict permissions for directories and files to satisfy SSH StrictModes
chmod 750 "/home/$USERNAME"
chmod 700 "$SSH_DIR"

if [ -f "$SSH_DIR/authorized_keys" ]; then
  chmod 600 "$SSH_DIR/authorized_keys"
fi
if [ -f "$SSH_DIR/id_ed25519.pub" ]; then
  chmod 644 "$SSH_DIR/id_ed25519.pub"
fi

# 4. Configure /etc/ssh/sshd_config
SSHD_CONFIG="/etc/ssh/sshd_config"

# Check if configuration already exists to prevent duplication
if grep -q "Match User $USERNAME" "$SSHD_CONFIG"; then
  echo "Match User configuration for $USERNAME already exists in $SSHD_CONFIG. Skipping."
else
  echo "Adding security restrictions to the end of $SSHD_CONFIG..."
  cat << 'EOF' >> "$SSHD_CONFIG"

# Security settings for SSH tunnel user
Match User sshtunneluser
    AllowTcpForwarding yes
    X11Forwarding no
    PermitTTY no
    ForceCommand echo "This account is for SSH tunneling only."
EOF
fi

# 5. Validate configuration before restart
echo "Checking SSH configuration for syntax errors..."
if ! sshd -t; then
  echo "Error: Syntax errors found in $SSHD_CONFIG! Please fix them manually."
  exit 1
fi

# 6. Restart SSH service
echo "Restarting SSH service..."
if systemctl is-active --quiet sshd; then
  systemctl restart sshd
elif systemctl is-active --quiet ssh; then
  systemctl restart ssh
else
  echo "Warning: Could not determine SSH service name. Please restart it manually."
fi

echo "=== Configuration successfully completed! ==="
echo "All done. The user, directories, and keys are perfectly secured."
