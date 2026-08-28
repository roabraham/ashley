# Service Wrapper Documentation

**Overview:** Llama Service Wrapper - A cross-platform service manager for LLM server processes, web servers, PHP FastCGI, and API proxy.

---

## Table of Contents
- [Classes and Types](#classes-and-types)
- [Methods and Functions](#methods-and-functions)
- [Fields and Properties](#fields-and-properties)
- [Constants](#constants)

---

## Classes and Types

### `JOBOBJECT_BASIC_LIMIT_INFORMATION (MSWINDOWS)`
Windows Job Object limit information structure for process job management.

```pascal
JOBOBJECT_BASIC_LIMIT_INFORMATION = record
```

### `IO_COUNTERS (MSWINDOWS)`
Windows I/O performance counters structure.

```pascal
IO_COUNTERS = record
```

### `JOBOBJECT_EXTENDED_LIMIT_INFORMATION (MSWINDOWS)`
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

## Methods and Functions

### `CreateJobObjectW (MSWINDOWS)`
Creates or opens a job object in Windows.

```pascal
function CreateJobObjectW(lpJobAttributes: Pointer; lpName: PWideChar): THandle; stdcall; external 'kernel32.dll';
```

### `SetInformationJobObject (MSWINDOWS)`
Sets information for a job object in Windows.

```pascal
function SetInformationJobObject(hJob: THandle; JobObjectInfoClass: Integer; lpJobObjectInfo: Pointer; cbJobObjectInfoLength: DWORD): BOOL; stdcall; external 'kernel32.dll';
```

### `AssignProcessToJobObject (MSWINDOWS)`
Assigns a process to an existing job object in Windows.

```pascal
function AssignProcessToJobObject(hJob: THandle; hProcess: THandle): BOOL; stdcall; external 'kernel32.dll';
```

### `TListenerThread.Execute`
Main thread execution - blocks waiting for incoming connections.

```pascal
procedure Execute; override;
```

### `TListenerThread.Create`
Initializes the listener thread with the given server instance.

```pascal
constructor Create(AServer: TInetServer);
```

### `TWorkerThread.InternalReadLine`
Reads a line from the socket stream with timeout support.

```pascal
function InternalReadLine(Stream: TSocketStream): AnsiString;
```

### `TWorkerThread.GetContentLength`
Extracts the Content-Length value from HTTP headers.

```pascal
function GetContentLength(const Headers: AnsiString): Integer;
```

### `TWorkerThread.SendHttpError`
Sends an HTTP error response to the client.

```pascal
procedure SendHttpError(Stream: TSocketStream; Code: Integer; Msg: AnsiString);
```

### `TWorkerThread.Execute`
Main thread execution - handles the request/response cycle.

```pascal
procedure Execute; override;
```

### `TWorkerThread.Create`
Initializes the worker thread with connection and routing parameters.

```pascal
constructor Create(AHandle: TSocket; ATargetPort, ATargetEmbeddingPort: Integer; AEndpoint, AEmbeddingEndpoint: string; ATimeout, AmaxPackageSize: Integer);
```

### `TProxyThread.CleanupFinishedWorkers`
Removes and frees finished worker threads from the list.

```pascal
procedure CleanupFinishedWorkers;
```

### `TProxyThread.EnforceTimeouts`
Terminates workers that have exceeded the timeout limit.

```pascal
procedure EnforceTimeouts;
```

### `TProxyThread.Execute`
Main thread execution - manages listener and worker lifecycle.

```pascal
procedure Execute; override;
```

### `TProxyThread.Create`
Initializes the proxy thread with routing and connection parameters.

```pascal
constructor Create(AProxyHost: String; APort, ATargetPort, ATargetEmbeddingPort: Integer; AEndpoint, AEmbeddingEndpoint: String; ATimeout, AMax, Apmax: Integer);
```

### `TProxyThread.Destroy`
Frees the proxy thread and cleans up resources.

```pascal
destructor Destroy; override;
```

### `TServiceWrapper.CheckSingleInstance`
Verifies no other instance is running, returns False if already running.

```pascal
function CheckSingleInstance: Boolean;
```

### `TServiceWrapper.IsPortFree`
Checks if a TCP port is available for binding.

```pascal
function IsPortFree(APort: Integer): Boolean;
```

### `TServiceWrapper.ExecAndCapture`
Executes an external command and captures output.

```pascal
function ExecAndCapture(const command: AnsiString; const parameters: TStringList): Integer;
```

### `TServiceWrapper.CheckCertificateExpiration`
Checks if SSL certificate is expired or within renewal window.

```pascal
function CheckCertificateExpiration(const CertFile: AnsiString; ExpirationDays: Integer): Boolean;
```

### `TServiceWrapper.InitPaths`
Initializes all path variables based on executable location.

```pascal
procedure InitPaths;
```

### `TServiceWrapper.SetupDatabase`
Opens connection to the SQLite configuration database.

```pascal
procedure SetupDatabase;
```

### `TServiceWrapper.LoadConfiguration`
Loads server and proxy configuration from database and JSON file.

```pascal
procedure LoadConfiguration;
```

### `TServiceWrapper.GenerateSslCertificate`
Generates a self-signed SSL certificate using OpenSSL.

```pascal
procedure GenerateSslCertificate(const CertFile, KeyFile: AnsiString);
```

### `TServiceWrapper.GenerateSslCertificateIfNeeded`
Generates SSL certificate if missing or expiring soon.

```pascal
procedure GenerateSslCertificateIfNeeded;
```

### `TServiceWrapper.WaitUntilPortFree`
Blocks until the specified port becomes available.

```pascal
procedure WaitUntilPortFree(APort: Integer);
```

### `TServiceWrapper.StartProxy`
Starts the API proxy service on the given port.

```pascal
procedure StartProxy(AProxyPort, ATargetPort, ATargetEmbeddingPort: Integer);
```

### `TServiceWrapper.StopProxy`
Stops the API proxy service.

```pascal
procedure StopProxy;
```

### `TServiceWrapper.RunWatchdog`
Main watchdog loop that monitors and restarts failed processes.

```pascal
procedure RunWatchdog;
```

### `TServiceWrapper.Cleanup`
Releases all resources and terminates child processes.

```pascal
procedure Cleanup;
```

### `TServiceWrapper.ShowHelp`
Displays command-line help and usage information.

```pascal
procedure ShowHelp;
```

### `TServiceWrapper.DoRun`
Main application entry point for the service wrapper.

```pascal
procedure DoRun; override;
```

### `TServiceWrapper.Create`
Initializes the service wrapper application.

```pascal
constructor Create(TheOwner: TComponent); override;
```

### `TServiceWrapper.Destroy`
Frees the service wrapper and all associated resources.

```pascal
destructor Destroy; override;
```

### `TServiceWrapper.HandleGlobalException`
Global exception handler that logs and terminates on fatal errors.

```pascal
procedure HandleGlobalException(Sender: TObject; E: Exception);
```

### `Helper`
Try to bing port without blocking.

```pascal
function TryBind(Family: SmallInt): Boolean;
```

### `DoSigInt (UNIX)`
Signal handler for SIGINT/SIGTERM signals on Unix platforms.

```pascal
procedure DoSigInt(Sig: LongInt); cdecl;
```

---

## Fields and Properties

### `TListenerThread.FServer`
The TCP server socket that listens for incoming connections.

```pascal
FServer: TInetServer;
```

### `TListenerThread.FNewSocket`
Socket handle for the newly accepted connection.

```pascal
FNewSocket: TSocket;
```

### `TListenerThread.NewSocket`
Property to access the accepted client socket handle.

```pascal
property NewSocket: TSocket read FNewSocket;
```

### `TWorkerThread.FTargetPort`
The target port for the conversational LLM server.

```pascal
FTargetPort: Integer;
```

### `TWorkerThread.FTargetEmbeddingPort`
The target port for the embedding LLM server.

```pascal
FTargetEmbeddingPort: Integer;
```

### `TWorkerThread.FTargetEndpoint`
The endpoint path for the conversational LLM server.

```pascal
FTargetEndpoint: string;
```

### `TWorkerThread.FTargetEmbeddingEndpoint`
The endpoint path for the embedding LLM server.

```pascal
FTargetEmbeddingEndpoint: string;
```

### `TWorkerThread.FProxyTimeout`
Maximum time in seconds before the connection times out.

```pascal
FProxyTimeout: Integer;
```

### `TWorkerThread.FMaxPackageSize`
Maximum allowed request/response size in bytes.

```pascal
FMaxPackageSize: Integer;
```

### `TWorkerThread.FClientHandle`
Socket handle for the client connection.

```pascal
FClientHandle: TSocket;
```

### `TWorkerThread.FLlamaSocket`
Socket handle for the LLM server connection.

```pascal
FLlamaSocket: TSocket;
```

### `TWorkerThread.FStartTime`
Timestamp when the worker started processing the request.

```pascal
FStartTime: TDateTime;
```

### `TWorkerThread.StartTime`
Property to access the worker start timestamp.

```pascal
property StartTime: TDateTime read FStartTime;
```

### `TProxyThread.FProxyHost`
Host address on which the proxy listens for incoming connections.

```pascal
FProxyHost: String;
```

### `TProxyThread.FProxyPort`
The port on which the proxy listens for incoming connections.

```pascal
FProxyPort: Integer;
```

### `TProxyThread.FTargetPort`
The target port for the conversational LLM server.

```pascal
FTargetPort: Integer;
```

### `TProxyThread.FTargetEmbeddingPort`
The target port for the embedding LLM server.

```pascal
FTargetEmbeddingPort: Integer;
```

### `TProxyThread.FTargetEndpoint`
The endpoint path for the conversational LLM server.

```pascal
FTargetEndpoint: String;
```

### `TProxyThread.FTargetEmbeddingEndpoint`
The endpoint path for the embedding LLM server.

```pascal
FTargetEmbeddingEndpoint: String;
```

### `TProxyThread.FProxyTimeout`
Maximum time in seconds before a worker times out.

```pascal
FProxyTimeout: Integer;
```

### `TProxyThread.FProxyMaxConnections`
Maximum number of concurrent worker connections.

```pascal
FProxyMaxConnections: Integer;
```

### `TProxyThread.FMaxPackageSize`
Maximum allowed request/response size in bytes.

```pascal
FMaxPackageSize: Integer;
```

### `TProxyThread.FServerSocket`
The TCP server socket for accepting connections.

```pascal
FServerSocket: TInetServer;
```

### `TProxyThread.FWorkers`
List of active worker threads.

```pascal
FWorkers: TFPList;
```

### `TServiceWrapper.FInstanceID`
Unique identifier for the service instance (MD5 hash of executable path).

```pascal
FInstanceID: string;
```

### `TServiceWrapper.FConn`
SQLite database connection.

```pascal
FConn: TSQLite3Connection;
```

### `TServiceWrapper.FTrans`
Database transaction object.

```pascal
FTrans: TSQLTransaction;
```

### `TServiceWrapper.FQuery`
SQL query object for configuration loading.

```pascal
FQuery: TSQLQuery;
```

### `TServiceWrapper.FProcess`
Process object for the conversational LLM server.

```pascal
FProcess: TProcess;
```

### `TServiceWrapper.FEmbeddingProcess`
Process object for the embedding LLM server.

```pascal
FEmbeddingProcess: TProcess;
```

### `TServiceWrapper.FPhpProcess`
Process object for PHP FastCGI server.

```pascal
FPhpProcess: TProcess;
```

### `TServiceWrapper.FWebserverProcess`
Process object for Nginx web server.

```pascal
FWebserverProcess: TProcess;
```

### `TServiceWrapper.FAppDir`
Directory path of the application executable.

```pascal
FAppDir: AnsiString;
```

### `TServiceWrapper.FConfigDir`
Configuration directory path.

```pascal
FConfigDir: AnsiString;
```

### `TServiceWrapper.FModelDir`
Model files directory path.

```pascal
FModelDir: AnsiString;
```

### `TServiceWrapper.FEmbeddingModelDir`
Embedding model files directory path.

```pascal
FEmbeddingModelDir: AnsiString;
```

### `TServiceWrapper.FLlamaDir`
LLM server binaries directory path.

```pascal
FLlamaDir: AnsiString;
```

### `TServiceWrapper.FServerBinary`
Full path to the LLM server executable.

```pascal
FServerBinary: AnsiString;
```

### `TServiceWrapper.FDeviceID`
Device identifier for GPU/CPU selection.

```pascal
FDeviceID: string;
```

### `TServiceWrapper.FEndpoint`
Conversational LLM endpoint path.

```pascal
FEndpoint: string;
```

### `TServiceWrapper.FEmbeddingEndpoint`
Embedding LLM endpoint path.

```pascal
FEmbeddingEndpoint: string;
```

### `TServiceWrapper.FinalFModelFile`
Resolved full path to the conversational model file.

```pascal
FinalFModelFile: AnsiString;
```

### `TServiceWrapper.FinalFEmbeddingModelFile`
Resolved full path to the embedding model file.

```pascal
FinalFEmbeddingModelFile: AnsiString;
```

### `TServiceWrapper.FParams`
Command-line parameters for the conversational LLM server.

```pascal
FParams: TStringList;
```

### `TServiceWrapper.FEmbeddingParams`
Command-line parameters for the embedding LLM server.

```pascal
FEmbeddingParams: TStringList;
```

### `TServiceWrapper.FLLMenabled`
Flag indicating whether LLM service is enabled.

```pascal
FLLMenabled: Boolean;
```

### `TServiceWrapper.FEmbeddingEnabled`
Flag indicating whether embedding service is enabled.

```pascal
FEmbeddingEnabled: Boolean;
```

### `TServiceWrapper.FUseLogFile`
Flag indicating whether to log to file.

```pascal
FUseLogFile: boolean;
```

### `TServiceWrapper.FProxyHost`
Host address for the API proxy service to listen on.

```pascal
FProxyHost: String;
```

### `TServiceWrapper.FProxyPort`
Port for the API proxy service.

```pascal
FProxyPort: integer;
```

### `TServiceWrapper.FProxyTimeout`
Timeout in seconds for proxy connections.

```pascal
FProxyTimeout: integer;
```

### `TServiceWrapper.FProxyMaxConnections`
Maximum concurrent connections for the proxy.

```pascal
FProxyMaxConnections: integer;
```

### `TServiceWrapper.FMaxPackageSize`
Maximum request/response package size in bytes.

```pascal
FMaxPackageSize: integer;
```

### `TServiceWrapper.FProxyThread`
The proxy manager thread instance.

```pascal
FProxyThread: TProxyThread;
```

### `TServiceWrapper.FPhpPort`
Port for PHP FastCGI service.

```pascal
FPhpPort: Integer;
```

### `TServiceWrapper.FWebserverHttpPort`
HTTP port for the web server.

```pascal
FWebserverHttpPort: Integer;
```

### `TServiceWrapper.FWebserverHttpsPort`
HTTPS port for the web server.

```pascal
FWebserverHttpsPort: Integer;
```

### `TServiceWrapper.FOpensslBinary`
Full path to OpenSSL executable.

```pascal
FOpensslBinary: AnsiString;
```

### `TServiceWrapper.FWebserverBinary`
Full path to Nginx web server executable.

```pascal
FWebserverBinary: AnsiString;
```

### `TServiceWrapper.FPhpBinary`
Full path to PHP-CGI executable.

```pascal
FPhpBinary: AnsiString;
```

### `TServiceWrapper.FPhpHost`
Host address for PHP FastCGI binding.

```pascal
FPhpHost: AnsiString;
```

### `TServiceWrapper.FSSLcertDir`
Directory containing SSL certificates.

```pascal
FSSLcertDir: AnsiString;
```

### `TServiceWrapper.FSSLcertificate`
Full path to SSL certificate file.

```pascal
FSSLcertificate: AnsiString;
```

### `TServiceWrapper.FSSLkey`
Full path to SSL key file.

```pascal
FSSLkey: AnsiString;
```

### `TServiceWrapper.FSSLexpiration`
SSL certificate validity period in days.

```pascal
FSSLexpiration: Integer;
```

### `TServiceWrapper.FSSGeneration`
Days before expiration to renew SSL certificate.

```pascal
FSSGeneration: Integer;
```

### `TServiceWrapper.FSSLencryption`
SSL key encryption algorithm.

```pascal
FSSLencryption: AnsiString;
```

### `TServiceWrapper.DBPath`
Full path to the SQLite database file.

```pascal
DBPath: AnsiString;
```

### `TServiceWrapper.DBPathWAL`
Full path to the database WAL file.

```pascal
DBPathWAL: AnsiString;
```

### `TServiceWrapper.DBPathSHM`
Full path to the database SHM file.

```pascal
DBPathSHM: AnsiString;
```

### `TServiceWrapper.IsCertOnlyMode`
Flag indicating whether only SSL certificate generation is requested.

```pascal
IsCertOnlyMode: Boolean;
```

### `TServiceWrapper.FJob (MSWINDOWS)`
Windows job object handle for process group management.

```pascal
FJob: THandle;
```

### `TServiceWrapper.FMutex (MSWINDOWS)`
Windows mutex handle for single instance check.

```pascal
FMutex: THandle;
```

### `TServiceWrapper.FLockFileHandle (UNIX)`
Unix file handle for lock file based single instance check.

```pascal
FLockFileHandle: Integer;
```

---

## Constants

### `LLM_TIMEOUT_THRESHOLD`
Seconds before proxy timeout to trigger early partial response.

```pascal
LLM_TIMEOUT_THRESHOLD = 3;
```

### `MIN_LLM_TIMEOUT_FOR_THRESHOLD`
Minimum proxy timeout in seconds to enable early timeout behavior.

```pascal
MIN_LLM_TIMEOUT_FOR_THRESHOLD = 10;
```

### `LLM_TIMEOUT_WARNING`
Suffix appended to incomplete conversational responses on timeout.

```pascal
LLM_TIMEOUT_WARNING = 'LLM TIMEOUT REACHED';
```

### `JobObjectExtendedLimitInformation (MSWINDOWS)`
Windows Job Object information class constant.

```pascal
JobObjectExtendedLimitInformation = 9;
```

### `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE (MSWINDOWS)`
Job object limit flag that kills processes when job closes.

```pascal
JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = $00002000;
```

### `INSTANCE_PREFIX (MSWINDOWS)`
Windows mutex name prefix for single instance management.

```pascal
INSTANCE_PREFIX = 'Global\llama_service_wrapper_';
```

### `INSTANCE_PREFIX (UNIX)`
Unix lock file path prefix for single instance management.

```pascal
const INSTANCE_PREFIX = '/tmp/llama_service_wrapper_';
```

---

**Copyright © 2026 Robert Abraham. All rights reserved.**
