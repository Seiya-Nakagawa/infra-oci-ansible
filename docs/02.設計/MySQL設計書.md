# MySQL詳細設計書 - infra-oci-ansible

## 1. 概要

本ドキュメントは、OCI上の Ubuntu 24.04 LTS インスタンスにおいて、ホストOSに直接導入する MySQL サーバの詳細設計を定める。Laravel 等のアプリケーションのデータストアとして利用し、パフォーマンスとセキュリティを両立させた設定を行う。

## 2. 構成・インストール

### 2.1. インストール方針

- **取得元**: Ubuntu 標準リポジトリ（APT）を使用。
- **パッケージ名**:
  - `mysql-server`: データベースサーバ
  - `mysql-client`: クライアントツール
  - `python3-pymysql`: Ansible からの操作用ライブラリ

### 2.2. サービス管理

- **ユニット名**: `mysql.service`
- **自動起動**: 有効 (`enabled`)

## 3. 詳細設計

### 3.1. ディレクトリ構成

| パス | 内容 | 備考 |
| :--- | :--- | :--- |
| `/etc/mysql/my.cnf` | メイン設定ファイル | 基本的に `conf.d` を読み込む。 |
| `/etc/mysql/mysql.conf.d/` | 詳細設定ディレクトリ | `mysqld.cnf` 等を配置。 |
| `/var/lib/mysql/` | データディレクトリ | データベースの実体。 |
| `/var/log/mysql/` | ログディレクトリ | エラーログ、スロークエリログ等。 |

### 3.2. 主要パラメータ設定 (`mysqld.cnf`)

- **接続設定**:
  - `bind-address`: `127.0.0.1` (外部からの直接接続は原則禁止)
  - `mysqlx-bind-address`: `127.0.0.1`
- **文字コード設定**:
  - `character-set-server`: `utf8mb4`
  - `collation-server`: `utf8mb4_0900_ai_ci`
- **パフォーマンス設定**:
  - `innodb_buffer_pool_size`: インスタンスメモリの 50-70% を目安に調整。
  - `max_connections`: `151` (デフォルト、必要に応じて拡張)
- **ログ設定**:
  - `slow_query_log`: `ON`
  - `long_query_time`: `2.0` (2秒以上のクエリを記録)

### 3.3. データベース・ユーザー管理

- **認証方式**: `caching_sha2_password` (MySQL 8.0 標準)
- **ユーザー設計**:
  - `root`: `auth_socket` プラグインにより、OS の特権ユーザーからパスワードなしでアクセス可能とする。
  - `app_user`: アプリケーション専用ユーザー。特定データベースへの権限のみ付与。

## 4. セキュリティ・運用

- **初期セキュリティ設定**: `mysql_secure_installation` に相当する設定を Ansible で実施。
  - 匿名ユーザーの削除。
  - リモートからの root ログイン禁止。
  - テストデータベースの削除。
- **ログローテーション**: `logrotate` により `/var/log/mysql/*.log` を 14世代管理。
- **バックアップ**: IaC での再現性を重視しつつ、必要に応じて `mysqldump` による定期出力を検討。

## 5. 確認コマンド

- **サービス状態**: `systemctl status mysql`
- **ログイン確認**: `sudo mysql -u root`
- **設定値確認**: `mysql -u root -e "SHOW VARIABLES LIKE 'character_set_server';"`
- **データベース一覧**: `mysql -u root -e "SHOW DATABASES;"`

## 6. Ansible 実装ガイド

### 6.1. 変数構造案 (`vars/main.yml`)

```yaml
mysql_databases:
  - name: "laravel_db"
    encoding: "utf8mb4"
    collation: "utf8mb4_0900_ai_ci"

mysql_users:
  - name: "laravel_user"
    password: "{{ vault_mysql_password }}"
    priv: "laravel_db.*:ALL"
    host: "localhost"
```

### 6.2. Role 構成案

1.  **install**: パッケージ導入。
2.  **config**: `mysqld.cnf` テンプレートの配置と再起動。
3.  **secure**: 匿名ユーザー削除等のセキュリティ設定。
4.  **database**: データベースおよびユーザーの作成（`mysql_db`, `mysql_user` モジュールを使用）。
