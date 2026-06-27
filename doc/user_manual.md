<h1 align="center">Ashley User Manual</h1>

<img title="Ashley portrait" src="../media/ashley_icon.png" alt="Ashley portrait" data-align="center" width="300">

## Table of Contents

- [What is Ashley?](#what-is-ashley)
- [System Requirements](#system-requirements)
- [Quick Start (First Time Setup)](#quick-start-first-time-setup)
- [Service Manager Window](#service-manager-window)
- [Service Menu](#service-menu)
- [Tools Menu](#tools-menu)
- [Help Menu](#help-menu)
- [System Tray Icon](#system-tray-icon)
- [Open Service Manager](#open-service-manager)
- [Settings Window](#settings-window)
- [Engine Settings Tab](#engine-settings-tab)
  - [Engine Group](#engine-group)
  - [Engine Parameters Group](#engine-parameters-group)
  - [Engine Change Behavior](#engine-change-behavior)
- [Embedding Tab](#embedding-tab)
  - [Embedding Model Group](#embedding-model-group)
  - [Embedding Parameters Group](#embedding-parameters-group)
- [Logging and Proxy Tab](#logging-and-proxy-tab)
  - [Logging Group](#logging-group)
  - [LLM Proxy Service Group](#llm-proxy-service-group)
- [Web Server Tab](#web-server-tab)
  - [Nginx Settings Group](#nginx-settings-group)
  - [PHP Settings Group](#php-settings-group)
  - [Temporary Files and Folders Group](#temporary-files-and-folders-group)
- [Persona Tab](#persona-tab)
  - [Default Persona Group](#default-persona-group)
  - [Properties Group](#properties-group)
  - [System Group](#system-group)
- [About Dialog](#about-dialog)
- [Everyday Use](#everyday-use)
- [Directory Structure](#directory-structure)
- [Understanding the Architecture](#understanding-the-architecture)
- [Database Documentation](#database-documentation)
- [Frontend Documentation](#frontend-documentation)
- [Troubleshooting](#troubleshooting)
- [Tips and Best Practices](#tips-and-best-practices)
- [Support Information](#support-information)

## What is Ashley?

Ashley is a complete, single-click local AI assistant for Windows. It bundles an *LLM inference engine*, a *web chatbot interface*, and a *settings manager* into one package that requires no Internet connection or cloud API key. The application runs entirely on your computer using locally installed AI models.

The **Service Manager** (`manager.exe`) is the central control application. It runs from the *system tray*, manages all background services and provides the graphical interface for configuration.

---

## System Requirements

Before running Ashley, ensure the following prerequisites are installed on your Windows 10/11 system:

* **Microsoft Visual C++ 2015-2022 Redistributable (x64)**: Ashley's bundled *Llama.cpp* backend and *web server* binaries are compiled with Microsoft Visual C++ and require the Microsoft Visual C++ 2015–2022 Redistributable (x64) to be present on the system. Download: https://aka.ms/vs/17/release/vc_redist.x64.exe. Minimum version: 14.34.0 (Visual Studio 2022).
* **NVIDIA GPU Drivers and CUDA Toolkit**: if you intend to use *NVIDIA CUDA acceleration*, install a matching *CUDA Toolkit* version for your selected backend and keep your *NVIDIA driver* up to date.
  - For **CUDA 12.x**: https://developer.nvidia.com/cuda-12-0-download-archive
  - For **CUDA 13.x**: https://developer.nvidia.com/cuda-downloads
  - Also install the latest **Game Ready** or **Studio driver** from: https://www.nvidia.com/drivers.
* **AMD Radeon or ROCm (Radeon backend)**: if you intend to use the *AMD Radeon backend* from the `radeon/` folder, install the *ROCm software stack* and verify your GPU appears under supported hardware: https://rocm.docs.amd.com/en/latest/deploy/gpus/index.html.
  - *Note: ROCm is officially supported on Linux; Windows support is experimental.*

## Quick Start (First Time Setup)

1. Unzip the *release archive* to a folder of your choice. For example: `C:\AI\Ashley\`.
2. Open that folder and double-click `manager.exe`. Ashley starts automatically. A small icon appears in the *Windows taskbar system tray* in the bottom-right corner of the screen.
3. On first startup or when no configuration file is detected, the application opens the *Settings* window so you can make sure everything is configured properly before starting the actual services.
4. When running the application normally with the services configured properly, the application will start the services automatically.
5. If you need to change configuration or fine-tune settings, right-click the *tray icon* and choose *Settings* to open the *Settings window*.
6. The first thing to do is pick an *LLM engine*. The engine selection is on the very first tab in the *Settings window*. Choose the engine that matches your hardware.
   * **CPU** works on every Windows PC and no extra software is needed.
   * **CUDA** requires an **NVIDIA GPU** and is faster than CPU.
   * **Vulkan** works on **AMD**, **Intel**, or **NVIDIA** GPUs without requiring the *CUDA toolkit*.
   * **HIP Radeon** requires a **Radeon** GPU and is not tested yet.
7. Choose a model file with the `.gguf` extension for the engine to use.
8. Click *OK* at the bottom of the window. Ashley configures everything, generates a *security certificate* if needed, and starts the AI service in the background.
9. Right-click the *tray icon* again and choose *Open Web UI* to launch the *chatbot window*. You can also access the service from your web browser at `http[s]://localhost:port/`, where *port* is the HTTP[S] port configured in the settings window.

---

## Service Manager Window

When the *Service Manager* window is visible, it contains:

* A **menu bar** at the top with the following menus: **Service**, **Tools**, and **Help**.
* A **status bar** at the bottom that displays the current state of the application and services.
* The window can be minimized to the system tray by clicking the minimize button or choosing *Minimize* from the *Service* menu. The application continues running in the background.

The main window is primarily used for service control, tool execution, and accessing documentation. Most configuration is done through the Settings window.

### Service Menu

* **Minimize to System Tray**: minimizes the window to the system tray.
* **Open Web UI**: Launches the *CEF*-based chat window application (`webclient.exe`). The chat window opens as a separate standalone browser window. You can open and close it as many times as you like while the service runs.
* **Start LLM service**: starts the *LLM service* (`wrapper.exe`). A confirmation dialog appears before starting.
* **Stop LLM service**: stops the running *LLM service*. A confirmation dialog appears before stopping.
* **Restart LLM service**: restarts the *LLM service*. A confirmation dialog appears before restarting.
* **Exit**: stops the services and closes the application.

### Tools Menu

* **Generate embedding vectors**: generates missing embedding vectors. This requires the *LLM service* to be running. A confirmation dialog appears before starting. This process runs synchronously and blocks the application until completed.
* **Generate SSL certificate**: generates a new *self-signed SSL certificate* for HTTPS connections. The *LLM service* must be stopped first. A confirmation dialog appears before starting. This process runs synchronously and blocks the application until completed.

### Help Menu

* **Database Documentation > Service Wrapper**: opens the *Service Wrapper* database documentation.
* **Database Documentation > Personality Database**: opens the *Personality* database documentation.
* **Frontend Documentation**: opens the frontend documentation in your default browser.
* **User Manual**: opens this *user manual* document.
* **About**: opens the *About* dialog showing the *application version*, *copyright*, and *license* information.

All options in the main menu are also available from the system tray popup menu.

## System Tray Icon

The *Service Manager* application minimizes to the *Windows system tray*. The *tray icon* indicates the current state of the services.

* **Left/Right-click** the tray icon to open the popup menu.

The popup menu contains the following additional option:

### Open Service Manager

Restores the *Service Manager* window from the *system tray*. This option is available when the window is minimized or hidden.

## Settings Window

The *Settings window* is the main configuration interface for Ashley. It contains five tabs organized in a tab control at the top. The tabs are:

1. **Engine Settings**
2. **Embedding**
3. **Logging and Proxy**
4. **Web Server**
5. **Persona**

At the bottom of the *Settings window* are the following buttons:

* **OK**: saves all changes and closes the *Settings window*. If the *LLM service* was running before the changes, it will be automatically restarted.
* **Cancel**: closes the *Settings window* without saving any changes.
* **Apply**: saves all changes without closing the *Settings window*. The *LLM service* will be restarted if it was running.
* **Load Defaults for LLM engine**: loads the default configuration for the currently selected *LLM engine* from the database. A confirmation dialog appears before discarding changes.

Changes are not saved automatically. You must click *OK* or *Apply* to save your changes.

### Engine Settings Tab

This is the first and most important tab. It configures the core *LLM engine* that processes your prompts.

#### Engine Group

* **LLM engine**: a drop-down list that lets you select the *LLM engine* to use. The available engines are loaded from the `database/wrapper.db` file and depend on which engine binaries are present in the `llama/` folder. The available options are:
  * **CPU**: works on every Windows PC. No extra software needed. Slowest option but universally compatible.
  * **CUDA**: requires an *NVIDIA GPU* with *CUDA toolkit* installed. Provides significant performance improvements over CPU.
  * **Vulkan**: works on *AMD*, *Intel*, and *NVIDIA GPU*s without requiring the *CUDA toolkit*. Good cross-vendor alternative.
  * **HIP Radeon**: requires a *Radeon GPU* with *ROCm* support. Windows support is experimental.
    The engine choice highly affects performance. Select the engine that matches your hardware.
* **Device**: a drop-down list that lets you select which specific device (*GPU*) the *LLM engine* should use. When you select an engine that supports multiple devices, the application queries the engine binary for available devices and populates this list. *N/A* will be selected for CPU or when device selection is not applicable. This choice also highly affects performance.
* **Model**: a drop-down list that lets you select which `.gguf` model file the engine will load. The list is populated from the `model/` folder. Only one model can be selected at a time. The selected model determines the AI's capabilities and response quality.
* **Add Model**: opens a file dialog to import a new `.gguf` model file into the `model/` folder. The file is copied into the model directory, and its name is sanitized (special characters and spaces are replaced with underscores). After importing, the model appears in the Model drop-down list.

#### Engine Parameters Group

* **Parameters**: a key-value editor that lets you fine-tune the *LLM engine* parameters. Each row has a parameter name and its value. Common parameters include:
  * **`port`**: the port number the *LLM engine* listens on (default: 8080 for conversational, 8081 for embedding).
  * **`threads`**: number of CPU threads to use.
  * **`ctx_size`**: context window size in tokens.
  * **`gpu_layers`**: number of layers to offload to *GPU* (for *CUDA/Vulkan* engines).
  * Other engine-specific parameters.
    Hover the mouse over a parameter name to see its description in a tooltip. You can add new parameters using the *Add* button and remove existing ones using the *Remove* button. Parameter names must be unique.
* **Add**: opens a dialog to add a new custom parameter. Enter the parameter name when prompted. The parameter is added with an empty value that you can then edit in the list.
* **Remove**: removes the selected parameter from the list after confirmation.

#### Engine Change Behavior

When you change the *LLM engine* selection, a confirmation dialog appears: *"Load default configuration for the selected LLM engine?"* If you click *Yes*, the default configuration for that engine is loaded from the database, which may change the available parameters, model selection, and device options.

### Embedding Tab

This tab configures the embedding engine, which is used for behavior matching. The embedding engine allows Ashley to recognize question patterns and respond more appropriately.

#### Embedding Model Group

* **Enable Embedding**: a checkbox that enables or disables the *embedding engine*. When enabled, the embedding model and parameters below become active. When disabled, the embedding server is not started.
* **Embedding Model**: a drop-down list that lets you select which `.gguf` embedding model file to use. The list is populated from the `model/embedding/` folder.
* **Add Model**: opens a file dialog to import a new `.gguf` embedding model file into the `model/embedding/` folder. The file is copied and sanitized the same way as conversational models.

#### Embedding Parameters Group

* **Parameters**: a key-value editor for *embedding engine* parameters. Works the same way as the *LLM parameters* editor. Common parameters include:
  * **`port`**: the port the embedding engine listens on.
  * **`threads`**: number of threads.
  * **`ctx_size`**: context size.
  * Other embedding-specific parameters.
* **Add**: adds a new custom embedding parameter.
* **Remove**: removes the selected embedding parameter after confirmation.

### Logging and Proxy Tab

This tab controls logging behavior and the LLM proxy service settings.

#### Logging Group

* **Logging enabled**: a checkbox that enables or disables server logging. When enabled, the *LLM service* writes log entries to `log/wrapper.log` and the web server writes to `log/error.log` and `log/access.log`. When disabled, logging is suppressed for better performance.
* **Open Log Folder**: opens the `log/` folder in *File Explorer*. This button is enabled when the log directory exists.
* **Clear Log**: clears the log files. When the *LLM service* is running, this deletes the current `wrapper.log` file. When the service is stopped, this clears the entire `log/` directory recursively. A confirmation dialog appears before clearing.

#### LLM Proxy Service Group

* **LLM proxy service port number**: the port number the proxy service listens on. Web applications use this port to access the *LLM service* through a normal *REST API*. Default depends on the selected engine. Only numeric values are accepted.
* **LLM proxy service timeout in seconds**: the timeout for proxy requests, in seconds. Range: 1-3600. Default: 60.
* **Maximal connections for LLM proxy service**: the maximum number of simultaneous connections the proxy will accept. Range: 1-20000. Default: 200.
* **Maximal package size for requests (bytes)**: the maximum size of a single request package in bytes. Range: 1-1073741824 (1 GB). Default: 2097152 (2 MB).

The timeout, max connections, and max package size settings are only enabled when a proxy port number is specified.

### Web Server Tab

This tab configures the built-in *NGINX web server* and *PHP runtime*.

#### Nginx Settings Group

* **HTTP port**: the port number for normal HTTP connections. Range: 1-65535. Default: 80.
* **HTTPS port**: the port number for HTTPS (SSL) connections. Range: 1-65535. Default: 443.
* **SSL Certificate**: the path to the *SSL certificate* file for HTTPS. You can type a path directly or click the *Open* button to browse for a `.crt` file. The path is relative to the application directory. If left empty, the self-signed certificate generated on first start is used.
* **SSL Key**: the path to the *SSL private key* file. You can type a path directly or click the *Open* button to browse for a `.key` file. The path is relative to the application directory.
* **Open (SSL Certificate)**: opens a file browser to select an SSL certificate file.
* **Open (SSL Key)**: opens a file browser to select an SSL key file.

#### PHP Settings Group

* **PHP HTTP port (internal)**: the port number for the internal *PHP FastCGI* process. This is used for localhost-only communication between *NGINX* and *PHP*. Range: 1-65535. Default: 9000.

#### Temporary Files and Folders Group

* **Open Folder**: opens the `temp/` folder in *File Explorer*. This folder contains temporary files created by the *PHP runtime*, *web server* and other services. This button is enabled when the service is stopped and the temp directory exists.
* **Clear Folder**: clears all temporary files and folders in the `temp/` directory recursively. This can only be done when the *LLM service* is stopped. A confirmation dialog appears before clearing.

### Persona Tab

This tab configures the AI chatbot's personality, appearance and behavior.

#### Default Persona Group

* **Default Persona**: a drop-down list of available personas loaded from the `database/personality.db` file. Each persona has a full name and description. When you select a persona from this list and click *Load Persona*, its settings are loaded into the *Properties* group below.
* **Load Persona**: loads the selected persona from the database into the form fields. A confirmation dialog appears: *"Do you really want to load the selected persona from the database and discard current changes?"* After loading, you can customize the persona properties and save them.

#### Properties Group

* **Avatar**: a clickable image area that shows the persona's avatar. Click on it to open a file browser and select an image file (JPG, JPEG, PNG, BMP, GIF, TIFF). The image is embedded into the persona configuration.
* **Background**: a clickable image area that shows the persona's background image. Click on it to open a file browser and select an image file. The image is embedded into the persona configuration.
* **Full name**: the full display name of the persona. Maximum 255 characters.
* **Description**: a short description of the persona. Maximum 255 characters.
* **Initial message**: the greeting message the persona sends when a new conversation starts.
* **System prompt**: the main behavior prompt that defines how the persona acts, its personality traits, and how it should respond to users. This is a multi-line text area.
* **Summary prompt override**: a multi-line text area for a custom summary prompt. This overrides the default summary prompt used by the *LLM server* for conversation summarization.
* **CSS override**: a *CSS* code editor with syntax highlighting that lets you customize the chatbot's appearance in the web interface. You can override colors, fonts, layouts and other visual elements. The editor supports standard *CSS* syntax with code folding, bracket matching, and keyboard shortcuts.

#### System Group

* **Behavior Similarity Threshold (%)**: controls how strictly the embedding engine matches user messages to persona behaviors. Range: 1-100. Default: 80. Higher values mean stricter matching (the persona behaves more consistently), while lower values allow more variation.
* **Response mode**: a drop-down list that controls how the *LLM server* generates responses:
  * **Legacy (default)**: the original response generation mode.
  * **Modern (stream)**: streaming response mode that delivers tokens as they are generated, providing a faster perceived response time.

## About Dialog

The *About* dialog is accessible from the *Help* menu (both in the main window and the system tray popup). It displays:

* The *application title* ("Service Manager")
* The *version number* (read from the *executable's version resources*)
* The *copyright notice*: "©2026 Robert Abraham. All rights reserved."
* A *logo image*
* The full *license text* loaded from `doc/license.rtf`

---

## Everyday Use

* **Opening and closing the chatbot**: right-click the *Ashley tray icon* in the taskbar and choose *Open Web UI*. The chat window is a standalone application that you can close and reopen at any time. The AI service keeps running in the background.
* **Changing the Personality**: right-click the *Ashley tray icon* and choose *Settings*. Go to the *Persona* tab. Pick a personality from the drop-down list at the top of the tab. Optionally edit the personality *name*, *description*, *avatar image*, *background image* or *CSS theme*. Click *OK* to save and close.
* **Changing the Model or compute device**: open *Settings* from the *tray menu*. Go to the *Engine Settings* tab. Change the engine or pick a different model file, then click *OK*.
* **Adding a new Model**: in *Settings*, go to the *Engine Settings* tab and click *Add*. Select a `.gguf` file from your computer. The model is copied into Ashley's `model` folder and appears in the drop-down list immediately. Click *OK*.
* **Enabling and disabling the embedding engine**: open *Settings* from the *tray menu*. Go to the *Embedding* tab. Check or uncheck the *Enable embedding* option. Optionally select an *embedding model* and adjust its parameters. Click *OK*. Embedding models are used for smart *behavior matching*. Ashley can recognize what kind of question you are asking and respond more naturally as a result.
* **Viewing and clearing log files**: open *Settings* from the *tray menu*. Go to the *Logging and Proxy* tab. Click *Open Log Folder* to open the log folder in File Explorer or click *Clear Log* to empty the log file.
* **Stopping Ashley**: right-click the *tray icon* and choose *Exit*. Ashley will ask for confirmation and then stop the AI service and close all windows. **Always use the tray icon to stop Ashley. Do NOT just end the process in Task Manager as this can leave temporary files behind and corrupt the configuration.**
* **Restarting the AI service**: right-click the *tray icon* and choose *Restart*. The AI service is restarted automatically.

## Directory Structure

* **`manager.exe`**: this is the Ashley *Service Manager*. It runs from the *system tray*, manages the built-in services and displays the *Settings window*.
* **`wrapper.exe`**: this is the background service that runs the AI engine. It manages the *LLM process*, *embedding process*, *web server* and *proxy*.
* **`llama` folder**: this folder contains the *LLM engine* binaries bundled with Ashley. Do not modify anything inside this folder.
  - **`cpu` subdirectory**: contains the CPU-only engine that works on every PC.
  - **`cuda12` subdirectory**: contains the *NVIDIA CUDA* engine that requires *CUDA 12.x toolkit*.
  - **`cuda13` subdirectory**: contains the *NVIDIA CUDA* engine that requires *CUDA 13.x toolkit*.
  - **`vulkan` subdirectory**: contains the *Vulkan* engine that works on *AMD*, *Intel* and *NVIDIA GPUs*.
  - **`radeon` subdirectory**: contains the *Radeon* engine but it is not tested yet.
* **`model` folder**: your AI *model* files with the `.gguf` extension are stored here. Place your *conversational* models directly in this folder.
  - **`model\embedding` folder**: *embedding model* files are stored here. Embedding models are used for behavior matching.
* **webserver folder**: this folder contains the *NGINX web server*, *PHP runtime*, and *embedded web client*. Do not modify files in this folder unless you know what you are doing.
  - **`webserver\webclient.exe`**: this is the *CEF*-based chat window application. It is a standalone browser window that loads the chat interface.
  - **`webserver\settings.json`**: this file contains the web client settings including window size and web server configuration.
  - **`webserver\conf` folder**: this folder contains web server configuration files.
  - **`webserver\www` folder**: this folder contains the web chatbot files including *HTML*, *CSS*, and *JavaScript*.
* **`config` folder**: this folder contains *JSON* configuration files. Advanced users can modify these files directly if needed.
* **`database` folder**: this folder contains *SQLite* databases. Do not delete or modify anything inside this folder while Ashley is running.
  - **`database\wrapper.db`**: this database stores the background service configuration including engine settings and parameters.
  - **`database\personality.db`**: this database stores persona definitions and behavior matching data.
* **`log` folder**: this folder contains *log* files written by the AI services. Check these files if you need to troubleshoot problems.
* **`temp` folder**: this folder contains *temporary files* created by the *PHP runtime*, *web server*, and other services. You can clear this folder when no services are running.

## Understanding the Architecture

Ashley consists of three main components working together:

1. **Service Manager (`manager.exe`)**: runs in the *system tray* and provides the graphical interface for configuration. It manages the lifecycle of the background services.
2. **The Service Wrapper (`wrapper.exe`)**: background process that starts and monitors the AI services. It launches the *LLM server*, *embedding server*, *PHP FastCGI*, and *NGINX web server*. It also includes a *watchdog* that automatically restarts any crashed services.
3. **Frontend**: web-based chatbot interface that runs in the *CEF browser* window or any *web browser*. It communicates with the *LLM* through the *proxy* managed by the *wrapper* or directly the *LLM engine*.

The AI interaction flow works as follows:

1. When you send a message in the chat window, the *frontend* sends the message to the *NGINX web server* which handles the *PHP code* and/or redirects the message to the *LLM engine*.
2. The *ChatController* sends the *request* through the *proxy* to the *LLM engine*.
3. The *LLM engine* processes your input and generates a *response*.
   * If *embedding* is enabled, your message may be analyzed for *behavior matching* before being sent to the *LLM engine*.
4. The *response* flows back through the same path to be displayed in the chat window.

---

## Database Documentation

The application provides access to database documentation from the *Help* menu:

* **Wrapper Database Documentation**: opens the *service wrapper database documentation*, which documents the schema of `database/wrapper.db`. This file contains engine configurations, parameters and web server defaults.
* **Personality Database Documentation**: opens the *personality database documentation*, which documents the schema of `database/personality.db`. This file contains persona definitions and default settings stored in the database.

These documents are intended for advanced users and developers who need to understand the internal data structures.

## Frontend Documentation

The **Frontend Documentation** option in the *Help* menu opens the *frontend documentation* in your default web browser. This document describes the web-based chatbot interface, its HTML/CSS/JavaScript structure, and how it communicates with the backend services. This is intended for developers and advanced users who want to customize or extend the web interface.

---

## Troubleshooting

* **The service failed to start**: a common cause is that the selected model file is missing or corrupted. Open *Settings* and check the *Engine Settings* tab to confirm a model file is selected and the path is correct. If you added a model manually, make sure the `.gguf` file is inside the model folder. Also check that no other application is using port **8080** or **8081** (or the HTTP[S] ports selected for the *LLM- and embedding engine*). This can happen if a previous instance of Ashley is still running. Open Task Manager, look for `manager.exe` and `wrapper.exe`, end them, then try again.
* **Chatbot says Both AI Services Disabled**: at least one service (the *conversational LLM* and/or the *embedding engine*) must be enabled. Open *Settings*, go to the *Embedding* tab and make sure *Enable embedding* is checked and/or go to the *Engine Settings* tab to confirm a model is selected.
* **Chatbot is slow or delays in responses**: on CPU-only hardware, responses are naturally slower than on a GPU. If you have a *CUDA*-capable *NVIDIA GPU*, open *Settings* and change the engine to *CUDA* on the *Engine Settings* tab. Large context window sizes also need more *RAM*. Reduce the context size at the parameters if you are running out of memory.
* **Web UI cannot open or Connection refused**: make sure the *LLM service* is running by checking the *system tray icon*. If the service is running but the *Web UI window* still fails to open, try opening the chatbot directly in a *browser* at `http://localhost/`. Port 80 or 443 may also be in use by another program such as *IIS*, *Apache* or *Skype*. Open *Settings*, go to the *Web Server* tab and change the ports or access the interface directly at `http://localhost:8080/` for *conversational* AI or `http://localhost:8081/` for the *embedding engine*.
* **Chatbot says the model cannot be found**: the model file was moved, renamed, or deleted after Ashley was configured. Open *Settings*, go to the *Engine Settings* tab, select the correct `.gguf` file from the drop-down list and click *OK*.
* **SSL or HTTPS error**: Ashley generates a *self-signed security certificate* on first start. If it becomes corrupted or expired, Ashley regenerates it automatically the next time the AI service starts. If the problem persists, delete the files `webserver\conf\ssl\nginx.crt` and `webserver\conf\ssl\nginx.key`, then restart the AI service from the *tray icon*.
* **Error loading database**: the files `database\wrapper.db` or `database\personality.db` may have been deleted or moved. Do NOT delete or move anything inside the database folder while Ashley is not running. If a database file is truly missing, re-extract Ashley from the original archive and copy your model folder back into it.

## Tips and Best Practices

* Always click *OK* to save any changes you make in *Settings*. Changes are not saved automatically.
* Ashley's *system tray icon* in the bottom-right of the taskbar is the quickest way to check whether the AI service is running. The icon indicates the current state of the services.
* *Log files* are in the `log` folder if you need to report a problem to support.
* For best results with the *CUDA* engine on *NVIDIA GPU*s, install the latest *NVIDIA driver*s from https://www.nvidia.com/drivers first.
* The *Open Web UI* button launches a separate chat window. You can open and close it as many times as you like while the service runs.
* When importing *models*, ensure the files have the `.gguf` extension and do not contain spaces or special characters in the filename.
* Use the *Load Defaults for LLM engine* button to restore engine-specific default parameters if you have customized them and want to start over.
* The *Behavior Similarity Threshold* in the *Persona* tab affects how the embedding engine matches user intent. Adjust it carefully: too high and the persona becomes rigid; too low and it becomes inconsistent.
* The `temp/` folder can be safely cleared when the service is stopped to free up disk space.
* If you experience port conflicts, check the *Logging and Proxy* tab for the proxy port and the *Web Server* tab for HTTP/HTTPS/PHP ports. Common conflicting applications include *IIS*, *Apache*, *Skype* and other web servers.
* The *About* dialog shows the exact version of the Service Manager. Use this when reporting issues.

---

## Support Information

**Copyright © 2026 Robert Abraham. All rights reserved.**

For additional help, refer to the `readme.txt` file in the Ashley folder for quick start instructions.
