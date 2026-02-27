#!/bin/bash

# Exit on error
set -e

# --- Configuration ---
# You can pass these as arguments: ./ssh-keysetup.sh [alias] [user] [host] [port]
REMOTE_ALIAS="${1:-trailer}"           # Default: trailer
REMOTE_USER="${2:-your_username}"      # Default: your_username
REMOTE_HOST="${3:-192.168.1.100}"      # Default: 192.168.1.100
REMOTE_PORT="${4:-23}"                 # Default: 23 (Storage Box SFTP/SSH port)

USER_KEY_PATH="$HOME/.ssh/id_ed25519_$REMOTE_ALIAS"
ROOT_KEY_PATH="/root/.ssh/id_ed25519_$REMOTE_ALIAS"

# Function to update SSH config safely
update_ssh_config() {
    local config_file="$1"
    local alias="$2"
    local host="$3"
    local user="$4"
    local port="$5"
    local key="$6"
    local sudo_prefix="$7"

    if ! $sudo_prefix grep -q "Host $alias" "$config_file" 2>/dev/null; then
        echo "Adding shortcut '$alias' to $config_file..."
        $sudo_prefix tee -a "$config_file" > /dev/null <<EOF

Host $alias
    HostName $host
    User $user
    Port $port
    IdentityFile $key
EOF
    else
        echo "Shortcut '$alias' already exists in $config_file. Skipping."
    fi
}

# 1. Setup for Current User
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

if [ ! -f "$USER_KEY_PATH" ]; then
    echo "Generating new Ed25519 SSH key for $REMOTE_ALIAS..."
    ssh-keygen -t ed25519 -f "$USER_KEY_PATH" -N ""
fi

# Update SSH config BEFORE pushing the key so the local system knows how to connect
update_ssh_config "$HOME/.ssh/config" "$REMOTE_ALIAS" "$REMOTE_HOST" "$REMOTE_USER" "$REMOTE_PORT" "$USER_KEY_PATH" ""

echo "Pushing user key to $REMOTE_HOST (requires password)..."
# Using manual injection for compatibility (e.g., QNAP NAS)
cat "${USER_KEY_PATH}.pub" | ssh -p "$REMOTE_PORT" "$REMOTE_USER@$REMOTE_HOST" "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"

# 2. Setup for Root (Required for systemd services)
echo "Setting up dedicated root key for systemd services..."
sudo mkdir -p /root/.ssh
sudo chmod 700 /root/.ssh

if ! sudo [ -f "$ROOT_KEY_PATH" ]; then
    echo "Generating new dedicated root SSH key..."
    sudo ssh-keygen -t ed25519 -f "$ROOT_KEY_PATH" -N ""
fi

# Update root SSH config so root can use the alias
update_ssh_config "/root/.ssh/config" "$REMOTE_ALIAS" "$REMOTE_HOST" "$REMOTE_USER" "$REMOTE_PORT" "$ROOT_KEY_PATH" "sudo"

echo "Pushing root key to $REMOTE_HOST (may require password)..."
# Using manual injection for compatibility (e.g., QNAP NAS)
sudo cat "${ROOT_KEY_PATH}.pub" | ssh -p "$REMOTE_PORT" "$REMOTE_USER@$REMOTE_HOST" "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"

echo "Success! Both you and systemd services (root) can now connect via: ssh $REMOTE_ALIAS"
