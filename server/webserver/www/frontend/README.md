# Ashley Frontend – Symfony 8 Web Developer Documentation {#mainpage}

This is the developer documentation of the Symfony-based chatbot frontend that powers the Ashley Web UI.

---

## Overview

The frontend is a Symfony 8 PHP application that provides the web-based chatbot interface for Ashley. It communicates with the local LLM engine (llama.cpp) via HTTP proxy, manages conversation sessions, applies persona/behavior matching through vector embeddings, and streams responses back to the browser.

* **Namespace**: `App\` → `src/`
* **Web root**: `public/`
* **Template engine**: Twig
* **CSS**: Bootstrap 5 + custom `public/assets/css/main.css`
* **JS**: Stimulus + Turbo
* **Database**: SQLite (personality.db, wrapper.db)

---

## Requirements

* PHP >= 8.4 with `ctype` and `iconv` extensions
* Composer
* NGINX + PHP-FPM

---

## Installation

1. Run `composer install` (post-install scripts: `cache:clear`, `assets:install`, `importmap:install`)
2. Configure NGINX to serve from `trunk/server/webserver/www/` with PHP-FPM on port 9000
3. Copy `.env` to `.env.local` and set `APP_ENV` / `APP_DEBUG`

---

## Directory Structure

```
frontend/
├─ .editorconfig
├─ .env / .env.dev / .env.test
├─ .gitignore
├─ assets/
│  ├─ app.js                 ← Main JS entry point
│  ├─ controllers.json
│  ├─ controllers/
│  │  ├─ csrf_protection_controller.js
│  │  └─ hello_controller.js
│  ├─ stimulus_bootstrap.js
│  └─ styles/
│     └─ app.css              ← Imported by app.js (skyblue background)
├─ bin/
│  ├─ console
│  └─ phpunit
├─ compose.yaml / compose.override.yaml
├─ composer.json / composer.lock
├─ config/
│  ├─ bundles.php
│  ├─ packages/
│  │  ├─ asset_mapper.yaml, cache.yaml, csrf.yaml, debug.yaml
│  │  ├─ doctrine.yaml, doctrine_migrations.yaml, framework.yaml
│  │  ├─ mailer.yaml, messenger.yaml, monolog.yaml, notifier.yaml
│  │  ├─ property_info.yaml, routing.yaml, security.yaml
│  │  ├─ translation.yaml, twig.yaml, ux_turbo.yaml
│  │  ├─ validator.yaml, web_profiler.yaml
│  ├─ preload.php
│  ├─ reference.php
│  ├─ routes.yaml
│  ├─ routes/ (framework.yaml, security.yaml, web_profiler.yaml)
│  └─ services.yaml
├─ importmap.php
├─ migrations/
├─ phpunit.dist.xml
├─ public/ (web root)
│  ├─ index.php
│  ├─ assets/
│  │  ├─ css/
│  │  │  ├─ bootstrap.*.css   ← Bootstrap 5 compiled files
│  │  │  └─ main.css          ← Main chatbot interface styling
│  │  └─ js/
│  │     ├─ bootstrap.*.js     ← Bootstrap 5 compiled files
│  │     └─ main.js            ← Compiled main.js
│  └─ media/ (directory listing blocked)
├─ src/ (PHP source: App\ namespace)
│  ├─ Command/GenerateEmbeddingsCommand.php
│  ├─ Controller/ChatController.php
│  ├─ Kernel.php
│  ├─ Entity/ (.gitignore placeholder)
│  ├─ Repository/ (.gitignore placeholder)
│  └─ Service/
│     └─ ChatConfigService.php
├─ symfony.lock
├─ templates/
│  ├─ base.html.twig         ← Default Symfony template (unused)
│  └─ chat/index.html.twig   ← Chat UI page
├─ tests/
├─ translations/
├─ var/ (runtime caches/logs)
│  └─ share/
└─ vendor/
```

---

## Routing

* `GET /` -> `App\Controller\ChatController::index`: Renders the chat UI page
* `POST /api/chat` -> `App\Controller\ChatController::handleApi`: Unified chat API

---

## Services

Services are auto-discovered from `src/` via `config/services.yaml`.

* **`App\Service\ChatConfigService`**: Loads LLM and persona configuration from `wrapper.json`, `wrapper.db`, `personality.json`, `personality.db`. Instantiated directly (no Symfony DI container).

---

## CLI Commands

* `php bin/console app:generate-embeddings`: Back-fill missing vector embeddings in `personality.db`

---

## Notes

* `public/index.php` is the Symfony front controller.
* `trunk/server/webserver/www/index.php` is a redirection file used by the CEF-based web client to connect to the actual frontend.
* The application writes logs to `trunk/server/log/` (configured in `src/Kernel.php`).
* Assets are managed via Symfony Asset Mapper; do not write directly to `public/assets/`.
