# 実装計画: Ansible 構築コードおよび構築手順書の作成

設計書（OS・Kubernetes・MySQL）に基づき、構築作業をユーザー自身で実行できるよう、Ansible プレイブック、各 Role のコード、実行補助スクリプトを実装します。さらに、ユーザーが迷わず構築を進められるよう、詳細な「構築手順書」を作成します。

## ユーザー確認・合意が必要な事項

> [!IMPORTANT]
> **構築の実施について**
> 実際の Ansible 実行によるサーバー構築はユーザー自身で行うため、今回の作業範囲は**「構築に必要な Ansible コード一式、実行用スクリプト、および構築手順書の作成とリポジトリへのプッシュ」**とします。

## 提案する変更内容

`infra-oci-ansible` リポジトリに対して、以下のファイルを新規作成・配置します。

---

### 1. 構築手順書

#### [NEW] [構築手順書.md](file:///home/seiya/git/infra-oci-ansible/docs/構築手順書.md)
- OCI Bastion セッションの確立、秘密鍵の配置、Ansible Vault の暗号化、プレイブックの実行、および構築後の検証コマンドまでを網羅した詳細な手順書。

---

### 2. 実行制御・インベントリ

#### [NEW] [run_ansible.sh](file:///home/seiya/git/infra-oci-ansible/scripts/run_ansible.sh)
- `terraform output` から自動的に接続情報を取得し、OCI Bastion セッションを確保（または作成）。
- 取得した SSH コマンドから ProxyCommand を抽出し、`ANSIBLE_SSH_COMMON_ARGS`環境変数にセットして `ansible-playbook` を実行するラッパースクリプト。

#### [NEW] [hosts.yml](file:///home/seiya/git/infra-oci-ansible/hosts.yml)
- ターゲットホスト（`10.0.1.60`）のインベントリ定義。

#### [NEW] [group_vars/all.yml](file:///home/seiya/git/infra-oci-ansible/group_vars/all.yml)
- パッケージ定義、k8sバージョン（`1.30`）、MySQLデータベース名、ユーザー定義などの共通変数。

#### [NEW] [site.yml](file:///home/seiya/git/infra-oci-ansible/site.yml)
- `os_setup`, `kubernetes`, `mysql` のロールを順次実行するメインプレイブック。

---

### 3. OS 設定ロール (`roles/os_setup`)

#### [NEW] [roles/os_setup/tasks/main.yml](file:///home/seiya/git/infra-oci-ansible/roles/os_setup/tasks/main.yml)
- OS 基本設定、ユーザー管理、SSH 堅牢化、カーネルパラメータ設定、リソース制限、Fail2Ban/Auditd、journald/logrotate 等のタスク定義。

#### [NEW] templates 類
- [custom_sshd.conf.j2](file:///home/seiya/git/infra-oci-ansible/roles/os_setup/templates/custom_sshd.conf.j2) (SSH設定)
- [security_sysctl.conf.j2](file:///home/seiya/git/infra-oci-ansible/roles/os_setup/templates/security_sysctl.conf.j2) (カーネルパラメータ)
- [limits.conf.j2](file:///home/seiya/git/infra-oci-ansible/roles/os_setup/templates/limits.conf.j2) (リソース制限)

---

### 4. Kubernetes 構築ロール (`roles/kubernetes`)

#### [NEW] [roles/kubernetes/tasks/main.yml](file:///home/seiya/git/infra-oci-ansible/roles/kubernetes/tasks/main.yml)
- `containerd` および k8s コンポーネント（1.30）の導入。
- クラスターの初期化 (`kubeadm init`）、kubeconfig の配置、CNI (Flannel) のデプロイ。
- Masterノードの Taint 解除（シングルノード実行許可）。
- Rancher `local-path-provisioner`、`ingress-nginx` (HostNetwork)、`cert-manager`、`Metrics Server` の導入。

---

### 5. MySQL 構築ロール (`roles/mysql`)

#### [NEW] [roles/mysql/tasks/main.yml](file:///home/seiya/git/infra-oci-ansible/roles/mysql/tasks/main.yml)
- MySQL パッケージ導入、`mysqld.cnf` の配置。
- 初期セキュリティ設定、データベース `laravel_db` とユーザー `laravel_user` の作成。

#### [NEW] [roles/mysql/templates/mysqld.cnf.j2](file:///home/seiya/git/infra-oci-ansible/roles/mysql/templates/mysqld.cnf.j2)
- 文字コード `utf8mb4` や接続制限を定義した設定ファイル。

---

## 検証プラン

### 1. 構文チェック (Syntax Check)
- 作成したプレイブックに対して `ansible-playbook --syntax-check` を実行し、構文に誤りがないことを確認します。

### 2. 手順書の整合性検証
- 手順書に記載された各コマンド、設定ファイルのパス、パラメータが、作成した Ansible コードおよび OCI 環境情報と完全に一致していることを確認します。
