# PHP/Laravel詳細設計書 - infra-oci-ansible

## 1. 概要

本ドキュメントは、OCI上の Ubuntu 24.04 LTS インスタンスにおいて、PHP 8.x および Laravel アプリケーションを実行するための詳細設計を定める。Web サーバ (Nginx) との連携および Composer による依存関係管理を含む。

## 2. 構成・インストール

### 2.1. インストール方針

- **取得元**: Ubuntu 標準リポジトリ（APT）を使用。
- **パッケージ名**:
  - `php-fpm`: FastCGI Process Manager
  - `php-cli`: コマンドライン実行用
  - `php-common`: 共通ファイル
- **主要な拡張モジュール**:
  - `php-mysql`: DB連携
  - `php-mbstring`: マルチバイト文字列対応
  - `php-xml`, `php-curl`, `php-zip`, `php-bcmath`, `php-intl`

### 2.2. Composer

- **インストール方式**: 公式インストーラをダウンロードし、`/usr/local/bin/composer` としてグローバルに配置。

## 3. 詳細設計

### 3.1. PHP-FPM 設定

- **リスニング設定**: Unix Domain Socket を使用.
  - パス: `/run/php/php8.3-fpm.sock` (Ubuntu 24.04 デフォルト)
- **実行ユーザー**: `www-data` / `www-data`
- **主要パラメータ (`php.ini` / `www.conf`)**:
  - `memory_limit`: `256M`
  - `upload_max_filesize`: `64M`
  - `post_max_size`: `64M`
  - `max_execution_time`: `60`
  - `pm`: `dynamic` (負荷に応じたプロセス管理)

### 3.2. Laravel 実行環境

- **ディレクトリ構成**:
  - アプリケーション配置先: `/var/www/<app_name>`
  - パーミッション設定: `storage` および `bootstrap/cache` ディレクトリに対して、`www-data` への書き込み権限を付与。
- **環境変数 (`.env`)**:
  - `APP_ENV`: `production`
  - `APP_DEBUG`: `false`
  - `DB_CONNECTION`: `mysql`
  - `DB_HOST`: `127.0.0.1`

## 4. セキュリティ・運用

- **セキュリティ**:
  - `expose_php = Off` (HTTPレスポンスヘッダから PHP バージョンを隠匿)
  - PHP-FPM のプロセス分離。
- **ログ管理**:
  - PHP-FPM ログ: `/var/log/php8.3-fpm.log`
  - Laravel ログ: `/var/www/<app_name>/storage/logs/laravel.log`
- **運用**: `php artisan migrate` 等のコマンドを Ansible から実行可能な構成とする。

## 5. 確認コマンド

- **バージョン確認**: `php -v`
- **FPM状態**: `systemctl status php8.3-fpm`
- **Composer確認**: `composer --version`
- **モジュール確認**: `php -m`

## 6. Ansible 実装ガイド

### 6.1. 変数構造案 (`vars/main.yml`)

```yaml
php_version: "8.3"
laravel_apps:
  - name: "portfolio"
    path: "/var/www/portfolio"
    repo: "https://github.com/example/portfolio.git"
    env:
      db_name: "laravel_db"
      db_user: "laravel_user"
```

### 6.2. Role 構成案

1.  **install**: PHP本体および拡張モジュールの導入。
2.  **composer**: Composer のグローバルインストール。
3.  **config**: `php.ini` および `www.conf` テンプレートの配置。
4.  **deploy**: ソースコードの取得、`composer install`、パーミッション設定、`.env` 配置。
