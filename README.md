# Ashley - LLM Service Manager

Ashley is an all-in-one, single-click local AI assistant that runs entirely on your own computer. It includes everything needed to run an LLM offline: an llama.cpp LLM inference engine, a Symfony/PHP web chatbot interface, a CEF-based web client (PHP Desktop), and a service manager (written in Free Pascal) into one package - no Internet connection or cloud API key required at runtime.

## Why Ashley

- Complete control over the AI stack
- No cloud dependencies
- Predictable long-term availability
- Vendor-independent deployment
- Suitable for confidential environments
- Easily customizable and extensible

## Typical Use Cases

- Companies handling confidential data
- Developers experimenting with GGUF models
- Offline AI workstations
- Air-gapped environments
- AI appliances
- Embedded systems

## Features

- Fully offline operation
- No API keys or cloud services
- Supports any GGUF model
- CPU, CUDA and Vulkan backends
- Embedded desktop application
- Local SQLite configuration
- Self-contained deployment
- Modular, easy to add extensions

---

## Directory Layout

This repository contains only source files to minimize size. After cloning, the build process assembles the `server/` subdirectory into a runnable package.

```
ashley/                             # Project root (this directory)
├─ bruno/                           # Bruno API test collections
│  └─ Llama Service Wrapper/
├─ doc/                             # Source files of documentation
│  ├─ frontend_doxygen.cfg          # DoxyGen config for frontend documentation
│  ├─ gendoc.py                     # Quick and dirty Python script to generate MarkDown (*.md) documentation for Pascal (*.pas) files
│  ├─ manager.pds                   # PasDoc config for Service Manager documentation
│  ├─ user_manual.md                # Source of user manual PDF
│  └─ wrapper.md                    # Source of Service Wrapper PDF
├─ LICENSE.md                       # Main license file
├─ media/                           # Application images and icons (PNG, ICO, JPG)
├─ README.md                        # This file
│
├─ manager/                                     # Pascal GUI manager (Lazarus project)
│  ├─ lib/x86_64-win64/                         # Compiler output directory (empty in source)
│  ├─ manager.lpi / manager.lpr / manager.lps
│  ├─ main_form.pas + main_form.lfm
│  ├─ progress_form.pas + progress_form.lfm
│  ├─ settings_form.pas + settings_form.lfm
│  ├─ about_form.pas + about_form.lfm
│  ├─ vinfo.pas
│  ├─ sqlite3.def / sqlite3.dll                 # SQLite import library + DLL (Windows)
│  ├─ manager.ico / manager.res
│  └─ readme.txt                                # Main page for developer documentation
│
├─ server/                                      # Runtime skeleton (stub files)
│  ├─ database/
│  │  ├─ personality.db                         # SQLite persona database
│  │  └─ wrapper.db                             # SQLite service settings database
│  ├─ readme.txt                                # Quick start guide for release package
│  ├─ sqlite3.def / sqlite3.dll                 # SQLite import library + DLL (Windows)
│  └─ webserver/                                # Web server source skeleton
│     ├─ settings.json                          # PHP Desktop configuration (properly adjusted)
│     ├─ conf/                                  # NGINX configuration files (properly adjusted)
│     │  ├─ nginx.conf                          # Main config (edited by wrapper at runtime)
│     │  ├─ fastcgi.conf                        # FastCGI config
│     │  ├─ fastcgi_params
│     │  ├─ scgi_params
│     │  └─ uwsgi_params
│     ├─ php/                                   # PHP source config
│     │  └─ php.ini                             # PHP config (properly adjusted)
│     └─ www/
│        ├─ index.php                                   # Root redirect
│        ├─ not_found.php                               # Custom 404 handler
│        └─ frontend/                                   # Symfony 8 web application source
│           ├─ .editorconfig / .gitignore
│           ├─ README.md
│           ├─ composer.json / composer.lock
│           ├─ symfony.lock
│           ├─ .env / .env.dev / .env.test
│           ├─ compose.yaml / compose.override.yaml
│           ├─ importmap.php
│           ├─ phpunit.dist.xml
│           ├─ assets/                                  # Source assets (SCSS/JS entry points)
│           │  ├─ controllers.json
│           │  ├─ app.js
│           │  ├─ stimulus_bootstrap.js
│           │  ├─ controllers/                          # Stimulus controllers (source)
│           │  ├─ styles/                               # SCSS source
│           │  └─ vendor/                               # NPM asset config
│           ├─ bin/
│           │  ├─ console                               # Symfony console binary
│           │  └─ phpunit
│           ├─ config/                                  # Symfony configuration
│           │  ├─ bundles.php
│           │  ├─ preload.php
│           │  ├─ reference.php
│           │  ├─ routes.yaml
│           │  ├─ services.yaml
│           │  ├─ packages/*.yaml
│           │  └─ routes/*.yaml
│           ├─ migrations/                              # Database migrations
│           │  └─ .gitignore
│           ├─ public/                                  # Compiled assets + entry point
│           │  ├─ index.php
│           │  ├─ assets/                              # Compiled CSS/JS
│           │  └─ media/                               # Bootstrap Icons
│           ├─ src/                                     # Symfony PHP source code
│           │  ├─ Kernel.php
│           │  ├─ Controller/
│           │  ├─ Entity/
│           │  ├─ Repository/
│           │  ├─ Service/
│           │  └─ Command/
│           ├─ templates/                               # Twig templates (source)
│           │  ├─ base.html.twig
│           │  └─ chat/
│           ├─ tests/
│           │  └─ bootstrap.php
│           ├─ translations/
│           │  └─ .gitignore
│           ├─ var/                                     # Symfony cache var dir
│           │  └─ share/
│           └─ vendor/                                 # Composer-installed dependencies
│
└─ wrapper/                           # Pascal service wrapper (Lazarus project)
   ├─ lib/x86_64-win64/               # Compiler output directory (empty in source)
   ├─ wrapper.lpi / wrapper.lpr / wrapper.lps
   └─ wrapper.ico / wrapper.res
```

