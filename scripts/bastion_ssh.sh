#!/bin/bash

# OCI Bastion SSH Connect Script v1.3 (Portable)
# This script creates a Managed SSH session and optionally connects to the instance.

set -e

# --- Configuration ---
export PYTHONWARNINGS="ignore" # Suppress OCI CLI warnings

# --- Default Values ---
SSH_PRIV_KEY_FILE="$HOME/.ssh/id_rsa"
AUTO_CONNECT=false
TTL=10800 # 3 hours in seconds

# --- Help Message ---
show_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -i <key_path>  SSH private key path (default: $HOME/.ssh/id_rsa)"
    echo "  -c             Connect automatically after creating session"
    echo "  -t <seconds>   Session TTL in seconds (default: 10800)"
    echo "  -d <tf_dir>    Path to terraform directory (default: auto-detect)"
    echo "  -h             Show this help message"
}

# --- Parse Arguments ---
while getopts "i:ct:d:h" opt; do
    case "$opt" in
        i) SSH_PRIV_KEY_FILE=$OPTARG ;;
        c) AUTO_CONNECT=true ;;
        t) TTL=$OPTARG ;;
        d) MANUAL_TF_DIR=$OPTARG ;;
        h) show_help; exit 0 ;;
        *) show_help; exit 1 ;;
    esac
done

SSH_PUB_KEY_FILE="${SSH_PRIV_KEY_FILE}.pub"

echo "=== OCI Bastion SSH Connect Script v1.3 ==="

# --- Check Requirements ---
if ! command -v oci &> /dev/null; then
    echo "Error: oci-cli is not installed."
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed."
    exit 1
fi

if [ ! -f "$SSH_PUB_KEY_FILE" ]; then
    echo "Error: SSH public key file not found: $SSH_PUB_KEY_FILE"
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
echo "[1/4] Terraformから情報を取得中... (Dir: $TF_DIR)"
TF_OUTPUT=$(cd "$TF_DIR" && terraform output -json)

BASTION_ID=$(echo "$TF_OUTPUT" | jq -r '.bastion_ocid.value // empty')
TARGET_INSTANCE_ID=$(echo "$TF_OUTPUT" | jq -r '.instance_ocid.value // empty')
OS_USERNAME=$(echo "$TF_OUTPUT" | jq -r '.instance_user.value // "seiya"')

if [ -z "$BASTION_ID" ] || [ -z "$TARGET_INSTANCE_ID" ]; then
    echo "Error: terraform output から必要な情報が取得できませんでした。"
    exit 1
fi

echo "  Bastion ID: $BASTION_ID"
echo "  Target ID: $TARGET_INSTANCE_ID"
echo "  User: $OS_USERNAME"

# --- Check for Existing Session ---
echo "[2/4] 既存の有効なセッションを確認中..."
EXISTING_SESSION=$(oci bastion session list --bastion-id "$BASTION_ID" --all | jq -r --arg target "$TARGET_INSTANCE_ID" --arg user "$OS_USERNAME" '.data[] | select(."lifecycle-state" == "ACTIVE" and ."target-resource-details"."target-resource-id" == $target and ."target-resource-details"."target-resource-operating-system-user-name" == $user) | .id' | head -n 1)

if [ -n "$EXISTING_SESSION" ]; then
    echo "  有効な既存セッションが見つかりました: $EXISTING_SESSION"
    SESSION_ID="$EXISTING_SESSION"
else
    # --- Create Bastion Session ---
    echo "[2/4] 新しいBastionセッションを作成中... (1〜2分かかります)"
    CREATE_JSON=$(oci bastion session create-managed-ssh \
        --bastion-id "$BASTION_ID" \
        --target-resource-id "$TARGET_INSTANCE_ID" \
        --target-os-username "$OS_USERNAME" \
        --ssh-public-key-file "$SSH_PUB_KEY_FILE" \
        --session-ttl "$TTL")
    
    SESSION_ID=$(echo "$CREATE_JSON" | jq -r '.data.id')
    
    if [ -z "$SESSION_ID" ] || [ "$SESSION_ID" == "null" ]; then
        echo "Error: セッションの作成に失敗しました。"
        echo "$CREATE_JSON"
        exit 1
    fi
    
    echo "  セッション作成リクエスト完了 (ID: $SESSION_ID)"
    echo "[3/4] セッションがアクティブになるのを待機中..."
    
    # Wait for session to be ACTIVE
    oci bastion session get --session-id "$SESSION_ID" --wait-for-state ACTIVE --wait-interval-seconds 10 > /dev/null
fi

# --- Get Session Details ---
echo "[4/4] 接続情報を取得中..."
SESSION_JSON=$(oci bastion session get --session-id "$SESSION_ID")
SSH_COMMAND=$(echo "$SESSION_JSON" | jq -r '.data."ssh-metadata".command')

if [ -n "$SSH_COMMAND" ] && [ "$SSH_COMMAND" != "null" ]; then
    # Use // to replace ALL occurrences of <privateKey>
    EXEC_COMMAND="${SSH_COMMAND//<privateKey>/$SSH_PRIV_KEY_FILE}"
    
    echo "--------------------------------------------------"
    echo "SSH接続コマンド:"
    echo "$EXEC_COMMAND"
    echo "--------------------------------------------------"
    
    if [ "$AUTO_CONNECT" = true ]; then
        echo "SSH接続を開始します..."
        eval "$EXEC_COMMAND"
    fi
else
    echo "Error: SSHコマンドの取得に失敗しました。セッション状態を確認してください。"
    echo "Session JSON: $SESSION_JSON"
    exit 1
fi
