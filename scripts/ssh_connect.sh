#!/bin/bash

# OCI SSH Connect Script v1.1
# This script connects directly to the Compute instance using its public IP address.

set -e

# --- Default Values ---
SSH_PRIV_KEY_FILE="$HOME/.ssh/id_rsa"

# --- Help Message ---
show_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -i <key_path>  SSH private key path (default: $HOME/.ssh/id_rsa)"
    echo "  -d <tf_dir>    Path to terraform directory (default: auto-detect)"
    echo "  -h             Show this help message"
}

# --- Parse Arguments ---
while getopts "i:d:h" opt; do
    case "$opt" in
        i) SSH_PRIV_KEY_FILE=$OPTARG ;;
        d) MANUAL_TF_DIR=$OPTARG ;;
        h) show_help; exit 0 ;;
        *) show_help; exit 1 ;;
    esac
done

echo "=== OCI SSH Connect Script v1.1 ==="

# --- Check Requirements ---
if [ ! -f "$SSH_PRIV_KEY_FILE" ]; then
    echo "Error: SSH private key file not found: $SSH_PRIV_KEY_FILE"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed."
    exit 1
fi

# --- Find Terraform Directory ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -n "$MANUAL_TF_DIR" ]; then
    TF_DIR="$MANUAL_TF_DIR"
else
    # Auto-detect logic
    # 1. Check local (for infra-oci-terraform repo)
    # 2. Check sibling (for infra-oci-ansible repo)
    # 3. Check absolute standard path
    if [ -d "$SCRIPT_DIR/../terraform" ]; then
        TF_DIR="$SCRIPT_DIR/../terraform"
    elif [ -d "$SCRIPT_DIR/../../infra-oci-terraform/terraform" ]; then
        TF_DIR="$SCRIPT_DIR/../../infra-oci-terraform/terraform"
    elif [ -d "$HOME/git/infra-oci-terraform/terraform" ]; then
        TF_DIR="$HOME/git/infra-oci-terraform/terraform"
    else
        echo "Error: Terraformディレクトリが見つかりませんでした。"
        echo "  -d オプションでディレクトリを指定してください。"
        exit 1
    fi
fi

# --- Get Info from Terraform ---
echo "[1/2] Terraformから情報を取得中... (Dir: $TF_DIR)"
TF_OUTPUT=$(cd "$TF_DIR" && terraform output -json)

INSTANCE_IP=$(echo "$TF_OUTPUT" | jq -r '.instance_public_ip.value // empty')
OS_USERNAME=$(echo "$TF_OUTPUT" | jq -r '.instance_user.value // "seiya"')

if [ -z "$INSTANCE_IP" ]; then
    echo "Error: terraform output からパブリックIPアドレス (instance_public_ip) が取得できませんでした。"
    exit 1
fi

echo "  Instance IP: $INSTANCE_IP"
echo "  User: $OS_USERNAME"
echo "  Key: $SSH_PRIV_KEY_FILE"

# --- Execute SSH ---
echo "[2/2] SSH接続を開始します..."
echo "ssh -i $SSH_PRIV_KEY_FILE ${OS_USERNAME}@${INSTANCE_IP}"
ssh -i "$SSH_PRIV_KEY_FILE" "${OS_USERNAME}@${INSTANCE_IP}"
