# Nginx詳細設計書 - infra-oci-ansible

## 1. 概要

本ドキュメントは、OCI上の Ubuntu 24.04 LTS インスタンスにおいて、リバースプロキシおよび Web サーバとして動作する Nginx の詳細設計を定める。複数のバックエンドサービス（Kubernetes Ingress, PHP-FPM等）へのルーティングと SSL 終端を一括管理する。

## 2. 構成・インストール

### 2.1. インストール方針

- **取得元**: Ubuntu 標準リポジトリ（APT）を使用。
- **パッケージ名**: `nginx`
- **導入モジュール**:
  - `python3-certbot-nginx` (Let's Encrypt 連携用)

### 2.2. サービス管理

- **ユニット名**: `nginx.service`
- **自動起動**: 有効 (`enabled`)
- **再起動方針**: 設定変更時は `systemctl reload nginx` を優先し、接続断を最小限に抑える。

## 3. 詳細設計

### 3.1. ディレクトリ・ファイル構成

| パス | 内容 | 備考 |
| :--- | :--- | :--- |
| `/etc/nginx/nginx.conf` | メイン設定ファイル | プロセス数、ログ形式、イベント設定等。 |
| `/etc/nginx/conf.d/` | 共通設定ディレクトリ | SSL最適化、ヘッダー設定等を分離して配置。 |
| `/etc/nginx/sites-available/` | サイト個別設定 | 各サービス（バーチャルホスト）の定義。 |
| `/etc/nginx/sites-enabled/` | 有効サイト設定 | `sites-available` からのシンボリックリンク。 |
| `/var/www/html/` | 静的コンテンツ | デフォルトのドキュメントルート。 |

### 3.2. 主要パラメータ設定 (`nginx.conf`)

- **Worker設定**:
  - `worker_processes`: `auto`
  - `worker_connections`: `1024`
- **HTTP共通設定**:
  - `server_tokens`: `off` (セキュリティ向上のためバージョン非表示)
  - `client_max_body_size`: `64M` (Laravelアプリのファイルアップロードを考慮)
  - `keepalive_timeout`: `65`

### 3.3. バーチャルホスト設計

複数のサブドメインを運用することを前提とし、以下の構造で管理する。

- **デフォルトサイト (`00-default.conf`)**:
  - 未定義ドメインでのアクセスを 444 (No Response) または 403 で拒否。
- **リバースプロキシ設定例**:
  - Kubernetes Ingress 向け: 内部 IP (LoadBalancer/NodePort) へ転送。
  - PHP-FPM 向け: Unix Domain Socket (`/run/php/php8.3-fpm.sock`) へ転送。

### 3.4. SSL/TLS 設計

- **プロトコル**: `TLSv1.2`, `TLSv1.3` (脆弱なプロトコルは無効化)
- **証明書取得**: `Certbot` を使用。
  - チャレンジ方式: HTTP-01 チャレンジ。
  - 自動更新: `certbot.timer` (systemd) により、1日2回有効期限をチェックし、必要に応じて更新。
- **HSTS (HTTP Strict Transport Security)**: 有効化を推奨。

## 4. セキュリティ・運用

- **実行ユーザー**: `www-data`
- **ログ管理**:
  - アクセスログ: `/var/log/nginx/access.log` (JSON形式での出力を推奨)
  - エラーログ: `/var/log/nginx/error.log`
  - ローテーション: `logrotate` により 14世代管理。
- **ファイアウォール (参考)**:
  - OCI セキュリティ・リストにて TCP 80 (HTTP), 443 (HTTPS) を開放。

## 5. 確認コマンド

- **構文チェック**: `sudo nginx -t`
- **ステータス確認**: `systemctl status nginx`
- **証明書更新テスト**: `sudo certbot renew --dry-run`
- **サイト有効化状況**: `ls -l /etc/nginx/sites-enabled/`

## 6. Ansible 実装ガイド

### 6.1. 変数構造案 (`vars/main.yml`)

```yaml
nginx_sites:
  - name: "portfolio.example.com"
    server_name: "portfolio.example.com"
    proxy_pass: "http://127.0.0.1:8080"
    ssl_enabled: true
  - name: "api.example.com"
    server_name: "api.example.com"
    php_fpm: true
    ssl_enabled: true
```

### 6.2. Role 構成案

1.  **install**: パッケージ導入。
2.  **config**: `nginx.conf` および共通 snippets の配置。
3.  **vhost**: `sites-available` へのテンプレート配置とシンボリックリンク作成。
4.  **ssl**: Certbot の導入と初期証明書取得（要ドメイン疎通）。