> **Key design principle:** this repository contains only files that are authored or directly edited for this project. The `sqlite3.dll` and `sqlite3.def` files in `manager/` and `server/` **are** checked in because they are required at compile-time for the Pascal linker. All project configuration files (`settings.json`, `nginx.conf`, `php.ini`, `fastcgi.conf`, `fastcgi_params`, `scgi_params`, `uwsgi_params`) are properly adjusted for Ashley and must be kept unchanged. The files `mime.types`, `koi-utf`, `koi-win`, and `win-utf` in `server/webserver/conf/` are **not** project-supplied — they come from the NGINX distro and must be added during the build.

> **Note:** The `server/webserver/conf/ssl/` directory, `server/config/`, `server/log/`, and `server/temp/` are intentionally empty in the source. These are runtime directories created during assembly.

> The web frontend intentionally uses Symfony instead of Electron or Node.js. It provides a lightweight, stable, server-side rendered interface with minimal client-side complexity.

> The service manager is written in Free Pascal because it produces standalone native executables with virtually no runtime dependencies and excellent Windows integration.

---

## Prerequisites — Build Tools

Before starting, install the following on your Windows development machine:

### 1. Microsoft Visual C++ 2015–2022 Redistributable (x64)

Required by the llama.cpp backend binaries and the NGINX+PHP runtime at build and runtime. Without it the compiled Pascal executables and bundled binaries will fail to start.

Download: https://aka.ms/vs/17/release/vc_redist.x64.exe

### 2. Free Pascal Compiler (FPC) 3.2+ with Lazarus IDE

Both `manager` and `wrapper` are Lazarus GUI/console projects.

- Download Lazarus: https://www.lazarus-ide.org/
- Required Lazarus packages (install via the IDE Package / Online Package Manager):
  - `LCL`: Lazarus Component Library (core GUI framework, usually bundled)
  - `FCL`: Free Pascal Components Library (usually bundled)
  - `SQLDBLaz`: SQLite database components
  - `SynEdit`: Syntax-highlighting editor (used in settings form)
  - `SynEditDsgn`: SynEdit design-time package
  - `richmemopackage`: Rich memo component (settings form)
  - `richmemo_design`: Rich memo design-time package

### 3. PHP 8.x CLI + Composer (for building the web frontend, optional)

Composer is needed to install Symfony/ vendor dependencies into `server/webserver/www/frontend/vendor/`.

