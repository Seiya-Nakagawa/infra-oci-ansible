# OS詳細設計書 - infra-oci-ansible

## 目次

- [1. 概要](#1-概要)
- [2. システム基本設定](#2-システム基本設定)
  - [2.1. ホスト名管理](#21-ホスト名管理)
  - [2.2. タイムゾーン・ロケール・文字コード](#22-タイムゾーンロケール文字コード)
  - [2.3. 時刻同期 (NTP)](#23-時刻同期-ntp)
  - [2.4. パッケージ管理 (apt)](#24-パッケージ管理-apt)
- [3. ユーザー・グループ管理](#3-ユーザーグループ管理)
  - [3.1. ユーザー定義](#31-ユーザー定義)
  - [3.2. 認証・認可と環境設定](#32-認証認可と環境設定)
- [4. ネットワーク設計](#4-ネットワーク設計)
  - [4.1. IPアドレス・DNS](#41-ipアドレスdns)
  - [4.2. OS内ファイアウォール (ufw)](#42-os内ファイアウォール-ufw)
- [5. ストレージ・ファイルシステム](#5-ストレージファイルシステム)
  - [5.1. ボリューム・パーティション構成](#51-ボリュームパーティション構成)
  - [5.2. スワップ領域](#52-スワップ領域)
  - [5.3. マウントオプションによる保護](#53-マウントオプションによる保護)
- [6. セキュリティ堅牢化 (OS Hardening)](#6-セキュリティ堅牢化-os-hardening)
  - [6.1. SSH サービス設定](#61-ssh-サービス設定-etcsshsshd_configdcustomconf)
  - [6.2. カーネルパラメータ](#62-カーネルパラメータ-etcsysctld99-securityconf)
  - [6.3. リソース・プロセス制限](#63-リソースプロセス制限)
  - [6.4. 侵入検知と監査](#64-侵入検知と監査)
- [7. ログ管理・監視・運用](#7-ログ管理監視運用)
  - [7.1. ログローテーション (logrotate)](#71-ログローテーション-logrotate)
  - [7.2. systemd-journald](#72-systemd-journald)
  - [7.3. OCI 特有の運用機能](#73-oci-特有の運用機能)
- [8. バックアップ・リストア方針](#8-バックアップリストア方針)
  - [8.1. バックアップ](#81-バックアップ)
  - [8.2. リストア](#82-リストア)
- [9. Ansible 実装構造と設計方針](#9-ansible-実装構造と設計方針)

---

## 1. 概要

本ドキュメントは、OCI (Oracle Cloud Infrastructure) 上で稼働する Ubuntu 24.04 LTS インスタンスにおける OS レイヤーの詳細設計を定める。本設計は Ansible による自動構築（Infrastructure as Code）を前提とし、冪等性とセキュアな初期状態を担保する。

## 2. システム基本設定

### 2.1. ホスト名管理

- **命名規則**: `{プロジェクト識別子}-{環境名}-{役割}-{連番}` (例: `prj-prod-web-01`)
- **設定ファイル**: `/etc/hostname`, `/etc/hosts`
- **反映方法**: `hostnamectl` コマンドを使用。

### 2.2. タイムゾーン・ロケール・文字コード

- **タイムゾーン**: `Asia/Tokyo`
- **ロケール**: `ja_JP.UTF-8` (デフォルト)
- **キーボードレイアウト**: `jp106` (必要に応じて)

### 2.3. 時刻同期 (NTP)

- **ツール**: `systemd-timesyncd`
- **参照先**: OCI メタデータ/NTPサーバー (`169.254.169.254`) を優先。

### 2.4. パッケージ管理 (apt)

- **リポジトリ管理**: Ubuntu 24.04 準拠の DEB822 フォーマット (`/etc/apt/sources.list.d/ubuntu.sources`) を使用。
- **自動更新 (`unattended-upgrades`)**:
  - セキュリティアップデートのみ自動適用。
  - 更新後の自動再起動機能は「無効」。メンテナンス窓にて手動（またはジョブ）で実施する。
- **自動化阻害の抑止 (`needrestart`)**:
  - パッケージ更新時に表示される対話型プロンプトを抑制するため、`/etc/needrestart/needrestart.conf` にて `$nrconf{restart} = 'a';` (自動再起動) または `'l'` (リスト表示のみ) を設定し、Ansible の実行停止を防ぐ。
- **共通導入パッケージ**:
  - 管理: `vim`, `tmux`, `git`, `curl`, `wget`, `rsync`, `htop`, `tree`, `jq`
  - ネットワーク: `net-tools`, `iputils-ping`, `traceroute`, `dnsutils`
  - システム・セキュリティ: `software-properties-common`, `unzip`, `ufw`, `cloud-utils`, `auditd`, `apparmor-utils`

## 3. ユーザー・グループ管理

### 3.1. ユーザー定義

| ユーザー名 | UID | 所属グループ | 役割 | 備考 |
| :--- | :--- | :--- | :--- | :--- |
| `ubuntu` | 1000 | `sudo`, `adm` | OCI初期ユーザー | Ansible実行後に無効化 (`usermod -s /usr/sbin/nologin ubuntu`) |
| `infra-admin` | 任意 | `sudo`, `adm` | インフラ管理用 | Ansible 実行および緊急メンテナンス用 |
| `deploy` | 任意 | `www-data` | アプリ展開用 | アプリケーション要件に応じて作成 |

### 3.2. 認証・認可と環境設定

- **認証方式**: 公開鍵認証のみ（パスワード認証は一律禁止）。鍵データは Ansible Vault 等で暗号化して管理。
- **sudo 設定**:
  - `infra-admin`: `NOPASSWD: ALL` (運用要件によりパスワード要求へ変更を検討)
  - `/etc/sudoers.d/infra-admin` に個別定義し、`visudo` 相当の構文チェックを自動化に組み込む。
- **デフォルト umask**: `022` または要件に応じて `027` ( `/etc/login.defs` 等で制御)。

## 4. ネットワーク設計

### 4.1. IPアドレス・DNS

- **IP設定**: `netplan` (`/etc/netplan/*.yaml`) を使用し、DHCP 経由で取得（VCN 側で固定プライベートIPを予約）。
- **DNSレゾルバ**: `systemd-resolved` を利用し、VCN DNS (`169.254.169.254`) を参照。

### 4.2. OS内ファイアウォール (ufw)

OCI の「セキュリティ・リスト/NSG」と併用する多層防御。

- **デフォルトポリシー**: `incoming: deny`, `outgoing: allow`, `routed: deny`
- **許可ルール**:

  | 用途 | ポート | プロトコル | ソース |
  | :--- | :--- | :--- | :--- |
  | SSH | 22 (任意) | TCP | 管理セグメント (Bastion等) |
  | HTTP/S | 80, 443 | TCP | VCN内 / LB / Any (用途による) |
  | ICMP | N/A | ICMP | VCN内 (監視・疎通確認用) |

## 5. ストレージ・ファイルシステム

### 5.1. ボリューム・パーティション構成

- **ファイルシステム**: `ext4` または `xfs`
- **ブートボリューム**: `/` (ルート) に全容量を割り当て。
- **ブロックボリューム (追加データ用)**: 必要に応じて LVM (Logical Volume Manager) を用いて論理ボリュームを構築し、マウントする (`/data` 等)。

### 5.2. スワップ領域

- **設定**: スワップファイル (`/swapfile`) を作成。
- **サイズ**: メモリの要件に合わせて設定 (例: メモリ24GBなら4GB)。
- **優先度**: `vm.swappiness = 10` (物理メモリを優先)。

### 5.3. マウントオプションによる保護

以下のディレクトリに対し、不要な権限での実行を防ぐ。

- `/tmp`: `nosuid, nodev`
- `/dev/shm`: `nosuid, nodev, noexec`

## 6. セキュリティ堅牢化 (OS Hardening)

### 6.1. SSH サービス設定 (`/etc/ssh/sshd_config.d/custom.conf`)

- `PermitRootLogin`: `no`
- `PasswordAuthentication`: `no`
- `PubkeyAuthentication`: `yes`
- `MaxAuthTries`: `3`
- `ClientAliveInterval`: `300` / `ClientAliveCountMax`: `2`
- `AllowUsers`: `infra-admin` (許可ユーザーを限定、`ubuntu`は削除)
- **暗号化強化**: 脆弱な暗号スイート・MAC・KEXアルゴリズムを無効化し、強力なもの (例: `aes256-gcm@openssh.com`, `chacha20-poly1305@openssh.com` 等) のみ許可。

### 6.2. カーネルパラメータ (`/etc/sysctl.d/99-security.conf`)

- `net.ipv4.conf.all.accept_redirects = 0`
- `net.ipv4.conf.all.send_redirects = 0`
- `net.ipv4.tcp_syncookies = 1`
- `net.ipv6.conf.all.disable_ipv6 = 1` (IPv6 をVCNで使用しない場合、確実に無効化)
- `kernel.randomize_va_space = 2` (ASLRの有効化)

### 6.3. リソース・プロセス制限

- **Limits**: `/etc/security/limits.conf` にてファイルディスクリプタ上限を引き上げ（Webサーバー/DB向け）。
- **Systemd Limit**: ミドルウェアの Unit ファイル (`LimitNOFILE` 等) でもリソース制限を緩和。

### 6.4. 侵入検知と監査

- **MAC (Mandatory Access Control)**: Ubuntu標準の `AppArmor` を有効化し維持。
- **Fail2Ban**: SSH へのブルートフォース攻撃対策。
- **Auditd**: コマンド実行履歴やシステムファイル (`/etc/passwd` 等) の変更を監査ログ (`/var/log/audit/audit.log`) に記録。

## 7. ログ管理・監視・運用

### 7.1. ログローテーション (`logrotate`)

- **対象**: `/var/log/*.log`
- **世代管理**: 30日分維持。2世代目以降は `compress` (gzip圧縮)。

### 7.2. systemd-journald

- **保存設定**: `Storage=persistent`
- **容量制限**: `SystemMaxUse=1G`, `SystemMaxFileSize=100M` に制限し、ディスク枯渇を防止。

### 7.3. OCI 特有の運用機能

- **Oracle Cloud Agent**: 常駐させ、以下機能を OCI コンソールから管理する。
  - OS Management Hub (脆弱性管理・パッチ適用)
  - Metrics (CPU/メモリ等のリソース監視)
  - Custom Logs (OCI Logging への OS ログ転送)
- **kdump (クラッシュダンプ)**: リソース節約の観点から、トラブルシューティングで不要な場合は無効化し、メモリを解放する。

## 8. バックアップ・リストア方針

### 8.1. バックアップ

- **方式**: OCI ブート・ボリューム・バックアップ（ポリシーによる自動取得）。
- **頻度/保持**: 日次取得 / 7日間～保持。

### 8.2. リストア

- **IaC アプローチ**: バックアップからの直接リストアに加え、「標準イメージから新規インスタンスを起動し、Ansible を再実行して同等環境を復元する」アプローチを保証する。

## 9. Ansible 実装構造と設計方針

本設計は以下の構造で Role 化し、**冪等性（何度実行しても同じ状態になること）** を担保する。

- `roles/common`: ホスト名、タイムゾーン、apt/needrestart設定、パッケージ導入、NTP、kdump設定
- `roles/user`: ユーザー作成、公開鍵配置 (Vault連携)、sudo設定、不要ユーザーの無効化
- `roles/network`: Netplan設定、UFW設定、systemd-resolved
- `roles/security`: SSH暗号化強化、sysctl、Fail2Ban、AppArmor、Auditd
- `roles/storage`: スワップ領域の作成、各種マウント設定制限 (`/tmp` 等)
