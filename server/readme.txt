==========================================================
  ASHLEY - Local LLM Service Manager
  Quick Start Manual | Copyright (c) 2026 Robert Abraham
==========================================================

Ashley is a complete, single-click local AI assistant for Windows.  It bundles an LLM inference engine, a web chatbot interface, and a settings manager into one package - no Internet connection or cloud API key required.

-----------------------
  SYSTEM REQUIREMENTS
-----------------------

Before running Ashley, ensure the following prerequisites are installed on your Windows 10/11 system.

Microsoft Visual C++ 2015-2022 Redistributable (x64):
Ashley's bundled Llama.cpp backend and web server binaries are compiled with Microsoft Visual C++ and require the **Microsoft Visual C++ 2015–2022 Redistributable (x64)** to be present on the system.
Download: https://aka.ms/vs/17/release/vc_redist.x64.exe
Minimum version: 14.34.0 (Visual Studio 2022)

NVIDIA GPU Drivers and CUDA Toolkit:
If you intend to use NVIDIA CUDA acceleration, install a matching CUDA Toolkit version for your selected backend and keep your NVIDIA driver up to date.
* CUDA 12.x: https://developer.nvidia.com/cuda-12-0-download-archive
* CUDA 13.x: https://developer.nvidia.com/cuda-downloads
Also install the latest Game Ready / Studio driver from: https://www.nvidia.com/drivers

AMD Radeon / ROCm (Radeon backend):
If you intend to use the AMD Radeon backend (radeon/), install the ROCm software stack and verify your GPU appears under supported hardware: https://rocm.docs.amd.com/en/latest/deploy/gpus/index.html
Note: ROCm is officially supported on Linux; Windows support is experimental.

-----------------------------------
  QUICK START  (first time setup)
-----------------------------------

