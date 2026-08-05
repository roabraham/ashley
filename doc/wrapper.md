# Service Wrapper Documentation

**Overview:** Llama Service Wrapper - A cross-platform service manager for LLM server processes, web servers, PHP FastCGI, and API proxy.

---

## Table of Contents

- [Classes & Types](#classes--types)
- [Methods & Functions](#methods--functions)
- [Fields & Properties](#fields--properties)
- [Constants](#constants)

---

## Classes & Types

### `JOBOBJECT_BASIC_LIMIT_INFORMATION`

Windows Job Object limit information structure for process job management.

```pascal
JOBOBJECT_BASIC_LIMIT_INFORMATION = record
```

### `IO_COUNTERS`

Windows I/O performance counters structure.

```pascal
IO_COUNTERS = record
```

### `JOBOBJECT_EXTENDED_LIMIT_INFORMATION`

Extended Windows Job Object information structure with memory limits.

```pascal
JOBOBJECT_EXTENDED_LIMIT_INFORMATION = record
```

### `EWatchdogFatal`

Exception raised when a fatal error occurs in the watchdog thread, causing termination.

```pascal
EWatchdogFatal = class(Exception);
```

### `TListenerThread`

Background thread that listens for incoming network connections without blocking the manager thread.

```pascal
TListenerThread = class(TThread)
```

### `TWorkerThread`

Background thread that handles a single isolated client request by proxying to LLM server.

```pascal
TWorkerThread = class(TThread)
```

### `TProxyThread`

Manager thread that listens for connections and monitors worker threads.

```pascal
TProxyThread = class(TThread)
```

### `TServiceWrapper`

Main application class that manages LLM server processes, web servers, PHP FastCGI, and API proxy.

```pascal
TServiceWrapper = class(TCustomApplication)
```

---

## Methods & Functions

### `CreateJobObjectW`

Creates or opens a job object in Windows.

```pascal
function CreateJobObjectW(lpJobAttributes: Pointer; lpName: PWideChar): THandle; stdcall; external 'kernel32.dll';
```

### `SetInformationJobObject`

Sets information for a job object in Windows.

```pascal
function SetInformationJobObject(hJob: THandle; JobObjectInfoClass: Integer; lpJobObjectInfo: Pointer; cbJobObjectInfoLength: DWORD): BOOL; stdcall; external 'kernel32.dll';
```

### `AssignProcessToJobObject`

Assigns a process to an existing job object in Windows.

```pascal
function AssignProcessToJobObject(hJob: THandle; hProcess: THandle): BOOL; stdcall; external 'kernel32.dll';
```

### `Execute`

Main thread execution - blocks waiting for incoming connections.

```pascal
procedure Execute; override;
```

### `Create`

Initializes the listener thread with the given server instance.

```pascal
constructor Create(AServer: TInetServer);
```

### `InternalReadLine`

Reads a line from the socket stream with timeout support.

```pascal
function InternalReadLine(Stream: TSocketStream): AnsiString;
```

### `GetContentLength`

Extracts the Content-Length value from HTTP headers.

```pascal
function GetContentLength(const Headers: AnsiString): Integer;
```

### `SendHttpError`

Sends an HTTP error response to the client.

```pascal
procedure SendHttpError(Stream: TSocketStream; Code: Integer; Msg: AnsiString);
```

### `Execute`

Main thread execution - handles the request/response cycle.

```pascal
procedure Execute; override;
```

### `Create`

Initializes the worker thread with connection and routing parameters.

```pascal
constructor Create(AHandle: TSocket; ATargetPort, ATargetEmbeddingPort: Integer; AEndpoint, AEmbeddingEndpoint: string; ATimeout, AmaxPackageSize: Integer);
```

### `CleanupFinishedWorkers`

Removes and frees finished worker threads from the list.

```pascal
procedure CleanupFinishedWorkers;
```

### `EnforceTimeouts`

Terminates workers that have exceeded the timeout limit.

```pascal
procedure EnforceTimeouts;
```

### `Execute`

Main thread execution - manages listener and worker lifecycle.

```pascal
procedure Execute; override;
```

### `Create`

Initializes the proxy thread with routing and connection parameters.

```pascal
constructor Create(AProxyHost: String; APort, ATargetPort, ATargetEmbeddingPort: Integer; AEndpoint, AEmbeddingEndpoint: String; ATimeout, AMax, Apmax: Integer);
```

### `Destroy`

Frees the proxy thread and cleans up resources.

```pascal
destructor Destroy; override;
```

### `CheckSingleInstance`

Verifies no other instance is running, returns False if already running.

```pascal
function CheckSingleInstance: Boolean;
```

### `IsPortFree`

Checks if a TCP port is available for binding.

```pascal
function IsPortFree(APort: Integer): Boolean;
```

### `ExecAndCapture`

Executes an external command and captures output.

```pascal
function ExecAndCapture(const command: AnsiString; const parameters: TStringList): Integer;
```

### `CheckCertificateExpiration`

Checks if SSL certificate is expired or within renewal window.

```pascal
function CheckCertificateExpiration(const CertFile: AnsiString; ExpirationDays: Integer): Boolean;
```

### `InitPaths`

Initializes all path variables based on executable location.

```pascal
procedure InitPaths;
```

### `SetupDatabase`

Opens connection to the SQLite configuration database.

```pascal
procedure SetupDatabase;
```

### `LoadConfiguration`

Loads server and proxy configuration from database and JSON file.

```pascal
procedure LoadConfiguration;
```

### `GenerateSslCertificate`

Generates a self-signed SSL certificate using OpenSSL.

```pascal
procedure GenerateSslCertificate(const CertFile, KeyFile: AnsiString);
```

### `GenerateSslCertificateIfNeeded`

Generates SSL certificate if missing or expiring soon.

```pascal
procedure GenerateSslCertificateIfNeeded;
```

### `WaitUntilPortFree`

Blocks until the specified port becomes available.

```pascal
procedure WaitUntilPortFree(APort: Integer);
```

### `StartProxy`

Starts the API proxy service on the given port.

```pascal
procedure StartProxy(AProxyPort, ATargetPort, ATargetEmbeddingPort: Integer);
```

### `StopProxy`

Stops the API proxy service.

```pascal
procedure StopProxy;
```

### `RunWatchdog`

Main watchdog loop that monitors and restarts failed processes.

```pascal
procedure RunWatchdog;
```

### `Cleanup`

Releases all resources and terminates child processes.

```pascal
procedure Cleanup;
```

### `ShowHelp`

Displays command-line help and usage information.

```pascal
procedure ShowHelp;
```

### `DoRun`

Main application entry point for the service wrapper.

```pascal
procedure DoRun; override;
```

### `Create`

Initializes the service wrapper application.

```pascal
constructor Create(TheOwner: TComponent); override;
```

### `Destroy`

Frees the service wrapper and all associated resources.

```pascal
destructor Destroy; override;
```

### `HandleGlobalException`

Global exception handler that logs and terminates on fatal errors.

```pascal
procedure HandleGlobalException(Sender: TObject; E: Exception);
```

### `Routine`

TListenerThread implementation.

```pascal
constructor TListenerThread.Create(AServer: TInetServer);
```

### `Routine`

TListenerThread.Create initializes the listener thread with the given server instance.

```pascal
constructor TListenerThread.Create(AServer: TInetServer);
```

### `TListenerThread.Execute`

Waits for and accepts incoming TCP connections.

```pascal
procedure TListenerThread.Execute;
```

### `Routine`

TWorkerThread implementation.

```pascal
constructor TWorkerThread.Create(AHandle: TSocket; ATargetPort, ATargetEmbeddingPort: Integer; AEndpoint, AEmbeddingEndpoint: string; ATimeout, AmaxPackageSize: Integer);
```

### `Routine`

TWorkerThread.Create initializes the worker thread with connection and routing parameters.

```pascal
constructor TWorkerThread.Create(AHandle: TSocket; ATargetPort, ATargetEmbeddingPort: Integer; AEndpoint, AEmbeddingEndpoint: string; ATimeout, AmaxPackageSize: Integer);
```

### `TWorkerThread.SendHttpError`

Sends an HTTP error response to the client stream.

```pascal
procedure TWorkerThread.SendHttpError(Stream: TSocketStream; Code: Integer; Msg: AnsiString);
```

### `TWorkerThread.InternalReadLine`

Reads a line of text from the socket stream with timeout support.

```pascal
function TWorkerThread.InternalReadLine(Stream: TSocketStream): AnsiString;
```

### `TWorkerThread.GetContentLength`

Extracts the Content-Length value from HTTP headers string.

```pascal
function TWorkerThread.GetContentLength(const Headers: AnsiString): Integer;
```

### `TWorkerThread.Execute`

Main thread method that handles the complete request/response cycle by proxying to LLM server.

```pascal
procedure TWorkerThread.Execute;
```

### `Routine`

TProxyThread implementation.

```pascal
constructor TProxyThread.Create(AProxyHost: String; APort, ATargetPort, ATargetEmbeddingPort: Integer; AEndpoint, AEmbeddingEndpoint: String; ATimeout, AMax, Apmax: Integer);
```

### `TProxyThread.Create`

Initializes the proxy thread with routing and connection parameters.

```pascal
constructor TProxyThread.Create(AProxyHost: String; APort, ATargetPort, ATargetEmbeddingPort: Integer; AEndpoint, AEmbeddingEndpoint: String; ATimeout, AMax, Apmax: Integer);
```

### `TProxyThread.Destroy`

Terminates all workers and frees the proxy thread resources.

```pascal
destructor TProxyThread.Destroy;
```

### `TProxyThread.CleanupFinishedWorkers`

Removes and frees finished worker threads from the active list.

```pascal
procedure TProxyThread.CleanupFinishedWorkers;
```

### `TProxyThread.EnforceTimeouts`

Terminates workers that have exceeded the timeout limit.

```pascal
procedure TProxyThread.EnforceTimeouts;
```

### `TProxyThread.Execute`

Main thread method that manages the listener and spawns worker threads for connections.

```pascal
procedure TProxyThread.Execute;
```

### `Routine`

TServiceWrapper implementation (Boilerplate and Glue).

```pascal
procedure TServiceWrapper.StartProxy(AProxyPort, ATargetPort, ATargetEmbeddingPort: Integer);
```

### `TServiceWrapper.StartProxy`

Creates and starts the API proxy service thread.

```pascal
procedure TServiceWrapper.StartProxy(AProxyPort, ATargetPort, ATargetEmbeddingPort: Integer);
```

### `TServiceWrapper.StopProxy`

Stops the API proxy service thread gracefully.

```pascal
procedure TServiceWrapper.StopProxy;
```

### `TServiceWrapper.CheckSingleInstance`

Verifies no other instance is running, preventing duplicate execution.

```pascal
function TServiceWrapper.CheckSingleInstance: Boolean;
```

### `TServiceWrapper.IsPortFree`

Check for IPv4 and optional IPv6 availability. Returns True if port can be bound OR if protocol is completely unsupported by OS, False otherwise.

```pascal
function TServiceWrapper.IsPortFree(APort: Integer): Boolean;
```

### `Helper`

Try to bing port without blocking.

```pascal
function TryBind(Family: SmallInt): Boolean;
```

### `TServiceWrapper.HandleGlobalException`

Global exception handler that logs error and terminates application.

```pascal
procedure TServiceWrapper.HandleGlobalException(Sender: TObject; E: Exception);
```

### `TServiceWrapper.InitPaths`

Initializes all path variables based on executable location.

```pascal
procedure TServiceWrapper.InitPaths;
```

### `TServiceWrapper.SetupDatabase`

Opens connection to the SQLite configuration database.

```pascal
procedure TServiceWrapper.SetupDatabase;
```

### `TServiceWrapper.LoadConfiguration`

Loads server and proxy configuration from database and JSON file.

```pascal
procedure TServiceWrapper.LoadConfiguration;
```

### `TServiceWrapper.GenerateSslCertificate`

Generates a self-signed SSL certificate using OpenSSL.

```pascal
procedure TServiceWrapper.GenerateSslCertificate(const CertFile, KeyFile: AnsiString);
```

### `TServiceWrapper.GenerateSslCertificateIfNeeded`

Checks certificate expiration and generates if needed.

```pascal
procedure TServiceWrapper.GenerateSslCertificateIfNeeded;
```

### `TServiceWrapper.ExecAndCapture`

Executes an external command and captures output, returning exit code.

```pascal
function TServiceWrapper.ExecAndCapture(const command: AnsiString; const parameters: TStringList): Integer;
```

### `TServiceWrapper.CheckCertificateExpiration`

Checks if SSL certificate is expired or within renewal window.

```pascal
function TServiceWrapper.CheckCertificateExpiration(const CertFile: AnsiString; ExpirationDays: Integer): Boolean;
```

### `TServiceWrapper.WaitUntilPortFree`

Blocks until the specified port becomes available for binding.

```pascal
procedure TServiceWrapper.WaitUntilPortFree(APort: Integer);
```

### `TServiceWrapper.RunWatchdog`

Main watchdog loop that monitors and restarts failed processes.

```pascal
procedure TServiceWrapper.RunWatchdog;
```

### `TServiceWrapper.ShowHelp`

Displays command-line help and usage information.

```pascal
procedure TServiceWrapper.ShowHelp;
```

### `TServiceWrapper.Cleanup`

Releases all resources and terminates child processes gracefully.

```pascal
procedure TServiceWrapper.Cleanup;
```

### `DoSigInt`

Signal handler for SIGINT/SIGTERM signals on Unix platforms.

```pascal
procedure DoSigInt(Sig: LongInt); cdecl;
```

### `TServiceWrapper.DoRun`

Main application entry point that processes command-line arguments and starts services.

```pascal
procedure TServiceWrapper.DoRun;
```

### `TServiceWrapper.Create`

Initializes the service wrapper application.

```pascal
constructor TServiceWrapper.Create(TheOwner: TComponent);
```

### `TServiceWrapper.Destroy`

Frees the service wrapper and all associated resources.

```pascal
destructor TServiceWrapper.Destroy;
```

---

## Fields & Properties

### `Field`

Llama Service Wrapper - A cross-platform service manager for LLM server processes, web servers, PHP FastCGI, and API proxy.

```pascal
program wrapper;
```

### `JobObjectExtendedLimitInformation`

Windows Job Object information class constant.

```pascal
JobObjectExtendedLimitInformation = 9;
```

### `FServer`

The TCP server socket that listens for incoming connections.

```pascal
FServer: TInetServer;
```

### `FNewSocket`

Socket handle for the newly accepted connection.

```pascal
FNewSocket: TSocket;
```

### `NewSocket`

Property to access the accepted client socket handle.

```pascal
property NewSocket: TSocket read FNewSocket;
```

### `FTargetPort`

The target port for the conversational LLM server.

```pascal
FTargetPort: Integer;
```

### `FTargetEmbeddingPort`

The target port for the embedding LLM server.

```pascal
FTargetEmbeddingPort: Integer;
```

### `FTargetEndpoint`

The endpoint path for the conversational LLM server.

```pascal
FTargetEndpoint: string;
```

### `FTargetEmbeddingEndpoint`

The endpoint path for the embedding LLM server.

```pascal
FTargetEmbeddingEndpoint: string;
```

### `FProxyTimeout`

Maximum time in seconds before the connection times out.

```pascal
FProxyTimeout: Integer;
```

### `FMaxPackageSize`

Maximum allowed request/response size in bytes.

```pascal
FMaxPackageSize: Integer;
```

### `FClientHandle`

Socket handle for the client connection.

```pascal
FClientHandle: TSocket;
```

### `FLlamaSocket`

Socket handle for the LLM server connection.

```pascal
FLlamaSocket: TSocket;
```

### `FStartTime`

Timestamp when the worker started processing the request.

```pascal
FStartTime: TDateTime;
```

### `StartTime`

Property to access the worker start timestamp.

```pascal
property StartTime: TDateTime read FStartTime;
```

### `FProxyHost`

Host address on which the proxy listens for incoming connections.

```pascal
FProxyHost: String;
```

### `FProxyPort`

The port on which the proxy listens for incoming connections.

```pascal
FProxyPort: Integer;
```

### `FTargetPort`

The target port for the conversational LLM server.

```pascal
FTargetPort: Integer;
```

### `FTargetEmbeddingPort`

The target port for the embedding LLM server.

```pascal
FTargetEmbeddingPort: Integer;
```

### `FTargetEndpoint`

The endpoint path for the conversational LLM server.

```pascal
FTargetEndpoint: String;
```

### `FTargetEmbeddingEndpoint`

The endpoint path for the embedding LLM server.

```pascal
FTargetEmbeddingEndpoint: String;
```

### `FProxyTimeout`

Maximum time in seconds before a worker times out.

```pascal
FProxyTimeout: Integer;
```

### `FProxyMaxConnections`

Maximum number of concurrent worker connections.

```pascal
FProxyMaxConnections: Integer;
```

### `FMaxPackageSize`

Maximum allowed request/response size in bytes.

```pascal
FMaxPackageSize: Integer;
```

### `FServerSocket`

The TCP server socket for accepting connections.

```pascal
FServerSocket: TInetServer;
```

### `FWorkers`

List of active worker threads.

```pascal
FWorkers: TFPList;
```

### `FInstanceID`

Unique identifier for the service instance (MD5 hash of executable path).

```pascal
FInstanceID: string;
```

### `FConn`

SQLite database connection.

```pascal
FConn: TSQLite3Connection;
```

### `FTrans`

Database transaction object.

```pascal
FTrans: TSQLTransaction;
```

### `FQuery`

SQL query object for configuration loading.

```pascal
FQuery: TSQLQuery;
```

### `FProcess`

Process object for the conversational LLM server.

```pascal
FProcess: TProcess;
```

### `FEmbeddingProcess`

Process object for the embedding LLM server.

```pascal
FEmbeddingProcess: TProcess;
```

### `FPhpProcess`

Process object for PHP FastCGI server.

```pascal
FPhpProcess: TProcess;
```

### `FWebserverProcess`

Process object for Nginx web server.

```pascal
FWebserverProcess: TProcess;
```

### `FAppDir`

Directory path of the application executable.

```pascal
FAppDir: AnsiString;
```

### `FConfigDir`

Configuration directory path.

```pascal
FConfigDir: AnsiString;
```

### `FModelDir`

Model files directory path.

```pascal
FModelDir: AnsiString;
```

### `FEmbeddingModelDir`

Embedding model files directory path.

```pascal
FEmbeddingModelDir: AnsiString;
```

### `FLlamaDir`

LLM server binaries directory path.

```pascal
FLlamaDir: AnsiString;
```

### `FServerBinary`

Full path to the LLM server executable.

```pascal
FServerBinary: AnsiString;
```

### `FDeviceID`

Device identifier for GPU/CPU selection.

```pascal
FDeviceID: string;
```

### `FEndpoint`

Conversational LLM endpoint path.

```pascal
FEndpoint: string;
```

### `FEmbeddingEndpoint`

Embedding LLM endpoint path.

```pascal
FEmbeddingEndpoint: string;
```

### `FinalFModelFile`

Resolved full path to the conversational model file.

```pascal
FinalFModelFile: AnsiString;
```

### `FinalFEmbeddingModelFile`

Resolved full path to the embedding model file.

```pascal
FinalFEmbeddingModelFile: AnsiString;
```

### `FParams`

Command-line parameters for the conversational LLM server.

```pascal
FParams: TStringList;
```

### `FEmbeddingParams`

Command-line parameters for the embedding LLM server.

```pascal
FEmbeddingParams: TStringList;
```

### `FLLMenabled`

Flag indicating whether LLM service is enabled.

```pascal
FLLMenabled: Boolean;
```

### `FEmbeddingEnabled`

Flag indicating whether embedding service is enabled.

```pascal
FEmbeddingEnabled: Boolean;
```

### `FUseLogFile`

Flag indicating whether to log to file.

```pascal
FUseLogFile: boolean;
```

### `FProxyHost`

Host address for the API proxy service to listen on.

```pascal
FProxyHost: String;
```

### `FProxyPort`

Port for the API proxy service.

```pascal
FProxyPort: integer;
```

### `FProxyTimeout`

Timeout in seconds for proxy connections.

```pascal
FProxyTimeout: integer;
```

### `FProxyMaxConnections`

Maximum concurrent connections for the proxy.

```pascal
FProxyMaxConnections: integer;
```

### `FMaxPackageSize`

Maximum request/response package size in bytes.

```pascal
FMaxPackageSize: integer;
```

### `FProxyThread`

The proxy manager thread instance.

```pascal
FProxyThread: TProxyThread;
```

### `FPhpPort`

Port for PHP FastCGI service.

```pascal
FPhpPort: Integer;
```

### `FWebserverHttpPort`

HTTP port for the web server.

```pascal
FWebserverHttpPort: Integer;
```

### `FWebserverHttpsPort`

HTTPS port for the web server.

```pascal
FWebserverHttpsPort: Integer;
```

### `FOpensslBinary`

Full path to OpenSSL executable.

```pascal
FOpensslBinary: AnsiString;
```

### `FWebserverBinary`

Full path to Nginx web server executable.

```pascal
FWebserverBinary: AnsiString;
```

### `FPhpBinary`

Full path to PHP-CGI executable.

```pascal
FPhpBinary: AnsiString;
```

### `FPhpHost`

Host address for PHP FastCGI binding.

```pascal
FPhpHost: AnsiString;
```

### `FSSLcertDir`

Directory containing SSL certificates.

```pascal
FSSLcertDir: AnsiString;
```

### `FSSLcertificate`

Full path to SSL certificate file.

```pascal
FSSLcertificate: AnsiString;
```

### `FSSLkey`

Full path to SSL key file.

```pascal
FSSLkey: AnsiString;
```

### `FSSLexpiration`

SSL certificate validity period in days.

```pascal
FSSLexpiration: Integer;
```

### `FSSGeneration`

Days before expiration to renew SSL certificate.

```pascal
FSSGeneration: Integer;
```

### `FSSLencryption`

SSL key encryption algorithm.

```pascal
FSSLencryption: AnsiString;
```

### `DBPath`

Full path to the SQLite database file.

```pascal
DBPath: AnsiString;
```

### `DBPathWAL`

Full path to the database WAL file.

```pascal
DBPathWAL: AnsiString;
```

### `DBPathSHM`

Full path to the database SHM file.

```pascal
DBPathSHM: AnsiString;
```

### `IsCertOnlyMode`

Flag indicating whether only SSL certificate generation is requested.

```pascal
IsCertOnlyMode: Boolean;
```

### `FJob`

Windows job object handle for process group management.

```pascal
FJob: THandle;
```

### `FMutex`

Windows mutex handle for single instance check.

```pascal
FMutex: THandle;
```

### `FLockFileHandle`

Unix file handle for lock file based single instance check.

```pascal
FLockFileHandle: Integer;
```

### `"error"`

"' + Msg + '"

```pascal
try
```

### `"error"`

"Llama server stalled"

```pascal
Break;
```

### `"error"`

"Empty response from LLM engine"

```pascal
Line := 'HTTP/1.1 200 OK' + #13#10 + 'Content-Type: application/json' + #13#10 +
```

### `Field`

IPPROTO_IPV6

```pascal
fpsetsockopt(S, IPPROTO_IPV6, IPV6_V6ONLY, @OptVal, SizeOf(OptVal));
```

### `Field`

SOL_SOCKET

```pascal
if Family = AF_INET then
```

### `--- STEP 1`

Preliminary JSON Scan (To get EngineID only) ---

```pascal
if FileExists(JsonFile) then
```

### `--- STEP 2`

Resolve Server Data from DB ---

```pascal
FQuery.SQL.Clear;
```

### `--- STEP 3`

Load config_data from DB (Mandatory Filter) ---

```pascal
AllowedParams := TStringList.Create;
```

### `--- STEP 4`

Apply JSON Overrides and Permission Checks ---

```pascal
if FileExists(JsonFile) then
```

### `Field`

--- FINAL VALIDATION ---

```pascal
if not(FileExists(FServerBinary)) then raise Exception.Create('Server binary missing: ' + FServerBinary);
```

### `Application entry point`

Creates and runs the TServiceWrapper application.

```pascal
var Application: TServiceWrapper;
```

---

## Constants

### `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`

Job object limit flag that kills processes when job closes.

```pascal
JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = $00002000;
```

### `INSTANCE_PREFIX`

Windows mutex name prefix for single instance management.

```pascal
INSTANCE_PREFIX = 'Global\llama_service_wrapper_';
```

### `INSTANCE_PREFIX`

Unix lock file path prefix for single instance management.

```pascal
const INSTANCE_PREFIX = '/tmp/llama_service_wrapper_';
```

---

**Copyright © 2026 Robert Abraham. All rights reserved.**