- PHP 8.x: https://windows.php.net/download/
- Composer: https://getcomposer.org/download/
- Node.js + npm (for asset compilation): https://nodejs.org/
- or just simply use the official Symfony CLI tool: [https://github.com/symfony-cli/symfony-cli/releases/](https://github.com/symfony-cli/symfony-cli/releases/)

### 4. Git (for cloning the repository)

### 5. PHP Desktop (for the web client)

PHP Desktop is a standalone desktop wrapper for local web applications. The project includes a properly tweaked `settings.json` that configures the embedded browser, window behavior, and the local PHP/NGINX server stack.

- PHP Desktop project: https://github.com/cztomczak/phpdesktop
- Obtain a PHP Desktop build for Windows.

### 6. Windows PHP 8.x Runtime (Thread Safe, x64)

For the end-user deployment you need a full PHP 8.x build for Windows with the required extensions enabled.

### 7. llama.cpp Backend Binaries

The llama.cpp `llama-server.exe` is the core AI inference engine. You need builds for each backend you want to support.

- **Official build instructions:** https://github.com/ggerganov/llama.cpp/blob/master/docs/build.md
- **Pre-built Windows releases:** https://github.com/ggerganov/llama.cpp/releases

### 8. NGINX for Windows

The project supplies the following NGINX configuration files (already present in `server/webserver/conf/` and properly adjusted for Ashley). Additionally, the following standard NGINX distro files are needed but are **not** part of the project - obtain them from the NGINX Windows build:

- `mime.types`
- `koi-utf`
- `koi-win`
- `win-utf`

You also need the `nginx.exe` binary.

Download the latest stable NGINX Windows build from: https://nginx.org/en/download.html

---

## Build Overview

The goal is to assemble the `server/` subdirectory into a complete, runnable release package. There are **three major steps**:

1. **Compile the Pascal executables**: `manager.exe` and `wrapper.exe` (outputs to `server/` directory)
2. **Create runtime directories** in `server/` (config, log, temp, etc.)
3. **Add third-party binaries** (llama.cpp, PHP Desktop, NGINX, PHP) and model files

The `server/` directory is the final runnable package for end-user deployment.

---

## How to build the package

There are 2 ways to build the runnable release: an easy and an expert way.

### Easy way

1. Download and extract the **release package** (which already contains all components you need to get the system working but is not necessarily up-to-date compared to the source code);

2. Clone or download the **repository** (which contains only the source code);

3. Copy the entire `server` directory (the root directory) of the release package to the `server` directory of the repository (the source package) **without overwriting any files in it**;

4. Make your changes in the source code and recompile the component.

### Expert way

This is the advanced way to build the release package ensuring all components are up-to-date. Developers should always chose this way unless there is a good reason to keep the version of one or more component frozen.

#### Step 1 — Compile Pascal Executables

Open a **Lazarus IDE Command Prompt** (or a terminal where `fpc` and `lazbuild` are on PATH). Verify:

```powershell
lazbuild --version
fpc -iV
```

##### Compile manager.exe

```powershell
cd manager
lazbuild --bm=Release manager.lpi
```

This produces `server\manager.exe`. The Release build profile (`manager.lpi:28`) configures:

- Target: `../server/manager.exe`
- Optimization: Level 3, smart linking enabled, symbols stripped
- GUI application: `GraphicApplication=True` (Windows subsystem)
- Required packages: LCL, FCL, SQLDBLaz, SynEdit, SynEditDsgn, richmemopackage, richmemo_design
- Uses `sqlite3.dll` and `sqlite3.def` from the project directory at link time

##### Compile wrapper.exe

```powershell
cd wrapper
lazbuild --bm=Release wrapper.lpi
```

This produces `server\wrapper.exe`. The Release build profile (`wrapper.lpi:26`) configures:

- Target: `../server/wrapper.exe`
- Optimization: Level 3, smart linking enabled, symbols stripped
- Units used: `Classes`, `SysUtils`, `SQLite3Conn`, `fpjson`, `Process`, `StrUtils`, `md5`, `ssockets` (all standard FPC units)

---

#### Step 2 — Create Runtime Directories

Create the runtime directories needed for the server assembly:

```powershell
New-Item -ItemType Directory -Path "server\config"
New-Item -ItemType Directory -Path "server\log"
New-Item -ItemType Directory -Path "server\model\embedding"
New-Item -ItemType Directory -Path "server\temp"
New-Item -ItemType Directory -Path "server\webserver\conf\ssl"
New-Item -ItemType Directory -Path "server\webserver\logs"
New-Item -ItemType Directory -Path "server\webserver\temp"
```

> **Important:** All files in `server/webserver/` are either project-authored or pre-assembled third-party components properly adjusted for Ashley. Keep `settings.json`, `nginx.conf`, and `php.ini` **unchanged**. Do not edit Symfony config/template files.

---

#### Step 3 — Add Third-Party Binaries and Data

These are the components that are **not** in the repository and must be supplied externally.

##### A. llama.cpp backend binaries

Place the compiled llama.cpp binaries for each desired backend into `server/llama/<backend>/`. At minimum you need the CPU backend.

| Backend  | Requirement                                               | server path            |
| -------- | --------------------------------------------------------- | ---------------------- |
| CPU      | `llama-server.exe` + .dll files (no extra toolkit needed) | `server/llama/cpu/`    |
| CUDA 12  | CUDA 12.x toolkit + `-DGGML_CUDA=ON`                      | `server/llama/cuda12/` |
| CUDA 13  | CUDA 13.x toolkit + `-DGGML_CUDA=ON`                      | `server/llama/cuda13/` |
| Vulkan   | Vulkan SDK + `-DGGML_VULKAN=ON`                           | `server/llama/vulkan/` |
| ROCm/HIP | ROCm stack (Linux/experimental) + `-DGGML_HIP=ON`         | `server/llama/radeon/` |

Each backend directory must contain at least:

- `llama-server.exe`: the server binary (used by wrapper)
- `llama-cli.exe`: CLI tool
- `llama.dll` (or `llama-cuda.dll` / `llama-vulkan.dll`): backend library
- `ggml.dll` + `ggml-*.dll`: GGML backend DLLs (architecture-specific)
- `ggml-base.dll`: base GGML library
- `ggml-rpc.dll`: RPC support library
- `libomp140.x86_64.dll`: OpenMP runtime
- `mtmd.dll`: multimodal support library
- `rpc-server.exe`: RPC server helper
- `license.md`: llama.cpp license

> The exact set of files varies per build. The `server/llama/` directories should mirror the contents of a complete llama.cpp Windows server package.

##### B. PHP Desktop web client

PHP Desktop embeds a web browser and serves the local PHP/Symfony application. Obtain a PHP Desktop build for Windows. Place the files into `server/webserver/`:

```powershell
# PHP Desktop executable + CEF/Chromium runtime files
Copy-Item "path\to\phpdesktop\webclient.exe"          "server\webserver\webclient.exe"
Copy-Item "path\to\phpdesktop\libcef.dll"             "server\webserver\"
Copy-Item "path\to\phpdesktop\chrome_elf.dll"         "server\webserver\"
Copy-Item "path\to\phpdesktop\*.pak"                  "server\webserver\"
Copy-Item "path\to\phpdesktop\*.dat"                  "server\webserver\"
Copy-Item "path\to\phpdesktop\*.bin"                  "server\webserver\"
Copy-Item "path\to\phpdesktop\*.dll"                  "server\webserver\"
# Copy remaining PHP Desktop directories/files as needed (locales, debug.log, docs, etc.)
```

> **Keep `settings.json` unchanged** in `server/webserver/` - it is properly tweaked for this project. It configures the window title, size, Chromium flags, the local web server root (`www_directory: "www"`), index files, and the CGI interpreter path (`php/php-cgi.exe`).

##### C. PHP 8.x runtime (Thread Safe, x64)

1. Download **PHP 8.x Thread Safe (TS) + VC15 x64** from https://windows.php.net/download/
2. Extract the PHP archive.
3. **Keep the project's `php.ini` unchanged.** It is already properly adjusted. Keep it in place in `server/webserver/php/php.ini`.
4. Place the entire PHP directory (containing `php.exe`, `php-cgi.exe`, `.dll` files, `ext/`, etc.) into `server/webserver/php/` (merge with existing php.ini).

##### D. NGINX binary and distro config files

From the NGINX Windows distro, obtain the following files. Place them into `server/webserver/` and `server/webserver/conf/`:

```powershell
# nginx.exe binary
Copy-Item "path\to\nginx\nginx.exe" "server\webserver\nginx.exe"

# Standard NGINX distro config files (not supplied by the project)
Copy-Item "path\to\nginx\conf\mime.types"   "server\webserver\conf\mime.types"
Copy-Item "path\to\nginx\conf\koi-utf"      "server\webserver\conf\koi-utf"
Copy-Item "path\to\nginx\conf\koi-win"      "server\webserver\conf\koi-win"
Copy-Item "path\to\nginx\conf\win-utf"      "server\webserver\conf\win-utf"
```

The project's own NGINX configuration files are already present in `server/webserver/conf/` (nginx.conf, fastcgi.conf, etc.). Do **not** edit them.

> **Important:** The `server/webserver/conf/ssl/` directory is intentionally empty. SSL certificates are auto-generated by wrapper.exe on first start if none exist.

##### E. LLM model files

Model files are `.gguf` format files consumed by llama-server.exe.

1. Download a GGUF model (e.g. from https://huggingface.co/models?search=gguf).
2. Place the model file in `server/model/`:

```powershell
Copy-Item "path\to\downloaded-model.gguf" "server\model\h2o_danube_1_8b_chat_q2_k.gguf"
Copy-Item "path\to\model-license.txt"     "server\model\license.txt"
```

The `server/model/embedding/` subdirectory is for optional embedding models. Place any `.gguf` embedding models here.

---

#### Step 4 — Build the Symfony Web Frontend (if needed)

If `server/webserver/www/frontend/vendor/` and `server/webserver/www/frontend/public/assets/` are already present (as they are in the completed repository state), you can skip this step. Otherwise, run the following to populate dependencies and compile assets:

##### A. Install PHP Composer dependencies

```powershell
cd server\webserver\www\frontend
composer install --no-dev --optimize-autoloader
```

This reads `composer.lock` and populates `vendor/` with all Symfony bundles, Twig, Doctrine, and other third-party PHP packages.

> `--no-dev` excludes development-only packages (e.g. PHPUnit, web-profiler).
> `--optimize-autoloader` produces a production-optimized autoloader.

##### B. Compile frontend assets (CSS + JS)

```powershell
# Install Node.js dependencies
npm ci

# Build and compile assets
npm run build
```

This compiles SCSS into CSS (Bootstrap + custom `app.css`) and bundles JavaScript (`main.js`, Stimulus controllers, etc.) into the `public/assets/` directory.

---

### Result — Release Directory Layout

After completing all steps, the `server/` directory contains the complete, runnable release package:

```
server/
├─ config/                    # Empty runtime JSON config directory
├─ database/
│  ├─ personality.db          # SQLite persona database
│  └─ wrapper.db              # SQLite service settings database
├─ doc/                       # Copied unchanged from project root
├─ llama/                     # Assembled (third-party binaries)
│  ├─ cpu/
│  ├─ cuda12/
│  ├─ cuda13/
│  ├─ radeon/
│  ├─ vulkan/
│  └─ license.md
├─ log/                                 # Empty runtime log directory
├─ manager.exe                          # Built from manager/ project
├─ model/
│  ├─ embedding/
│  │  └─ nomic_embed_text_v2_moe_q4_k_m.gguf
│  ├─ h2o_danube_1_8b_chat_q2_k.gguf
│  └─ license.txt
├─ readme.txt                           # Quick start guide
├─ sqlite3.def                          # SQLite import library
├─ sqlite3.dll                          # SQLite runtime DLL
├─ temp/                                # Empty runtime temp directory
├─ webserver/                           # Web server stack + added binaries
│  ├─ settings.json                     # Already adjusted
│  ├─ nginx.exe                         # Added from NGINX distro
│  ├─ webclient.exe                     # Added from PHP Desktop
│  ├─ PHP Desktop runtime files         # Added (libcef.dll, .pak, .dat, .dll, locales/)
│  ├─ conf/
│  │  ├─ nginx.conf                                 # Already adjusted
│  │  ├─ fastcgi.conf                               # Already adjusted
│  │  ├─ fastcgi_params                             # Already adjusted
│  │  ├─ scgi_params                                # Already adjusted
│  │  ├─ uwsgi_params                               # Already adjusted
│  │  ├─ ssl/                                       # .placeholder (certificates auto-generated first run)
│  │  └─ (mime.types, koi-utf, koi-win, win-utf)    # From NGINX distro
│  ├─ logs/                                         # Empty runtime logs
│  ├─ openssl/                                      # OpenSSL runtime
│  │  ├─ bin/
│  │  ├─ include/
│  │  ├─ lib/
│  │  ├─ LICENSE.txt
│  │  └─ version.txt
│  ├─ php/                                          # Added from PHP distro + project's php.ini
│  └─ www/
│     ├─ index.php
│     ├─ not_found.php
│     └─ frontend/                                  # Already adjusted
│        ├─ README.md
│        ├─ composer.json / composer.lock
│        ├─ symfony.lock
│        ├─ .env / .env.dev / .env.test
│        ├─ compose.yaml / compose.override.yaml
│        ├─ importmap.php
│        ├─ phpunit.dist.xml
│        ├─ .editorconfig
│        ├─ .gitignore
│        ├─ assets/
│        ├─ bin/
│        ├─ config/
│        ├─ migrations/
│        ├─ src/
│        ├─ templates/
│        ├─ tests/
│        ├─ translations/
│        ├─ public/                                   # Compiled assets + entry point
│        │  ├─ assets/
│        │  ├─ index.php
│        │  └─ media/                                 # Bootstrap Icons
│        ├─ var/                                      # Symfony cache var dir
│        │  └─ share/
│        └─ vendor/                                   # Composer-installed dependencies
└─ wrapper.exe           # Built from wrapper/ project
```

> **Note:** The `server/webserver/conf/ssl/` directory contains a `.placeholder` file. SSL certificates are auto-generated by wrapper.exe on first start if none exist.

---

## System Requirements for End Users

The assembled `server/` directory requires the following on the end-user machine:

- **Microsoft Visual C++ 2015–2022 Redistributable (x64)**

  - Download: https://aka.ms/vs/17/release/vc_redist.x64.exe
  - Minimum version: 14.34.0 (Visual Studio 2022)

- **GPU backend prerequisites** (optional, hardware-dependent):

  - **CUDA 12.x:** NVIDIA GPU + CUDA 12.x toolkit
  - **CUDA 13.x:** NVIDIA GPU + CUDA 13.x toolkit
  - **Vulkan:** AMD / Intel / NVIDIA GPU with Vulkan runtime
  - **ROCm/HIP:** AMD Radeon GPU (experimental; officially Linux-only)

Windows 10 or later, x64 architecture, is required.

---

## Quick Start (End User)

1. Extract the `server/` archive to a folder (e.g. `C:\AI\Ashley\`)
2. Double-click `manager.exe`
3. On first startup the Settings window opens — select an LLM engine (CPU / CUDA / Vulkan) and a `.gguf` model file
4. Click **OK** — Ashley starts the AI service and generates SSL certificates if needed
5. Right-click the system tray icon → **Open Web UI** to launch the chat

---

## Troubleshooting (Build)

**`The service failed to start` / manager.exe crashes on build machine**: ensure the Visual C++ 2015–2022 Redistributable (x64) is installed.

**NGINX fails to start**: verify `php-cgi.exe` exists at `server/webserver/php/php-cgi.exe` and the `server/webserver/conf/ssl/` directory exists. The wrapper edits `nginx.conf` at runtime; if you edited it manually, restore it from `server/webserver/conf/nginx.conf`.

**Symfony frontend shows blank / PHP errors**: ensure `php.ini` has the required extensions enabled (`sqlite3`, `mbstring`, `openssl`, `curl`) and that `vendor/` is present in the frontend directory.

**lazbuild cannot find required packages**: install the missing Lazarus packages via the IDE Package Manager (`SynEdit`, `SynEditDsgn`, `richmemopackage`, `richmemo_design`, `SQLDBLaz`).

**PHP Desktop window does not open**: verify that `server/webserver/settings.json` is unchanged and that `www/index.php` and the Symfony `frontend/public/` directory are present under `server/webserver/www/`.

---

## License

This project is licensed under the **Apache License, Version 2.0**.

**Copyright © 2026 Robert Abraham**