1. Unzip the release archive to a folder of your choice (for example: `C:\AI\Ashley\`)

2. Open that folder and double-click: `manager.exe`. Ashley starts automatically. A small icon appears in the Windows taskbar (system tray, bottom-right corner of the screen)

3. On first startup (or when no configuration file detected), the application will open the `Settings` menu so you can make sure everything is configured properly before starting the actual services (confirmation required)

4. When running the application normally (the services are configured properly), then application will start the services

5. When configuration or fine-tuning needed, right-click the tray icon and choose `Settings` to open the Settings window

6. The first thing to do is pick an LLM/EMBEDDING ENGINE. The engine selection is on the very first tab in the Settings window. Choose the engine that matches your hardware:
* CPU: works on every Windows PC; no extra software needed
* CUDA: NVIDIA GPU required (faster than CPU)
* Vulkan: AMD / Intel / NVIDIA GPU (no CUDA toolkit needed)
* HIP Radeon: Radeon GPU required (not tested yet!)
Also choose a model file (".gguf") for the engine to use

7. Click `OK` at the bottom of the window. Ashley configures everything, generates a security certificate if needed and starts the AI service in the background.

8. Right-click the tray icon again and choose `Open Web UI` to launch the chatbot window (but you can also access the service from your web browser on http[s]://localhost:port/, where `port` is the HTTP[S] port configured in the settings window)

----------------
  EVERYDAY USE
----------------

Opening / closing the chatbot: right-click the Ashley tray icon in the taskbar and choose  Open Web UI. The chat window is a standalone application - you can close and reopen it at any time. The AI service keeps running in the background.

Changing the Personality:
1. Right-click the Ashley tray icon and choose `Settings`
2. Go to the `Persona` tab
3. Pick a personality from the drop-down list at the top of the tab
4. (Optional) Edit the personality name, description, avatar image, background image or CSS theme
5. Click `OK` to save and close

Changing the Model or compute device:
1. Open `Settings` from the tray menu
2. Go to the `Engine Settings` tab
3. Change the engine or pick a different model file, then click `OK`

Adding a new Model:
1. In `Settings > Engine Settings`, click `Add Model...`
2. Select a `.gguf` file from your computer
3. The model is copied into Ashley's `model\` folder and appears in the drop-down list immediately
4. Click `OK`

Enabling / disabling the embedding engine:
1. Open `Settings` from the tray menu
2. Go to the `Embedding` tab
3. Check or uncheck the `Enable embedding` option
4. (Optional) Select an embedding model and adjust its parameters
5. Click `OK`
Embedding models are used for smart behaviour matching - Ashley can recognise what kind of question you are asking and respond more naturally as a result.

Viewing and clearing log files:
1. Open `Settings` from the tray menu
2. Go to the `Logging and Proxy` tab
3. Click `Open Log Folder` to open the log folder in File Explorer or `Clear Log` to empty the log file

Stopping Ashley: right-click the tray icon and choose `Exit`. Ashley will ask for confirmation and then stop the AI service and close all windows. Always use the tray icon to stop Ashley.  Do NOT just end the process in Task Manager - this can leave temporary files behind and corrupt the configuration.

Restarting the AI service: right-click the tray icon and choose `Restart services`. All services are restarted automatically without closing the Settings window.

-----------------------------------
  TABS OVERVIEW (Settings window)
-----------------------------------

* `Engine Settings`: select the LLM/Embedding engine (CPU / CUDA / Vulkan / Radeon) and choose the model file that the engine will use. This is the first tab and the most important setup step.
* `Embedding`: enable or disable the embedding engine and choose an embedding model file for behaviour matching.
* `Logging and Proxy`: view or clear log files, and adjust the internal API proxy settings (port, timeout, max connections).
* `Web Server`: configure the built-in web server ports (HTTP / HTTPS) and the SSL certificate. Normally leave these at their default values.
* `Persona`: choose and customise the chatbot's personality, avatar, background image and CSS theme.

--------------------------------------------
  FOLDER LAYOUT (inside the Ashley folder)
--------------------------------------------

* `manager.exe`: the Ashley Settings Manager (system tray + settings GUI)
* `wrapper.exe`: the background service manager that runs and monitors the AI engine, web server, PHP runtime and API proxy
* `llama\`: LLM engine binaries bundled with Ashley (do not modify)
- `cpu\`: CPU-only engine (works on every PC)
- `cuda12\`: NVIDIA CUDA engine (requires CUDA 12.x toolkit)
- `cuda13\`: NVIDIA CUDA engine (requires CUDA 13.x toolkit)
- `vulkan\`: Vulkan engine (works on AMD, Intel and NVIDIA GPUs)
- `radeon\`: Radeon engine (not tested yet!)
* `model\`: your AI model files (.gguf) are stored here
- `embedding\`: embedding model files are stored here
* `webserver\`: NGINX web server + PHP runtime + web chatbot application
- `webclient.exe`: CEF-based chat window (standalone)
- `settings.json`: web client settings (advanced)
- `conf\`: web server configuration
- `www\`: web chatbot application files (Symfony/PHP)
* `config\`: JSON configuration files (advanced)
* `database\`: SQLite databases (advanced - do not modify)
- `wrapper.db`: background service settings (SQLite database)
- `personality.db`: chatbot personality and behavior data (SQLite database)
* `log\`: log files
* `temp\`: temporary files

-------------------
  TROUBLESHOOTING
-------------------

`The service failed to start`:
A common cause is that the selected model file is missing or corrupted. Open Settings and check the `Engine Settings` tab: confirm a model file is selected and the path is correct. If you added a model manually, make sure the `.gguf` file is inside the `model\` folder.
Also check that no other application is using port 8080 or 8081. This can happen if a previous instance of Ashley is still running. Open Task Manager, look for `manager.exe` and `wrapper.exe`, end them, then try again.

Chatbot says `Both AI Services Disabled`:
At least one service (the conversational LLM and/or the embedding engine) must be running. Open `Settings` and make sure `Enable LLM server` on the `Engine Settings` tab or `Enable embedding` on the `Embedding` tab is checked, and that a model is selected for all enabled servers.

Chatbot is slow / delays in responses:
On CPU-only hardware, responses are naturally slower than on a GPU. If you have a CUDA-capable NVIDIA GPU, open `Settings` and change the engine to CUDA (Engine Settings tab). Large context window sizes also need more RAM - reduce the context size at the parameters if you are running out of memory.

`Web UI cannot open` / `Connection refused`:
make sure the services are running - check the system tray icon. If the service is running but the Web UI window still fails to open, try opening the chatbot directly in a browser at:
`http://localhost/`
Port 80 or 443 may also be in use by another program (IIS, Apache, Skype, etc.). Open `Settings > Web Server` and change the ports or access the interface directly at:
http://localhost:8080/ (conversational AI)
http://localhost:8081/ (embedding engine)

Chatbot says the model cannot be found:
The model file was moved, renamed or deleted after Ashley was configured. Open `Settings > Engine Settings`, select the correct `.gguf` file from the drop-down list and click `OK`.

SSL / HTTPS error:
Ashley generates a self-signed security certificate on first start. If it becomes corrupted or expired, Ashley regenerates it automatically the next time the AI service starts. If the problem persists, delete:
`webserver\conf\ssl\nginx.crt`
`webserver\conf\ssl\nginx.key`
and restart the AI service from the tray icon.

`Error loading database`:
The files `database\wrapper.db` or `database\personality.db` may have been deleted or moved. Do NOT delete or move anything inside the `database\` folder while Ashley is not running.
If a database file is truly missing, re-extract Ashley from the original archive and copy your `model\` folder back into it.

General tips:
* Always click `OK` to save any change you make in Settings - changes are not saved automatically
* Ashley's system tray icon (bottom-right of the taskbar) is the quickest way to check whether the AI service is running
* Log files are in the `log\` folder if you need to report a problem
* For best results with the CUDA engine on NVIDIA GPUs, install the latest NVIDIA drivers from `https://www.nvidia.com/drivers` first
* The `Open Web UI` button launches a separate chat window; you can open and close it as many times as you like while the service runs

=====================================
  Copyright (c) 2026 Robert Abraham
=====================================
