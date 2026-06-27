Manager - Service Manager GUI

The Manager is the central control application for Ashley. It provides a system-tray GUI for managing the LLM service lifecycle, configuring engines/models/personas, and launching the web-based chat interface. Built with Free Pascal and the LCL (Lazarus Component Library), it runs on Windows and Linux.

Units

* main_form.pas: main application form. Handles service control (START/STOP/RESTART), system tray icon, process management, SSL certificate generation, embedding vector generation, Web UI launch, and menu/event routing.

* settings_form.pas: settings dialog. Provides a 5-tab interface for configuring the LLM engine, model, embedding engine, proxy/logging, web server, and persona (avatar, system prompt, CSS theming). Reads/writes wrapper.json and personality.json.

* about_form.pas: about dialog. Displays the application title, version (from PE resources), copyright, logo, and license text.

* vinfo.pas: PE version-info reader. Retrieves FileVersion, ProductName, CompanyName, and InternalName from the executable's version resource for display in the About dialog.

Building

Prerequisites

* Free Pascal Compiler (FPC) 3.2+

* Lazarus IDE

* LCL, FCL, SQLDBLaz

* SynEdit + SynEditDsgn (settings form CSS editor)

* richmemo_design + richmemopackage (about form rich text)

Release build: lazbuild --bm=Release manager.lpi

Output: ../server/manager.exe

Architecture

manager.exe

TMainForm

* System tray icon (TTrayIcon) with popup menu

* Service control: START / STOP / RESTART wrapper.exe

* Process management: LLMserverProcess, SSLcertificateProcess, EmbeddingGenerationProcess, WebUIprocess

* Periodic status polling via TTimer

* Single-instance enforcement (named mutex on Windows, flock on UNIX)

* Menu handlers for documentation, settings, about

TSettingsForm

* Engine tab: engine selection, model import, device selection, parameters

* Embedding tab: embedding model, parameters, enable/disable toggle

* Logging & Proxy tab: log clearing, proxy port/timeout/connections/size

* Web Server tab: nginx HTTP/HTTPS ports, SSL cert/key, PHP port

* Persona tab: avatar/background images, system prompt, CSS override, response mode, behavior similarity threshold

TMainForm owns all background processes (TProcess) and delegates configuration to TSettingsForm. Saved configuration is written to config/wrapper.json, config/personality.json and webserver/conf/nginx.conf. The wrapper database (database/wrapper.db and database/personality.db) provides engine defaults and persona definitions.

Runtime Dependencies

* wrapper.exe: background service running the LLM engine

* webserver/webclient.exe: CEF-based chat window

* webserver/nginx.exe: HTTP/HTTPS reverse proxy

* webserver/php/php.exe: PHP-FPM for backend scripts

* config/wrapper.json: generated on first save

* config/personality.json: generated on first save
