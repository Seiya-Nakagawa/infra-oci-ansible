# Kubernetes詳細設計書 - infra-oci-ansible

## 1. 概要

本ドキュメントは、OCI上の Ubuntu 24.04 LTS インスタンスにおいて構築する Kubernetes (k8s) クラスターの詳細設計を定める。個人開発向けにリソース効率を重視し、シングルノード構成から開始しつつ、標準的なツールセットを備えた環境を実現する。

## 2. 構成・インストール

### 2.1. コンテナランタイム (containerd)

- **ランタイム**: `containerd`
- **設定方針**:
  - `SystemdCgroup = true` を有効化し、OS のリソース管理と統合。
  - 必要最小限のプラグインのみを有効化。

### 2.2. Kubernetes コンポーネント

- **構築ツール**: `kubeadm`, `kubelet`, `kubectl`
- **バージョン**: 最新の安定版（LTS またはその1つ前を推奨）
- **リポジトリ**: Google の公式 APT リポジトリを使用。

### 2.3. クラスター構成

- **ノード形態**: シングルノード（Control Plane と Worker を同一ノードに配置）。
- **Taint 解除**: `node-role.kubernetes.io/control-plane:NoSchedule` を解除し、マスターノード上での Pod 実行を許可する。

## 3. 詳細設計

### 3.1. ネットワーク (CNI)

- **選定**: `Calico` または `Flannel`
- **Pod CIDR**: `10.244.0.0/16` (デフォルト)
- **Service CIDR**: `10.96.0.0/12`

### 3.2. ストレージ (CSI)

- **選定**: `local-path-provisioner` (Rancher) を採用。
- **理由**: シングルノード環境において、ホストのディレクトリを動的に永続ボリューム (PV) として割り当てるため。

### 3.3. サービス公開 (Ingress)

- **Ingress Controller**: `ingress-nginx`
- **公開方式**: `NodePort` または `HostNetwork`
- **外部アクセス**: ホスト OS 上の Nginx からリバースプロキシ経由でアクセス。

## 4. セキュリティ・運用

- **API Server**: 外部からの直接アクセスは OCI セキュリティ・リストで制限（特定 IP のみ許可）。
- **認証**: `RBAC` (Role-Based Access Control) を有効化。
- **ログ**: `kubectl logs` および `/var/log/pods/` 下のログを確認。
- **監視**: `Metrics Server` の導入によりリソース使用状況を可視化。

## 5. 確認コマンド

- **ノード状態**: `kubectl get nodes`
- **Pod 状態**: `kubectl get pods -A`
- **クラスター情報**: `kubectl cluster-info`
- **コンテナ状態**: `sudo crictl ps` (containerd 操作用)

## 6. Ansible 実装ガイド

### 6.1. 変数構造案 (`vars/main.yml`)

```yaml
k8s_version: "1.30"
pod_network_cidr: "10.244.0.0/16"
k8s_master_ip: "10.0.0.10"
install_ingress_nginx: true
```

### 6.2. Role 構成案

1. **runtime**: `containerd` の導入とカーネルパラメータ (`br_netfilter` 等) の設定。
2. **kube-tools**: `kubeadm`, `kubelet`, `kubectl` の導入とホールド設定。
3. **init**: `kubeadm init` によるクラスター初期化と `kubeconfig` の配置。
4. **network**: CNI (Calico等) の適用。
5. **post-config**: Taint 解除、StorageClass の導入、Ingress Controller のセットアップ。
