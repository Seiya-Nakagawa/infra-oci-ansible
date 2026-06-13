#!/bin/bash
# OCI Bastion & Ansible Run Wrapper v1.0
set -e

# --- Configuration ---
export PYTHONWARNINGS="ignore" # Suppress OCI CLI warnings
SSH_PRIV_KEY_FILE="$HOME/.ssh/id_rsa"
TTL=10800 # 3 hours

# --- Help ---
show_help() {
    echo "Usage: $0 [ansible-playbook-options]"
    echo "This script manages OCI Bastion session and runs ansible-playbook via Bastion."
    echo "All options will be passed directly to ansible-playbook."
}

if [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
    show_help
    exit 0
fi

# --- Find Terraform Directory ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -d "$SCRIPT_DIR/../terraform" ]; then
    TF_DIR="$SCRIPT_DIR/../terraform"
elif [ -d "$SCRIPT_DIR/../../infra-oci-terraform/terraform" ]; then
    TF_DIR="$SCRIPT_DIR/../../infra-oci-terraform/terraform"
elif [ -d "$HOME/git/infra-oci-terraform/terraform" ]; then
    TF_DIR="$HOME/git/infra-oci-terraform/terraform"
else
    echo "Error: Terraform directory not found."
    exit 1
fi

echo "=== [1/4] Terraformから情報を取得中... ==="
TF_OUTPUT=$(cd "$TF_DIR" && terraform output -json)

BASTION_ID=$(echo "$TF_OUTPUT" | jq -r '.bastion_ocid.value // empty')
TARGET_INSTANCE_ID=$(echo "$TF_OUTPUT" | jq -r '.instance_ocid.value // empty')
OS_USERNAME=$(echo "$TF_OUTPUT" | jq -r '.instance_user.value // "seiya"')

if [ -z "$BASTION_ID" ] || [ -z "$TARGET_INSTANCE_ID" ]; then
    echo "Error: Could not retrieve Bastion ID or Instance ID from terraform output."
    exit 1
fi

echo "  Bastion ID: $BASTION_ID"
echo "  Target ID : $TARGET_INSTANCE_ID"
echo "  User      : $OS_USERNAME"

# --- Check/Create Bastion Session ---
echo "=== [2/4] 既存のBastionセッションを確認中... ==="
EXISTING_SESSION=$(oci bastion session list --bastion-id "$BASTION_ID" --all | jq -r --arg target "$TARGET_INSTANCE_ID" --arg user "$OS_USERNAME" '.data[] | select(."lifecycle-state" == "ACTIVE" and ."target-resource-details"."target-resource-id" == $target and ."target-resource-details"."target-resource-operating-system-user-name" == $user) | .id' | head -n 1)

if [ -n "$EXISTING_SESSION" ]; then
    echo "  有効な既存セッションが見つかりました: $EXISTING_SESSION"
    SESSION_ID="$EXISTING_SESSION"
else
    echo "  新しいBastionセッションを作成中... (1〜2分かかります)"
    CREATE_JSON=$(oci bastion session create-managed-ssh \
        --bastion-id "$BASTION_ID" \
        --target-resource-id "$TARGET_INSTANCE_ID" \
        --target-os-username "$OS_USERNAME" \
        --ssh-public-key-file "${SSH_PRIV_KEY_FILE}.pub" \
        --session-ttl "$TTL")
    
    SESSION_ID=$(echo "$CREATE_JSON" | jq -r '.data.id')
    
    if [ -z "$SESSION_ID" ] || [ "$SESSION_ID" == "null" ]; then
        echo "Error: Failed to create bastion session."
        echo "$CREATE_JSON"
        exit 1
    fi
    
    echo "  セッション作成リクエスト完了 (ID: $SESSION_ID)"
    echo "  セッションがアクティブになるのを待機中..."
    
    while true; do
        STATE=$(oci bastion session get --session-id "$SESSION_ID" | jq -r '.data."lifecycle-state"')
        if [ "$STATE" == "ACTIVE" ]; then
            echo "  セッションがアクティブになりました。"
            break
        elif [ "$STATE" == "FAILED" ] || [ "$STATE" == "DELETED" ] || [ "$STATE" == "DELETING" ]; then
            echo "Error: Session status became $STATE."
            exit 1
        fi
        sleep 10
    done
fi

echo "=== [3/4] 接続コマンドからProxyCommandを抽出中... ==="
SESSION_JSON=$(oci bastion session get --session-id "$SESSION_ID")
SSH_COMMAND=$(echo "$SESSION_JSON" | jq -r '.data."ssh-metadata".command')

if [ -z "$SSH_COMMAND" ] || [ "$SSH_COMMAND" == "null" ]; then
    echo "Error: Failed to get SSH command."
    exit 1
fi

# Extract ProxyCommand value
PROXY_CMD=$(echo "$SSH_COMMAND" | sed -n 's/.*ProxyCommand="\(.*\)".*/\1/p')
# Replace <privateKey> with actual SSH private key path
PROXY_CMD="${PROXY_CMD//<privateKey>/$SSH_PRIV_KEY_FILE}"

if [ -z "$PROXY_CMD" ]; then
    echo "Error: Failed to extract ProxyCommand."
    exit 1
fi

echo "  ProxyCommand extracted successfully."

echo "=== [4/4] Ansibleの実行を開始します... ==="
export ANSIBLE_SSH_COMMON_ARGS="-o ProxyCommand=\"$PROXY_CMD\""

# Run ansible-playbook with passed arguments
cd "$SCRIPT_DIR/.."
ansible-playbook -i hosts.yml site.yml "$@"
