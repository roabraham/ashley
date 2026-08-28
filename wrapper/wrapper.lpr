{ Llama Service Wrapper - A cross-platform service manager for LLM server processes, web servers, PHP FastCGI, and API proxy. }
program wrapper;

{$mode objfpc}{$H+}

uses
  {$IFDEF MSWINDOWS}
  Windows, WinSock2,
  {$ENDIF}
  {$IFDEF UNIX}
  cthreads, BaseUnix, Unix,
  {$ENDIF}
  Classes, SysUtils, CustApp, SQLDB, SQLite3Conn, fpjson, jsonparser, Process, StrUtils, md5, sockets, ssockets;

const
  { LLM_TIMEOUT_THRESHOLD: Seconds before proxy timeout to trigger early partial response. }
  LLM_TIMEOUT_THRESHOLD = 3;
  { MIN_LLM_TIMEOUT_FOR_THRESHOLD: Minimum proxy timeout in seconds to enable early timeout behavior. }
  MIN_LLM_TIMEOUT_FOR_THRESHOLD = 10;
  { LLM_TIMEOUT_WARNING: Suffix appended to incomplete conversational responses on timeout. }
  LLM_TIMEOUT_WARNING = 'LLM TIMEOUT REACHED';

{$IFDEF MSWINDOWS}
type
  { JOBOBJECT_BASIC_LIMIT_INFORMATION: Windows Job Object limit information structure for process job management. }
  JOBOBJECT_BASIC_LIMIT_INFORMATION = record
    PerProcessUserTimeLimit: Int64;
    PerJobUserTimeLimit: Int64;
    LimitFlags: DWORD;
    MinimumWorkingSetSize: UIntPtr;
    MaximumWorkingSetSize: UIntPtr;
    ActiveProcessLimit: DWORD;
    Affinity: UIntPtr;
    PriorityClass: DWORD;
    SchedulingClass: DWORD;
  end;

  { IO_COUNTERS: Windows I/O performance counters structure. }
  IO_COUNTERS = record
    ReadOperationCount: UInt64;
    WriteOperationCount: UInt64;
    OtherOperationCount: UInt64;
    ReadTransferCount: UInt64;
    WriteTransferCount: UInt64;
    OtherTransferCount: UInt64;
  end;

  { JOBOBJECT_EXTENDED_LIMIT_INFORMATION: Extended Windows Job Object information structure with memory limits. }
  JOBOBJECT_EXTENDED_LIMIT_INFORMATION = record
    BasicLimitInformation: JOBOBJECT_BASIC_LIMIT_INFORMATION;
    IoInfo: IO_COUNTERS;
    ProcessMemoryLimit: UIntPtr;
    JobMemoryLimit: UIntPtr;
    PeakProcessMemoryUsed: UIntPtr;
    PeakJobMemoryUsed: UIntPtr;
  end;

const
  { JobObjectExtendedLimitInformation: Windows Job Object information class constant. }
  JobObjectExtendedLimitInformation = 9;
  { JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE: Job object limit flag that kills processes when job closes. }
  JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = $00002000;
  { INSTANCE_PREFIX: Windows mutex name prefix for single instance management. }
  INSTANCE_PREFIX = 'Global\llama_service_wrapper_';

{ CreateJobObjectW: Creates or opens a job object in Windows. }
function CreateJobObjectW(lpJobAttributes: Pointer; lpName: PWideChar): THandle; stdcall; external 'kernel32.dll';
{ SetInformationJobObject: Sets information for a job object in Windows. }
function SetInformationJobObject(hJob: THandle; JobObjectInfoClass: Integer; lpJobObjectInfo: Pointer; cbJobObjectInfoLength: DWORD): BOOL; stdcall; external 'kernel32.dll';
{ AssignProcessToJobObject: Assigns a process to an existing job object in Windows. }
function AssignProcessToJobObject(hJob: THandle; hProcess: THandle): BOOL; stdcall; external 'kernel32.dll';
{$ENDIF}
{$IFDEF UNIX}
{ INSTANCE_PREFIX: Unix lock file path prefix for single instance management. }
const INSTANCE_PREFIX = '/tmp/llama_service_wrapper_';
{$ENDIF}

type

  { EWatchdogFatal: Exception raised when a fatal error occurs in the watchdog thread, causing termination. }
  EWatchdogFatal = class(Exception);

  { TListenerThread: Background thread that listens for incoming network connections without blocking the manager thread. }
  TListenerThread = class(TThread)
  protected
    { FServer: The TCP server socket that listens for incoming connections. }
    FServer: TInetServer;
    { FNewSocket: Socket handle for the newly accepted connection. }
    FNewSocket: TSocket;
    { Execute: Main thread execution - blocks waiting for incoming connections. }
    procedure Execute; override;
  public
    { Create: Initializes the listener thread with the given server instance. }
    constructor Create(AServer: TInetServer);
    { NewSocket: Property to access the accepted client socket handle. }
    property NewSocket: TSocket read FNewSocket;
  end;

  { TWorkerThread: Background thread that handles a single isolated client request by proxying to LLM server. }
  TWorkerThread = class(TThread)
  protected
    { FTargetPort: The target port for the conversational LLM server. }
    FTargetPort: Integer;
    { FTargetEmbeddingPort: The target port for the embedding LLM server. }
    FTargetEmbeddingPort: Integer;
    { FTargetEndpoint: The endpoint path for the conversational LLM server. }
    FTargetEndpoint: string;
    { FTargetEmbeddingEndpoint: The endpoint path for the embedding LLM server. }
    FTargetEmbeddingEndpoint: string;
    { FProxyTimeout: Maximum time in seconds before the connection times out. }
    FProxyTimeout: Integer;
    { FMaxPackageSize: Maximum allowed request/response size in bytes. }
    FMaxPackageSize: Integer;
    { InternalReadLine: Reads a line from the socket stream with timeout support. }
    function InternalReadLine(Stream: TSocketStream): AnsiString;
    { GetContentLength: Extracts the Content-Length value from HTTP headers. }
    function GetContentLength(const Headers: AnsiString): Integer;
    { SendHttpError: Sends an HTTP error response to the client. }
    procedure SendHttpError(Stream: TSocketStream; Code: Integer; Msg: AnsiString);
    { Execute: Main thread execution - handles the request/response cycle. }
    procedure Execute; override;
  public
    { FClientHandle: Socket handle for the client connection. }
    FClientHandle: TSocket;
    { FLlamaSocket: Socket handle for the LLM server connection. }
    FLlamaSocket: TSocket;
    { FStartTime: Timestamp when the worker started processing the request. }
    FStartTime: TDateTime;
    { Create: Initializes the worker thread with connection and routing parameters. }
    constructor Create(AHandle: TSocket; ATargetPort, ATargetEmbeddingPort: Integer; AEndpoint, AEmbeddingEndpoint: string; ATimeout, AmaxPackageSize: Integer);
    { StartTime: Property to access the worker start timestamp. }
    property StartTime: TDateTime read FStartTime;
  end;

  { TProxyThread: Manager thread that listens for connections and monitors worker threads. }
  TProxyThread = class(TThread)
  protected
    { FProxyHost: Host address on which the proxy listens for incoming connections. }
    FProxyHost: String;
    { FProxyPort: The port on which the proxy listens for incoming connections. }
    FProxyPort: Integer;
    { FTargetPort: The target port for the conversational LLM server. }
    FTargetPort: Integer;
    { FTargetEmbeddingPort: The target port for the embedding LLM server. }
    FTargetEmbeddingPort: Integer;
    { FTargetEndpoint: The endpoint path for the conversational LLM server. }
    FTargetEndpoint: String;
    { FTargetEmbeddingEndpoint: The endpoint path for the embedding LLM server. }
    FTargetEmbeddingEndpoint: String;
    { FProxyTimeout: Maximum time in seconds before a worker times out. }
    FProxyTimeout: Integer;
    { FProxyMaxConnections: Maximum number of concurrent worker connections. }
    FProxyMaxConnections: Integer;
    { FMaxPackageSize: Maximum allowed request/response size in bytes. }
    FMaxPackageSize: Integer;
    { FServerSocket: The TCP server socket for accepting connections. }
    FServerSocket: TInetServer;
    { FWorkers: List of active worker threads. }
    FWorkers: TFPList;
    { CleanupFinishedWorkers: Removes and frees finished worker threads from the list. }
    procedure CleanupFinishedWorkers;
    { EnforceTimeouts: Terminates workers that have exceeded the timeout limit. }
    procedure EnforceTimeouts;
    { Execute: Main thread execution - manages listener and worker lifecycle. }
    procedure Execute; override;
  public
    { Create: Initializes the proxy thread with routing and connection parameters. }
    constructor Create(AProxyHost: String; APort, ATargetPort, ATargetEmbeddingPort: Integer; AEndpoint, AEmbeddingEndpoint: String; ATimeout, AMax, Apmax: Integer);
    { Destroy: Frees the proxy thread and cleans up resources. }
    destructor Destroy; override;
  end;

  { TServiceWrapper: Main application class that manages LLM server processes, web servers, PHP FastCGI, and API proxy. }
  TServiceWrapper = class(TCustomApplication)
  protected
    { FInstanceID: Unique identifier for the service instance (MD5 hash of executable path). }
    FInstanceID: string;
    { FConn: SQLite database connection. }
    FConn: TSQLite3Connection;
    { FTrans: Database transaction object. }
    FTrans: TSQLTransaction;
    { FQuery: SQL query object for configuration loading. }
    FQuery: TSQLQuery;
    { FProcess: Process object for the conversational LLM server. }
    FProcess: TProcess;
    { FEmbeddingProcess: Process object for the embedding LLM server. }
    FEmbeddingProcess: TProcess;
    { FPhpProcess: Process object for PHP FastCGI server. }
    FPhpProcess: TProcess;
    { FWebserverProcess: Process object for Nginx web server. }
    FWebserverProcess: TProcess;
    { FAppDir: Directory path of the application executable. }
    FAppDir: AnsiString;
    { FConfigDir: Configuration directory path. }
    FConfigDir: AnsiString;
    { FModelDir: Model files directory path. }
    FModelDir: AnsiString;
    { FEmbeddingModelDir: Embedding model files directory path. }
    FEmbeddingModelDir: AnsiString;
    { FLlamaDir: LLM server binaries directory path. }
    FLlamaDir: AnsiString;
    { FServerBinary: Full path to the LLM server executable. }
    FServerBinary: AnsiString;
    { FDeviceID: Device identifier for GPU/CPU selection. }
    FDeviceID: string;
    { FEndpoint: Conversational LLM endpoint path. }
    FEndpoint: string;
    { FEmbeddingEndpoint: Embedding LLM endpoint path. }
    FEmbeddingEndpoint: string;
    { FinalFModelFile: Resolved full path to the conversational model file. }
    FinalFModelFile: AnsiString;
    { FinalFEmbeddingModelFile: Resolved full path to the embedding model file. }
    FinalFEmbeddingModelFile: AnsiString;
    { FParams: Command-line parameters for the conversational LLM server. }
    FParams: TStringList;
    { FEmbeddingParams: Command-line parameters for the embedding LLM server. }
    FEmbeddingParams: TStringList;
    { FLLMenabled: Flag indicating whether LLM service is enabled. }
    FLLMenabled: Boolean;
    { FEmbeddingEnabled: Flag indicating whether embedding service is enabled. }
    FEmbeddingEnabled: Boolean;
    { FUseLogFile: Flag indicating whether to log to file. }
    FUseLogFile: boolean;
    { FProxyHost: Host address for the API proxy service to listen on. }
    FProxyHost: String;
    { FProxyPort: Port for the API proxy service. }
    FProxyPort: integer;
    { FProxyTimeout: Timeout in seconds for proxy connections. }
    FProxyTimeout: integer;
    { FProxyMaxConnections: Maximum concurrent connections for the proxy. }
    FProxyMaxConnections: integer;
    { FMaxPackageSize: Maximum request/response package size in bytes. }
    FMaxPackageSize: integer;
    { FProxyThread: The proxy manager thread instance. }
    FProxyThread: TProxyThread;
    { FPhpPort: Port for PHP FastCGI service. }
    FPhpPort: Integer;
    { FWebserverHttpPort: HTTP port for the web server. }
    FWebserverHttpPort: Integer;
    { FWebserverHttpsPort: HTTPS port for the web server. }
    FWebserverHttpsPort: Integer;
    { FOpensslBinary: Full path to OpenSSL executable. }
    FOpensslBinary: AnsiString;
    { FWebserverBinary: Full path to Nginx web server executable. }
    FWebserverBinary: AnsiString;
    { FPhpBinary: Full path to PHP-CGI executable. }
    FPhpBinary: AnsiString;
    { FPhpHost: Host address for PHP FastCGI binding. }
    FPhpHost: AnsiString;
    { FSSLcertDir: Directory containing SSL certificates. }
    FSSLcertDir: AnsiString;
    { FSSLcertificate: Full path to SSL certificate file. }
    FSSLcertificate: AnsiString;
    { FSSLkey: Full path to SSL key file. }
    FSSLkey: AnsiString;
    { FSSLexpiration: SSL certificate validity period in days. }
    FSSLexpiration: Integer;
    { FSSGeneration: Days before expiration to renew SSL certificate. }
    FSSGeneration: Integer;
    { FSSLencryption: SSL key encryption algorithm. }
    FSSLencryption: AnsiString;
    { DBPath: Full path to the SQLite database file. }
    DBPath: AnsiString;
    { DBPathWAL: Full path to the database WAL file. }
    DBPathWAL: AnsiString;
    { DBPathSHM: Full path to the database SHM file. }
    DBPathSHM: AnsiString;
    { IsCertOnlyMode: Flag indicating whether only SSL certificate generation is requested. }
    IsCertOnlyMode: Boolean;
    {$IFDEF MSWINDOWS}
    { FJob: Windows job object handle for process group management. }
    FJob: THandle;
    { FMutex: Windows mutex handle for single instance check. }
    FMutex: THandle;
    {$ENDIF}
    {$IFDEF UNIX}
    { FLockFileHandle: Unix file handle for lock file based single instance check. }
    FLockFileHandle: Integer;
    {$ENDIF}
    { CheckSingleInstance: Verifies no other instance is running, returns False if already running. }
    function CheckSingleInstance: Boolean;
    { IsPortFree: Checks if a TCP port is available for binding. }
    function IsPortFree(APort: Integer): Boolean;
    { ExecAndCapture: Executes an external command and captures output. }
    function ExecAndCapture(const command: AnsiString; const parameters: TStringList): Integer;
    { CheckCertificateExpiration: Checks if SSL certificate is expired or within renewal window. }
    function CheckCertificateExpiration(const CertFile: AnsiString; ExpirationDays: Integer): Boolean;
    { InitPaths: Initializes all path variables based on executable location. }
    procedure InitPaths;
    { SetupDatabase: Opens connection to the SQLite configuration database. }
    procedure SetupDatabase;
    { LoadConfiguration: Loads server and proxy configuration from database and JSON file. }
    procedure LoadConfiguration;
    { GenerateSslCertificate: Generates a self-signed SSL certificate using OpenSSL. }
    procedure GenerateSslCertificate(const CertFile, KeyFile: AnsiString);
    { GenerateSslCertificateIfNeeded: Generates SSL certificate if missing or expiring soon. }
    procedure GenerateSslCertificateIfNeeded;
    { WaitUntilPortFree: Blocks until the specified port becomes available. }
    procedure WaitUntilPortFree(APort: Integer);
    { StartProxy: Starts the API proxy service on the given port. }
    procedure StartProxy(AProxyPort, ATargetPort, ATargetEmbeddingPort: Integer);
    { StopProxy: Stops the API proxy service. }
    procedure StopProxy;
    { RunWatchdog: Main watchdog loop that monitors and restarts failed processes. }
    procedure RunWatchdog;
    { Cleanup: Releases all resources and terminates child processes. }
    procedure Cleanup;
    { ShowHelp: Displays command-line help and usage information. }
    procedure ShowHelp;
    { DoRun: Main application entry point for the service wrapper. }
    procedure DoRun; override;
  public
    { Create: Initializes the service wrapper application. }
    constructor Create(TheOwner: TComponent); override;
    { Destroy: Frees the service wrapper and all associated resources. }
    destructor Destroy; override;
    { HandleGlobalException: Global exception handler that logs and terminates on fatal errors. }
    procedure HandleGlobalException(Sender: TObject; E: Exception);
  end;

{ TListenerThread implementation. }

{ TListenerThread.Create initializes the listener thread with the given server instance. }
constructor TListenerThread.Create(AServer: TInetServer);
begin
  inherited Create(false);
  FServer := AServer;
  FNewSocket := -1;
end;

{ TListenerThread.Execute: Waits for and accepts incoming TCP connections. }
procedure TListenerThread.Execute;
begin
  // This is the ONLY place that blocks.
  // It stays here until a connection arrives.
  FNewSocket := sockets.fpAccept(FServer.Socket, nil, nil);
end;

{ TWorkerThread implementation. }

{ TWorkerThread.Create initializes the worker thread with connection and routing parameters. }
constructor TWorkerThread.Create(AHandle: TSocket; ATargetPort, ATargetEmbeddingPort: Integer; AEndpoint, AEmbeddingEndpoint: string; ATimeout, AmaxPackageSize: Integer);
begin
  inherited Create(true);
  FreeOnTerminate := false; // Manager will free it
  FClientHandle := AHandle;
  FTargetPort := ATargetPort;
  FTargetEmbeddingPort := ATargetEmbeddingPort;
  FTargetEndpoint := AEndpoint;
  FTargetEmbeddingEndpoint := AEmbeddingEndpoint;
  FProxyTimeout := ATimeout;
  FMaxPackageSize := AmaxPackageSize;
  FStartTime := Now;
end;

{ TWorkerThread.SendHttpError: Sends an HTTP error response to the client stream. }
procedure TWorkerThread.SendHttpError(Stream: TSocketStream; Code: Integer; Msg: AnsiString);
var Status, Response: AnsiString;
begin
  case Code of
    400: Status := '400 Bad Request';
    404: Status := '404 Not Found';
    405: Status := '405 Method Not Allowed';
    408: Status := '408 Request Timeout';
    503: Status := '503 Service Unavailable';
    else Status := '500 Internal Server Error';
  end;
  Response := 'HTTP/1.1 ' + Status + #13#10 + 'Content-Type: application/json' + #13#10 +
    'Connection: close' + #13#10#13#10 + '{"error": "' + Msg + '"}';
  try
    Stream.Write(Response[1], Length(Response));
  except
    // Silent skip
  end;
end;

{ TWorkerThread.InternalReadLine: Reads a line of text from the socket stream with timeout support. }
function TWorkerThread.InternalReadLine(Stream: TSocketStream): AnsiString;
var
  C: Char;
  Res: AnsiString;
  ReadRes: Integer;
  {$IFDEF MSWINDOWS}
  FDSet: TFDSet;
  TimeVal: TTimeVal;
  {$ENDIF}
begin
  C := #0;
  Res := '';
  while not(Terminated) do
  begin
    // Force global timeout
    if (Now - FStartTime) * 86400 > FProxyTimeout then
    begin
      WriteLn('[WORKER] Global timeout reached in ReadLine.');
      Break;
    end;
    if not(Stream.Handle = INVALID_HANDLE_VALUE) then
    begin
      {$IFDEF MSWINDOWS}
      FD_ZERO(FDSet);
      FD_SET(Stream.Handle, FDSet);
      TimeVal.tv_sec := 0;
      TimeVal.tv_usec := 10000; // 10ms
      if select(0, @FDSet, nil, nil, @TimeVal) <= 0 then
      begin
        if Terminated then Break;
        Continue;
      end;
      {$ENDIF}
      {$IFDEF UNIX}
      if fpSelect(Stream.Handle + 1, @Stream.Handle, nil, nil, 10) = 0 then
      begin
        if Terminated then Break;
        Continue;
      end;
      {$ENDIF}
    end;
    try
      ReadRes := Stream.Read(C, 1);
    except
      ReadRes := -1;
    end;
    if ReadRes > 0 then
    begin
      if C = #10 then Break;
      if not(C = #13) then Res := Res + C;
    end
    else
      Break;
    if Length(Res) > FMaxPackageSize then Break;
  end;
  Result := Res;
end;

{ TWorkerThread.GetContentLength: Extracts the Content-Length value from HTTP headers string. }
function TWorkerThread.GetContentLength(const Headers: AnsiString): Integer;
var
  LowerHeaders: AnsiString;
  P, PEnd: Integer;
  LenStr: AnsiString;
begin
  Result := -1;
  LowerHeaders := LowerCase(Headers);
  // Find the start of the content-length header
  P := Pos('content-length:', LowerHeaders);
  if P <= 0 then Exit;
  // Move pointer to the start of the actual value (after the colon)
  Inc(P, Length('content-length:'));
  while (P <= Length(Headers)) and (Headers[P] in [' ', #9]) do
  begin
    Inc(P);
  end;
  // Find the end of the line (CR or LF)
  PEnd := P;
  while (PEnd <= Length(Headers)) and (Headers[PEnd] in ['0'..'9']) do
  begin
    Inc(PEnd);
  end;
  // Extract and trim the numeric string
  if PEnd > P then
  begin
    LenStr := trim(Copy(Headers, P, PEnd - P));
    Result := StrToIntDef(LenStr, -1);
  end;
end;

{ TWorkerThread.Execute: Main thread method that handles the complete request/response cycle by proxying to LLM server. }
procedure TWorkerThread.Execute;
var
  ClientConn: TSocketStream;
  LlamaStream: TInetSocket;
  Buffer: array[0..8191] of Byte;
  RequestHeader, ReceivedEndpoint, RequestBody, Line, FullContent: AnsiString;
  BytesRead, ContentLength, i: Integer;
  LastObject, TempObj: TJSONObject;
  DataNode, ContentNode, ValidationNode: TJSONData;
  ChunkStartTime: TDateTime;
  ElapsedSeconds, CurrentChunkTimeout: Double;
  TimeoutWarning, TimeoutReached: Boolean;
  CleanReceived, FinalEndpoint: AnsiString;
  FinalTargetPort: Integer;
begin
  FLlamaSocket := -1;
  TimeoutWarning := False;
  TimeoutReached := False;
  if FClientHandle = -1 then Exit; //If handle is dead, exit
  FillChar(Buffer, SizeOf(Buffer), 0);
  RequestBody := '';
  ClientConn := TSocketStream.Create(FClientHandle);
  try
    try
      ClientConn.IOTimeout := 5000; //5 seconds timeout for creating connections
      RequestHeader := '';
      // 1. Read Headers
      while not(Terminated) and (Length(RequestHeader) < 8192) do
      begin
        // Force global timeout
        if (Now - FStartTime) * 86400 > FProxyTimeout then
        begin
          WriteLn('[WORKER] Global timeout reached during header read.');
          Exit;
        end;
        try
          BytesRead := ClientConn.Read(Buffer[0], 1);
        except
          BytesRead := -1;
        end;
        if BytesRead <= 0 then Break;
        RequestHeader := RequestHeader + Char(Buffer[0]);
        if Pos(#13#10#13#10, RequestHeader) > 0 then Break;
      end;
      if Terminated then Exit;
      // Validate request
      if length(RequestHeader) > FMaxPackageSize then
      begin
        SendHttpError(ClientConn, 400, 'Max package size (' + IntToStr(FMaxPackageSize) + ' bytes) exceeded! Received ' + IntToStr(length(RequestHeader)) + ' bytes!');
        fpshutdown(FClientHandle, 2);
        Exit;
      end;
      // Extract the first word (the HTTP Method) from the first line
      Line := RequestHeader;
      i := Pos(#13#10, Line);
      if i > 0 then
        SetLength(Line, i - 1); // Narrow down to the request line
      // Grab the first word. Delimiters are space and tab.
      if not(uppercase(ExtractWord(1, Line, [' ', #9])) = 'POST') then
      begin
        SendHttpError(ClientConn, 405, 'Method Not Allowed. Only POST is supported.');
        fpshutdown(FClientHandle, 2);
        Exit;
      end;
      if (Pos(#13#10#13#10, RequestHeader) = 0) and (Pos(#10#10, RequestHeader) = 0) then
      begin
        SendHttpError(ClientConn, 400, 'Malformed Request: Incomplete Headers');
        fpshutdown(FClientHandle, 2);
        Exit;
      end;
      ContentLength := GetContentLength(RequestHeader);
      if ContentLength <= 0 then
      begin
        SendHttpError(ClientConn, 400, 'Missing Content-Length or empty content');
        fpshutdown(FClientHandle, 2);
        Exit;
      end;
      SetLength(RequestBody, ContentLength);
      i := 1;
      while (i <= ContentLength) and not(Terminated) do
      begin
        // Force global timeout
        if (Now - FStartTime) * 86400 > FProxyTimeout then
        begin
          WriteLn('[WORKER] Global timeout reached during body read.');
          Exit;
        end;
        try
          BytesRead := ClientConn.Read(RequestBody[i], ContentLength - i + 1);
        except
          BytesRead := -1;
        end;
        if BytesRead <= 0 then break;
        Inc(i, BytesRead);
      end;
      // JSON Payload Validation
      try
        ValidationNode := GetJSON(RequestBody);
        ValidationNode.Free;
      except
        on E: Exception do
        begin
          SendHttpError(ClientConn, 400, 'Invalid JSON payload');
          fpshutdown(FClientHandle, 2);
          Exit;
        end;
      end;
      if Terminated then Exit;
      // 3. Extract and validate endpoint
      ReceivedEndpoint := '';
      // Extract the 2nd word from the first line (e.g., "POST /v1/chat HTTP/1.1")
      // This handles spaces, tabs, and any consecutive whitespaces automatically.
      Line := RequestHeader;
      i := Pos(#13#10, Line);
      if i > 0 then
        SetLength(Line, i - 1); // Narrow down to just the first line
      // Word 1 is method (POST), Word 2 is the URI/Endpoint
      ReceivedEndpoint := ExtractWord(2, Line, [' ', #9]);
      // Validate ReceivedEndpoint and Select Port
      CleanReceived := StringReplace(ReceivedEndpoint, '/', '', [rfReplaceAll]);
      while (Length(CleanReceived) > 0) and (CleanReceived[1] = '/') do
        Delete(CleanReceived, 1, 1);
      // Determine if it's Embedding or Conversational
      FinalTargetPort := -1;
      FinalEndpoint := '';
      if not(FTargetEmbeddingEndpoint = '') then
      begin
        if CleanReceived = StringReplace(FTargetEmbeddingEndpoint, '/', '', [rfReplaceAll]) then
        begin
          FinalTargetPort := FTargetEmbeddingPort;
          FinalEndpoint := FTargetEmbeddingEndpoint;
        end;
      end;
      if not(FTargetEndpoint = '') then
      begin
        if CleanReceived = StringReplace(FTargetEndpoint, '/', '', [rfReplaceAll]) then
        begin
          FinalTargetPort := FTargetPort;
          FinalEndpoint := FTargetEndpoint;
        end;
      end;
      if (FinalTargetPort = -1) or (FinalEndpoint = '') then
      begin
        WriteLn('[WORKER] Invalid endpoint: ', ReceivedEndpoint);
        SendHttpError(ClientConn, 404, 'Invalid endpoint. Expected: ' + FTargetEndpoint + ' or ' + FTargetEmbeddingEndpoint);
        fpshutdown(FClientHandle, 2);
        Exit;
      end;
      // 4. Forward to Llama
      WriteLn('[WORKER] Request redirected to port ', FinalTargetPort);
      LlamaStream := TInetSocket.Create('127.0.0.1', FinalTargetPort);
      FLlamaSocket := LlamaStream.Handle;
      try
        i := Pos(ReceivedEndpoint, RequestHeader);
        if (i > 0) and not(ReceivedEndpoint = '') then
        begin
          Delete(RequestHeader, i, Length(ReceivedEndpoint));
          while (Length(FinalEndpoint) > 0) and (FinalEndpoint[1] = '/') do
          begin
            Delete(FinalEndpoint, 1, 1);
          end;
          Insert('/' + FinalEndpoint, RequestHeader, i);
        end;
        LlamaStream.Write(RequestHeader[1], Length(RequestHeader));
        LlamaStream.Write(RequestBody[1], Length(RequestBody));
        FullContent := '';
        LastObject := nil;
        CurrentChunkTimeout := 10.0; // Start with 10s for first chunk
        while not(Terminated) do
        begin
          if (FProxyTimeout >= MIN_LLM_TIMEOUT_FOR_THRESHOLD) and ((Now - FStartTime) * 86400 >= (FProxyTimeout - LLM_TIMEOUT_THRESHOLD)) then
          begin
            WriteLn('[WORKER] LLM timeout reached, sending partial response.');
            TimeoutWarning := True;
            TimeoutReached := True;
            Break;
          end;
          if (Now - FStartTime) * 86400 > FProxyTimeout then
          begin
            WriteLn('[WORKER] Global timeout reached.');
            TimeoutReached := True;
            Break;
          end;
          ChunkStartTime := Now;
          LlamaStream.IOTimeout := Round(CurrentChunkTimeout * 1000);
          try
            Line := trim(InternalReadLine(LlamaStream));
          except
            Line := '';
          end;
          if Line = '' then
          begin
            ElapsedSeconds := (Now - ChunkStartTime) * 86400;
            if ElapsedSeconds >= (CurrentChunkTimeout - 0.1) then
            begin
              WriteLn('[WORKER] Llama server stalled.');
              TimeoutWarning := True;
              TimeoutReached := True;
              Break;
            end;
            Sleep(10);
            Continue;
          end;
          ElapsedSeconds := (Now - ChunkStartTime) * 86400;
          if ElapsedSeconds > 0.1 then
          begin
            CurrentChunkTimeout := ElapsedSeconds * 2;
            if CurrentChunkTimeout > FProxyTimeout then CurrentChunkTimeout := FProxyTimeout;
            if CurrentChunkTimeout < 3.0 then CurrentChunkTimeout := 3.0;
          end;
          // If it's a direct JSON response (Embeddings), it won't start with "data: "
          if (Line[1] = '{') and not(StartsStr('data: ', Line)) then
          begin
            FullContent := Line; // Store the whole JSON for embedding
            Break;
          end;
          // Conversational Streaming Logic
          if lowercase(Line) = 'data: [done]' then Break;
          if not(StartsStr('data: ', Line)) then Continue;
          Delete(Line, 1, 6);
          try
            DataNode := GetJSON(Line);
            if DataNode is TJSONObject then
            begin
              TempObj := TJSONObject(DataNode);
              ContentNode := TempObj.FindPath('choices[0].delta.content');
              if Assigned(ContentNode) and not(ContentNode.JSONType = jtNull) then
                FullContent := FullContent + ContentNode.AsString;
              if Assigned(LastObject) then LastObject.Free;
              LastObject := TJSONObject(TempObj.Clone);
              if
                Assigned(TempObj.FindPath('choices[0].finish_reason')) and
                not(TempObj.FindPath('choices[0].finish_reason').JSONType = jtNull)
              then Break;
            end;
            DataNode.Free;
          except
            // Ignore malformed chunks
          end;
        end;
        // 4. Final Response Construction
        WriteLn('[WORKER] Response received from ', FinalTargetPort);
        if TimeoutReached and (FullContent = '') then FullContent := '{"error": "Llama server stalled"}';
        if FullContent = '' then
          Line := '{"error": "Empty response from LLM engine"}'
        else if (FullContent[1] = '{') or (FinalEndpoint = FTargetEmbeddingEndpoint) then //It's already a JSON (Embedding)
          Line := FullContent
        else
        begin
          // Add warning message tou output
          if TimeoutWarning then FullContent := FullContent + ' - ' + LLM_TIMEOUT_WARNING;
          // Wrap conversational content back into JSON
          if not(Assigned(LastObject)) then
            LastObject := TJSONObject.Create(['choices', TJSONArray.Create([TJSONObject.Create(['index', 0])])]);
          if Assigned(LastObject.FindPath('choices[0].delta')) then
            TJSONObject(LastObject.FindPath('choices[0]')).Delete('delta');
          TJSONObject(LastObject.FindPath('choices[0]')).Add('message', TJSONObject.Create(['role', 'assistant', 'content', FullContent]));
          Line := LastObject.AsJSON;
        end;
        Line := 'HTTP/1.1 200 OK' + #13#10 + 'Content-Type: application/json' + #13#10 +
          'Content-Length: ' + IntToStr(Length(Line)) + #13#10 + 'Connection: close' + #13#10#13#10 + Line;
        ClientConn.Write(Line[1], Length(Line));
      finally
        if Assigned(LastObject) then FreeAndNil(LastObject);
        FLlamaSocket := -1;
        FreeAndNil(LlamaStream);
      end;
    except
      on E: Exception do
      begin
        WriteLn('[WORKER] Exception: ', E.Message);
        if not(FClientHandle = -1) then
        begin
          fpshutdown(FClientHandle, 2);
          CloseSocket(FClientHandle);
          FClientHandle := -1;
        end;
        if not(FLlamaSocket = -1) then
        begin
          fpshutdown(FLlamaSocket, 2);
          CloseSocket(FLlamaSocket);
          FLlamaSocket := -1;
        end;
      end;
    end;
  finally
    FreeAndNil(ClientConn);
    if not(FClientHandle = -1) then
    begin
      CloseSocket(FClientHandle);
      FClientHandle := -1;
    end;
    if not(FLlamaSocket = -1) then
    begin
      CloseSocket(FLlamaSocket);
      FLlamaSocket := -1;
    end;
  end;
end;

{ TProxyThread implementation. }

{ TProxyThread.Create: Initializes the proxy thread with routing and connection parameters. }
constructor TProxyThread.Create(AProxyHost: String; APort, ATargetPort, ATargetEmbeddingPort: Integer; AEndpoint, AEmbeddingEndpoint: String; ATimeout, AMax, Apmax: Integer);
begin
  inherited Create(false);
  FProxyHost := AProxyHost;
  FProxyPort := APort;
  FTargetPort := ATargetPort;
  FTargetEmbeddingPort := ATargetEmbeddingPort;
  FTargetEndpoint := AEndpoint;
  FTargetEmbeddingEndpoint := AEmbeddingEndpoint;
  FProxyTimeout := ATimeout;
  FProxyMaxConnections := AMax;
  FMaxPackageSize := Apmax;
  FWorkers := TFPList.Create;
end;

{ TProxyThread.Destroy: Terminates all workers and frees the proxy thread resources. }
destructor TProxyThread.Destroy;
var i: Integer;
begin
  for i := 0 to FWorkers.Count - 1 do
    TWorkerThread(FWorkers[i]).Terminate;
  FreeAndNil(FWorkers);
  FreeAndNil(FServerSocket);
  inherited Destroy;
end;

{ TProxyThread.CleanupFinishedWorkers: Removes and frees finished worker threads from the active list. }
procedure TProxyThread.CleanupFinishedWorkers;
var
  i: Integer;
  W: TWorkerThread;
begin
  for i := FWorkers.Count - 1 downto 0 do
  begin
    W := TWorkerThread(FWorkers[i]);
    if W.Finished then
    begin
      W.WaitFor;
      W.Free;
      FWorkers.Delete(i);
      continue;
    end;
    if W.Terminated then
    begin
      if not(W.FClientHandle = -1) then
      begin
        CloseSocket(W.FClientHandle);
        W.FClientHandle := -1;
      end;
    end;
  end;
end;

{ TProxyThread.EnforceTimeouts: Terminates workers that have exceeded the timeout limit. }
procedure TProxyThread.EnforceTimeouts;
var
  i: Integer;
  W: TWorkerThread;
begin
  for i := FWorkers.Count - 1 downto 0 do
  begin
    W := TWorkerThread(FWorkers[i]);
    if (Now - W.StartTime) * 86400 > FProxyTimeout then
    begin
      WriteLn('[PROXY] Worker timed out. Terminating.');
      W.Terminate;
      if not(W.FClientHandle = -1) then
      begin
        fpshutdown(W.FClientHandle, 2);
        CloseSocket(W.FClientHandle);
        W.FClientHandle := -1;
      end;
      if not(W.FLlamaSocket = -1) then
      begin
        fpshutdown(W.FLlamaSocket, 2);
        CloseSocket(W.FLlamaSocket);
        W.FLlamaSocket := -1;
      end;
      if not(W.Finished) then
      begin
        W.WaitFor;
        if not(W.Finished) then
        begin
          WriteLn('[PROXY] Worker did not terminate gracefully. Force-removing.');
          FWorkers.Delete(i);
          FreeAndNil(W);
        end;
      end;
    end;
  end;
end;

{ TProxyThread.Execute: Main thread method that manages the listener and spawns worker threads for connections. }
procedure TProxyThread.Execute;
var
  Listener: TListenerThread;
  Worker: TWorkerThread;
begin
  try
    Listener := nil;
    FServerSocket := TInetServer.Create(FProxyHost, FProxyPort);
    FServerSocket.Bind;
    FServerSocket.Listen;
    WriteLn('[PROXY] Multi-threaded manager listening on ', FProxyHost, ':', FProxyPort);
    while not(Terminated) do
    begin
      CleanupFinishedWorkers;
      EnforceTimeouts;
      // Start a new listener only when having enough free slots
      if (FWorkers.Count < FProxyMaxConnections) then
      begin
        if not(Assigned(Listener)) then
          Listener := TListenerThread.Create(FServerSocket);
      end
      else if Assigned(Listener) then
      begin
        // If we are full, terminate active listener
        Listener.Terminate;
      end;
      // Check if listener caught a connection
      if Assigned(Listener) then
      begin
        if Listener.Finished then
        begin
          if not(Listener.NewSocket = -1) then
          begin
            if FWorkers.Count >= FProxyMaxConnections then
            begin
               WriteLn('[PROXY] Max connections reached. Rejecting.');
               CloseSocket(Listener.NewSocket);
            end
            else
            begin
              Worker := TWorkerThread.Create(Listener.NewSocket, FTargetPort, FTargetEmbeddingPort, FTargetEndpoint, FTargetEmbeddingEndpoint, FProxyTimeout, FMaxPackageSize);
              try
                FWorkers.Add(Worker);
                WriteLn('[PROXY] Worker started: ', FWorkers.Count, '/', FProxyMaxConnections);
                Worker.Start;
              except
                on E: Exception do
                begin
                  WriteLn('[PROXY] Failed to start worker: ', E.Message);
                  CloseSocket(Listener.NewSocket);
                  FreeAndNil(Worker);
                end;
              end;
            end;
          end;
          FreeAndNil(Listener); // Reset listener for next connection
        end;
      end;
      Sleep(100); // Manager loop is now high-frequency and NEVER blocks
    end;
  finally
    if Assigned(Listener) then
    begin
      Listener.Terminate;
      // Forcing the server socket closed wakes up the fpAccept in the listener thread
      CloseSocket(FServerSocket.Socket);
      Listener.WaitFor;
      FreeAndNil(Listener);
    end;
    FreeAndNil(FServerSocket);
  end;
end;

{ TServiceWrapper implementation (Boilerplate and Glue). }

{ TServiceWrapper.StartProxy: Creates and starts the API proxy service thread. }
procedure TServiceWrapper.StartProxy(AProxyPort, ATargetPort, ATargetEmbeddingPort: Integer);
var
  StatusMsg, FinalFEndpoint, FinalFEmbeddingEndpoint: String;
  FinalATargetPort, FinalATargetEmbeddingPort: Integer;
begin
  FinalATargetPort := -1;
  FinalATargetEmbeddingPort := -1;
  FinalFEndpoint := '';
  FinalFEmbeddingEndpoint := '';
  StopProxy;
  if not(AProxyPort >= 1) then Exit;
  StatusMsg := Format('[INFO] Starting API Proxy on port %d -> ', [AProxyPort]);
  if not(FinalFModelFile = '') then
  begin
    FinalATargetPort := ATargetPort;
    FinalFEndpoint := FEndpoint;
    StatusMsg := StatusMsg + Format('Conversational active (%d), ', [ATargetPort]);
  end;
  if not(FinalFEmbeddingModelFile = '') then
  begin
    FinalATargetEmbeddingPort := ATargetEmbeddingPort;
    FinalFEmbeddingEndpoint := FEmbeddingEndpoint;
    StatusMsg := StatusMsg + Format('Embedding active (%d)', [ATargetEmbeddingPort]);
  end;
  WriteLn(StatusMsg);
  FProxyThread := TProxyThread.Create(
    FProxyHost,
    AProxyPort,
    FinalATargetPort,
    FinalATargetEmbeddingPort,
    FinalFEndpoint,
    FinalFEmbeddingEndpoint,
    FProxyTimeout,
    FProxyMaxConnections,
    FMaxPackageSize);
end;

{ TServiceWrapper.StopProxy: Stops the API proxy service thread gracefully. }
procedure TServiceWrapper.StopProxy;
begin
  if not(Assigned(FProxyThread)) then Exit;
  FProxyThread.Terminate;
  if Assigned(FProxyThread.FServerSocket) then
    CloseSocket(FProxyThread.FServerSocket.Socket);
  // Note: In a real-world scenario, you'd force-close the listening socket here
  FProxyThread.WaitFor;
  FreeAndNil(FProxyThread);
  WriteLn('[INFO] API Proxy stopped.');
end;

{ TServiceWrapper.CheckSingleInstance: Verifies no other instance is running, preventing duplicate execution. }
function TServiceWrapper.CheckSingleInstance: Boolean;
var
  MutexName: string;
  {$IFDEF UNIX}
  LockFile: AnsiString;
  {$ENDIF}
begin
  Result := true;
  FInstanceID := LowerCase(MD5Print(MD5String(trim(ParamStr(0)))));
  {$IFDEF MSWINDOWS}
  // Windows doesn't need an extension
  MutexName := INSTANCE_PREFIX + FInstanceID;
  FMutex := CreateMutex(nil, false, PChar(MutexName));
  if not(FMutex = 0) and (GetLastError = ERROR_ALREADY_EXISTS) then
  begin
    CloseHandle(FMutex);
    FMutex := 0;
    Result := false;
    Exit;
  end;
  {$ENDIF}
  {$IFDEF UNIX}
  // Linux uses the path + ID + .pid
  LockFile := INSTANCE_PREFIX + FInstanceID + '.pid';
  // Open with Read/Write, Create if doesn't exist
  FLockFileHandle := fpOpen(LockFile, O_CREAT or O_RDWR, 438);
  if FLockFileHandle = -1 then
  begin
    Result := false;
    Exit;
  end;
  // LOCK_NB = Non-Blocking.
  // If this fails, the kernel knows another PID holds the lock.
  if fpFlock(FLockFileHandle, LOCK_EX or LOCK_NB) = 0 then
  begin
    // Optional: Write current PID to the file for debugging
    // This isn't required for the lock to work, but it's good practice.
    fpTruncate(FLockFileHandle, 0);
    FpWrite(FLockFileHandle, IntToStr(fpGetPid)[1], Length(IntToStr(fpGetPid)));
    Exit;
  end;
  // If we reach here, locking failed
  Result := false;
  fpClose(FLockFileHandle);
  {$ENDIF}
end;

{ TServiceWrapper.IsPortFree: Check for IPv4 and optional IPv6 availability. Returns True if port can be bound OR if protocol is completely unsupported by OS, False otherwise. }
function TServiceWrapper.IsPortFree(APort: Integer): Boolean;
  { Helper: Try to bing port without blocking. }
  function TryBind(Family: SmallInt): Boolean;
  const
    IPPROTO_IPV6 = 41;
    IPV6_V6ONLY = {$IFDEF MSWINDOWS}27{$ELSE}26{$ENDIF};
  var
    S: LongInt;
    Addr4: TInetSockAddr;
    Addr6: TInetSockAddr6;
    OptVal: Integer;
  begin
    Result := False;
    S := fpSocket(Family, SOCK_STREAM, 0);
    if S = -1 then
    begin
      // If IPv6 socket creation fails, OS doesn't support IPv6 (ignore it -> True).
      // If IPv4 socket creation fails, system socket error (fail check -> False).
      Result := (Family = AF_INET6);
      Exit;
    end;
    try
      OptVal := 1;
      // 1. Isolate IPv6 sockets from IPv4 to prevent dual-stack bind conflicts
      if Family = AF_INET6 then fpsetsockopt(S, IPPROTO_IPV6, IPV6_V6ONLY, @OptVal, SizeOf(OptVal));
      // 2. Prevent socket-hijacking on Windows (WSL2 / WinNAT port conflicts)
      {$IFDEF MSWINDOWS}
      fpsetsockopt(S, SOL_SOCKET, SO_EXCLUSIVEADDRUSE, @OptVal, SizeOf(OptVal));
      {$ENDIF}
      // 3. Test bind availability
      if Family = AF_INET then
      begin
        FillChar(Addr4, SizeOf(Addr4), 0);
        Addr4.sin_family := AF_INET;
        Addr4.sin_port := htons(Word(APort));
        Addr4.sin_addr.s_addr := htonl(LongWord(INADDR_ANY));
        Result := (fpBind(S, @Addr4, SizeOf(Addr4)) = 0);
        Exit;
      end;
      FillChar(Addr6, SizeOf(Addr6), 0);
      Addr6.sin6_family := AF_INET6;
      Addr6.sin6_port := htons(Word(APort));
      Result := (fpBind(S, @Addr6, SizeOf(Addr6)) = 0);
    finally
      CloseSocket(S);
    end;
  end;
begin
  // Default value
  Result := False;
  // Guard 1: Sanity check port range
  if (APort < 1) or (APort > 65535) then Exit;
  // Guard 2: Must be free on IPv4
  if not(TryBind(AF_INET)) then Exit;
  // Guard 3: Must be free on IPv6 (unless host OS has IPv6 disabled entirely)
  Result := TryBind(AF_INET6);
end;

{ TServiceWrapper.HandleGlobalException: Global exception handler that logs error and terminates application. }
procedure TServiceWrapper.HandleGlobalException(Sender: TObject; E: Exception);
begin
  WriteLn(StdErr, 'GLOBAL FATAL: ', E.Message);
  Cleanup;
  Halt(1);
end;

{ TServiceWrapper.InitPaths: Initializes all path variables based on executable location. }
procedure TServiceWrapper.InitPaths;
begin
  FAppDir := IncludeTrailingPathDelimiter(ExtractFilePath(ExeName));
  FConfigDir := FAppDir + 'config' + PathDelim;
  FModelDir := FAppDir + 'model' + PathDelim;
  FEmbeddingModelDir := FModelDir + 'embedding' + PathDelim;
  FLlamaDir := FAppDir + 'llama' + PathDelim;
  DBPath := FAppDir + 'database' + PathDelim + 'wrapper.db';
  DBPathWAL := ChangeFileExt(DBPath, '.db-wal');
  DBPathSHM := ChangeFileExt(DBPath, '.db-shm');
  FParams := TStringList.Create;
  FEmbeddingParams := TStringList.Create;
  FProxyHost := '127.0.0.1';
  FWebserverHttpPort := 80;
  FWebserverHttpsPort := 443;
  FPhpHost := '127.0.0.1';
  FPhpPort := 9000;
  FOpensslBinary := FAppDir + 'webserver' + PathDelim + 'openssl' + PathDelim + 'bin' + PathDelim + 'openssl.exe';
  FWebserverBinary := FAppDir + 'webserver' + PathDelim + 'nginx.exe';
  FPhpBinary := FAppDir + 'webserver' + PathDelim + 'php' + PathDelim + 'php-cgi.exe';
  FSSLcertDir := FAppDir + 'webserver' + PathDelim + 'conf' + PathDelim + 'ssl' + PathDelim;
  FSSLcertificate := FSSLcertDir + 'nginx.crt';
  FSSLkey := FSSLcertDir + 'nginx.key';
  FSSLexpiration := 3650; // days
  FSSGeneration := 10; // days
  FSSLencryption := 'rsa:2048';
end;

{ TServiceWrapper.SetupDatabase: Opens connection to the SQLite configuration database. }
procedure TServiceWrapper.SetupDatabase;
begin
  FConn := TSQLite3Connection.Create(nil);
  FTrans := TSQLTransaction.Create(FConn);
  FQuery := TSQLQuery.Create(nil);
  FConn.Transaction := FTrans;
  FConn.DatabaseName := DBPath;
  FQuery.Database := FConn;
  try
    //DO NOT delete WAL/SHM files before opening - let SQLite handle them
    {if FileExists(DBPathWAL) then DeleteFile(DBPathWAL);
    if FileExists(DBPathSHM) then DeleteFile(DBPathSHM);}
    FConn.Open;
    // Set busy timeout to wait for transient locks instead of failing immediately
    FConn.ExecuteDirect('PRAGMA busy_timeout = 5000');
  except
    on E: Exception do
      raise Exception.Create('Database Error: ' + E.Message);
  end;
end;

{ TServiceWrapper.LoadConfiguration: Loads server and proxy configuration from database and JSON file. }
procedure TServiceWrapper.LoadConfiguration;
var
  SL: TStringList;
  FModelFile, FEmbeddingModelFile, JsonFile: AnsiString;
  JsonData, EngineNode, DeviceNode, ModelNode, EmbeddingModelNode, LLMnode, EmbeddingNode, LogNode: TJSONData;
  WebServerData, ProxyPortNode, ProxyTimeoutNode, ProxyMaxConnectionsNode, MaxPackageSizeNode: TJSONData;
  httpPortNode, httpsPortNode, sslCertNode, sslKeyNode, phpPortNode: TJSONData;
  Root, ParamsObj, WebServerObj: TJSONObject;
  EngineID: String;
  ProxyPort: String;
  i: Integer;
  ParamName, ParamValue: AnsiString;
  enableServer: Boolean;
  //enableCLI: Boolean;
  ServerFileName: String;
  AllowedParams, AllowedEmbeddingParams: TStringList;
  ConfigTypeName: String;
  FHost, FEmbeddingHost: String;
begin
  JsonFile := FConfigDir + 'wrapper.json';
  EngineID := '';
  FDeviceID := '';
  FEndpoint := '';
  FEmbeddingEndpoint := '';
  FModelFile := '';
  FinalFModelFile := '';
  FEmbeddingModelFile := '';
  FinalFEmbeddingModelFile := '';
  FLLMenabled := true;
  FEmbeddingEnabled := true;
  FUseLogFile := true; // Default
  FProxyPort := -1; // Default
  FProxyTimeout := 60; // Default
  FProxyMaxConnections := 200; // Default
  FMaxPackageSize := 2097152; // Default
  { --- STEP 1: Preliminary JSON Scan (To get EngineID only) --- }
  if FileExists(JsonFile) then
  begin
    SL := TStringList.Create;
    try
      SL.LoadFromFile(JsonFile);
      JsonData := GetJSON(SL.Text);
      if JsonData is TJSONObject then
      begin
        EngineNode := TJSONObject(JsonData).Find('llama_engine');
        if Assigned(EngineNode) then EngineID := trim(EngineNode.AsString);
      end;
      JsonData.Free;
    finally
      SL.Free;
    end;
  end;
  { --- STEP 2: Resolve Server Data from DB --- }
  FQuery.SQL.Clear;
  FQuery.SQL.Add('SELECT id, server, endpoint, embedding_endpoint, proxy_port, proxy_timeout, max_proxy_connections, max_package_size FROM config');
  if EngineID = '' then
    FQuery.SQL.Add(' ORDER BY priority DESC, id ASC LIMIT 1')
  else
  begin
    FQuery.SQL.Add(' WHERE id = :id LIMIT 1');
    FQuery.ParamByName('id').AsString := EngineID;
  end;
  FQuery.Open;
  if FQuery.EOF then raise Exception.Create('No LLM server specified!');
  EngineID := trim(FQuery.FieldByName('id').AsString);
  ServerFileName := trim(FQuery.FieldByName('server').AsString);
  ServerFileName := StringReplace(ServerFileName, '/', PathDelim, [rfReplaceAll]);
  FServerBinary := FLlamaDir + ServerFileName;
  FEndpoint := trim(FQuery.FieldByName('endpoint').AsString);
  FEmbeddingEndpoint := trim(FQuery.FieldByName('embedding_endpoint').AsString);
  //Proxy settings from DB are only used if JSON doesn't override later
  ProxyPort := trim(FQuery.FieldByName('proxy_port').AsString);
  if length(ProxyPort) >= 1 then
  begin
    if StrToIntDef(ProxyPort, -1) >= 1 then
    begin
      FProxyPort := StrToInt(ProxyPort);
      FProxyTimeout := StrToIntDef(trim(FQuery.FieldByName('proxy_timeout').AsString), 60);
      FProxyMaxConnections := StrToIntDef(trim(FQuery.FieldByName('max_proxy_connections').AsString), 200);
      FMaxPackageSize := StrToIntDef(trim(FQuery.FieldByName('max_package_size').AsString), 2097152);
    end;
  end;
  FQuery.Close;
  { --- STEP 3: Load config_data from DB (Mandatory Filter) --- }
  AllowedParams := TStringList.Create;
  AllowedParams.Sorted := true;
  AllowedEmbeddingParams := TStringList.Create;
  AllowedEmbeddingParams.Sorted := true;
  try
    //FQuery.SQL.Text := 'SELECT config_data.name AS name, config_data.value AS value, config_data_type.name AS type_name, config_data.enable_server AS enable_server, config_data.enable_cli AS enable_cli FROM config_data LEFT JOIN config_data_type ON config_data_type.id = config_data.type_id WHERE config_data.config_id = :cid';
    FQuery.SQL.Text := 'SELECT config_data.name AS name, config_data.value AS value, config_data_type.name AS type_name, config_data.enable_server AS enable_server FROM config_data LEFT JOIN config_data_type ON config_data_type.id = config_data.type_id WHERE config_data.config_id = :cid';
    FQuery.ParamByName('cid').AsString := EngineID;
    FQuery.Open;
    while not(FQuery.EOF) do
    begin
      ParamName := trim(FQuery.FieldByName('name').AsString);
      ParamValue := trim(FQuery.FieldByName('value').AsString);
      ConfigTypeName := uppercase(trim(FQuery.FieldByName('type_name').AsString));
      enableServer := not(StrToIntDef(trim(FQuery.FieldByName('enable_server').AsString), 0) = 0);
      //enableCLI := not(StrToIntDef(trim(FQuery.FieldByName('enable_cli').AsString), 0) = 0); //Will be used later
      if ConfigTypeName = 'EMBEDDING' then
      begin
        //Allowed parameters for server
        AllowedEmbeddingParams.Values[ParamName] := BoolToStr(enableServer, '1', '0');
        // Default load: only if not using JSON parameters later
        if not(ParamName = 'device') then
        begin
          if ParamName = 'model' then
          begin
            if enableServer then FEmbeddingModelFile := ParamValue;
          end
          else if ParamName = 'host' then
          begin
            if enableServer then FEmbeddingHost := ParamValue;
          end
          else if enableServer then
          begin
            FEmbeddingParams.Add('--' + ParamName);
            if not(ParamValue = '') then FEmbeddingParams.Add(ParamValue);
          end;
        end;
      end
      else if ConfigTypeName = 'CONVERSATIONAL' then
      begin
        //Allowed parameters for server
        AllowedParams.Values[ParamName] := BoolToStr(enableServer, '1', '0');
        // Default load: only if not using JSON parameters later
        if not(ParamName = 'device') then
        begin
          if ParamName = 'model' then
          begin
            if enableServer then FModelFile := ParamValue;
          end
          else if ParamName = 'host' then
          begin
            if enableServer then FHost := ParamValue;
          end
          else if enableServer then
          begin
            FParams.Add('--' + ParamName);
            if not(ParamValue = '') then FParams.Add(ParamValue);
          end;
        end;
      end;
      FQuery.Next;
    end;
    FQuery.Close;
    FQuery.SQL.Clear;
    FQuery.SQL.Add('SELECT name, value FROM webserver_config ORDER BY id ASC');
    FQuery.Open;
    while not(FQuery.EOF) do
    begin
      ParamName := trim(FQuery.FieldByName('name').AsString);
      ParamValue := trim(FQuery.FieldByName('value').AsString);
      if SameText(ParamName, 'NGINX_BINARY') then
        FWebserverBinary := FAppDir + StringReplace(ParamValue, '/', PathDelim, [rfReplaceAll])
      else if SameText(ParamName, 'NGINX_HTTP_PORT') then
        FWebserverHttpPort := StrToIntDef(ParamValue, FWebserverHttpPort)
      else if SameText(ParamName, 'NGINX_HTTPS_PORT') then
        FWebserverHttpsPort := StrToIntDef(ParamValue, FWebserverHttpsPort)
      else if SameText(ParamName, 'NGINX_SSL_CERTIFICATE') then
        FSSLcertificate := FAppDir + StringReplace(ParamValue, '/', PathDelim, [rfReplaceAll])
      else if SameText(ParamName, 'NGINX_SSL_KEY') then
        FSSLkey := FAppDir + StringReplace(ParamValue, '/', PathDelim, [rfReplaceAll])
      else if SameText(ParamName, 'NGINX_SSL_EXPIRATION') then
        FSSLexpiration := StrToIntDef(ParamValue, FSSLexpiration)
      else if SameText(ParamName, 'NGINX_SSL_ENCRYPTION') then
        FSSLencryption := ParamValue
      else if SameText(ParamName, 'OPENSSL_BINARY') then
        FOpensslBinary := FAppDir + StringReplace(ParamValue, '/', PathDelim, [rfReplaceAll])
      else if SameText(ParamName, 'PHP_BINARY') then
        FPhpBinary := FAppDir + StringReplace(ParamValue, '/', PathDelim, [rfReplaceAll])
      else if SameText(ParamName, 'PHP_HTTP_HOST') then
        FPhpHost := ParamValue
      else if SameText(ParamName, 'PHP_HTTP_PORT') then
        FPhpPort := StrToIntDef(ParamValue, FPhpPort);
      FQuery.Next;
    end;
    FQuery.Close;
    { --- STEP 4: Apply JSON Overrides and Permission Checks --- }
    if FileExists(JsonFile) then
    begin
      SL := TStringList.Create;
      try
        SL.LoadFromFile(JsonFile);
        JsonData := GetJSON(SL.Text);
        if JsonData is TJSONObject then
        begin
          Root := TJSONObject(JsonData);
          FParams.Clear; //Clear the DB-loaded params because we are overriding
          FEmbeddingParams.Clear; //Clear the DB-loaded embedding params because we are overriding
          //Get device
          DeviceNode := Root.Find('llama_device');
          if Assigned(DeviceNode) then
          begin
            if not(AllowedParams.Values['device'] = '0') then
              FDeviceID := trim(DeviceNode.AsString);
          end;
          // Enable or Disable LLM server
          LLMnode := Root.Find('llm_enabled');
          if Assigned(LLMnode) then
          begin
            if LLMnode.JSONType = jtNumber then
              FLLMenabled := not(LLMnode.AsInteger = 0)
            else
              FLLMenabled := (IndexStr(LowerCase(trim(LLMnode.AsString)), ['0', 'false', 'no']) = -1);
          end;
          if FLLMenabled then
          begin
            ModelNode := Root.Find('model');
            if Assigned(ModelNode) then
              FModelFile := trim(ModelNode.AsString)
            else
              FModelFile := '';
          end
          else
            FModelFile := '';
          LogNode := Root.Find('logging');
          if Assigned(LogNode) then
          begin
            if LogNode.JSONType = jtNumber then
              FUseLogFile := not(LogNode.AsInteger = 0)
            else
              FUseLogFile := (IndexStr(LowerCase(trim(LogNode.AsString)), ['0', 'false', 'no']) = -1);
          end;
          ProxyPortNode := Root.Find('proxy_port');
          if Assigned(ProxyPortNode) then
          begin
            ProxyPort := trim(ProxyPortNode.AsString);
            if length(ProxyPort) >= 1 then
            begin
              if StrToIntDef(ProxyPort, -1) >= 1 then
              begin
                FProxyPort := StrToInt(ProxyPort);
                ProxyTimeoutNode := Root.Find('proxy_timeout');
                if Assigned(ProxyTimeoutNode) then
                  FProxyTimeout := StrToIntDef(trim(ProxyTimeoutNode.AsString), 60);
                ProxyMaxConnectionsNode := Root.Find('max_proxy_connections');
                if Assigned(ProxyMaxConnectionsNode) then
                  FProxyMaxConnections := StrToIntDef(trim(ProxyMaxConnectionsNode.AsString), 200);
                MaxPackageSizeNode := Root.Find('max_package_size');
                if Assigned(MaxPackageSizeNode) then
                  FMaxPackageSize := StrToIntDef(trim(MaxPackageSizeNode.AsString), 2097152);
              end;
            end;
          end;
          // Parameter Loop with DB validation
          if not(FModelFile = '') then
          begin
            ParamsObj := Root.Get('parameters', TJSONObject(nil));
            if Assigned(ParamsObj) then
            begin
              if ParamsObj.Count > 0 then
              begin
                for i := 0 to ParamsObj.Count - 1 do
                begin
                  ParamName := trim(ParamsObj.Names[i]);
                  if ParamName = '' then continue;
                  if ParamName = 'device' then continue;
                  if ParamName = 'model' then continue;
                  if ParamName = 'host' then
                  begin
                    FHost := trim(ParamsObj.Items[i].AsString);
                    continue;
                  end;
                  if AllowedParams.Values[ParamName] = '0' then continue;
                  FParams.Add('--' + ParamName); //Flag
                  if not(ParamsObj.Items[i].JSONType in [jtBoolean, jtNull]) then
                    FParams.Add(trim(ParamsObj.Items[i].AsString)); // Value
                end;
              end;
            end;
          end;
          // Enable or Disable Embedding
          EmbeddingNode := Root.Find('embedding');
          if Assigned(EmbeddingNode) then
          begin
            if EmbeddingNode.JSONType = jtNumber then
              FEmbeddingEnabled := not(EmbeddingNode.AsInteger = 0)
            else
              FEmbeddingEnabled := (IndexStr(LowerCase(trim(EmbeddingNode.AsString)), ['0', 'false', 'no']) = -1);
          end;
          if FEmbeddingEnabled then
          begin
            // Load Embedding Model
            EmbeddingModelNode := Root.Find('embedding_model');
            if Assigned(EmbeddingModelNode) then
            begin
              FEmbeddingModelFile := trim(EmbeddingModelNode.AsString);
              if not(FEmbeddingModelFile = '') then
              begin
                // Embedding Parameter Loop with DB validation
                ParamsObj := Root.Get('embedding_parameters', TJSONObject(nil));
                if Assigned(ParamsObj) then
                begin
                  if ParamsObj.Count > 0 then
                  begin
                    for i := 0 to ParamsObj.Count - 1 do
                    begin
                      ParamName := trim(ParamsObj.Names[i]);
                      if ParamName = '' then continue;
                      if ParamName = 'device' then continue;
                      if ParamName = 'model' then continue;
                      if ParamName = 'host' then
                      begin
                        FEmbeddingHost := trim(ParamsObj.Items[i].AsString);
                        continue;
                      end;
                      if AllowedEmbeddingParams.Values[ParamName] = '0' then continue;
                      FEmbeddingParams.Add('--' + ParamName); //Flag
                      if not(ParamsObj.Items[i].JSONType in [jtBoolean, jtNull]) then
                        FEmbeddingParams.Add(trim(ParamsObj.Items[i].AsString)); // Value
                    end;
                  end;
                end;
              end;
            end;
          end
          else
          begin
            // Clear Embedding Model File as embedding is disabled
            FEmbeddingModelFile := '';
          end;
          // Load web server configuration
          WebServerData := Root.Find('webserver');
          if Assigned(WebServerData) then
          begin
            if WebServerData.JSONType = jtObject then
            begin
              WebServerObj := TJSONObject(WebServerData);
              httpPortNode := WebServerObj.Find('nginx_http_port');
              if Assigned(httpPortNode) then
              begin
                if httpPortNode.JSONType = jtNumber then
                  FWebserverHttpPort := httpPortNode.AsInteger
                else
                  FWebserverHttpPort := StrToIntDef(trim(httpPortNode.AsString), 80);
              end;
              httpsPortNode := WebServerObj.Find('nginx_https_port');
              if Assigned(httpsPortNode) then
              begin
                if httpsPortNode.JSONType = jtNumber then
                  FWebserverHttpsPort := httpsPortNode.AsInteger
                else
                  FWebserverHttpsPort := StrToIntDef(trim(httpsPortNode.AsString), 443);
              end;
              sslCertNode := WebServerObj.Find('nginx_ssl_certificate');
              if Assigned(sslCertNode) then
                FSSLcertificate := FAppDir + StringReplace(trim(sslCertNode.AsString), '/', PathDelim, [rfReplaceAll]);
              sslKeyNode := WebServerObj.Find('nginx_ssl_key');
              if Assigned(sslKeyNode) then
                FSSLkey := FAppDir + StringReplace(trim(sslKeyNode.AsString), '/', PathDelim, [rfReplaceAll]);
              phpPortNode := WebServerObj.Find('php_http_port');
              if Assigned(phpPortNode) then
              begin
                if phpPortNode.JSONType = jtNumber then
                  FPhpPort := phpPortNode.AsInteger
                else
                  FPhpPort := StrToIntDef(trim(phpPortNode.AsString), 9000);
              end;
            end;
          end;
        end;
        JsonData.Free;
      finally
        SL.Free;
      end;
    end;
  finally
    FreeAndNil(AllowedParams);
    FreeAndNil(AllowedEmbeddingParams);
  end;
  { --- FINAL VALIDATION --- }
  if not(FileExists(FServerBinary)) then raise Exception.Create('Server binary missing: ' + FServerBinary);
  if (FEndpoint = '') and (FEmbeddingEndpoint = '') then raise Exception.Create('FATAL: no endpoint specified!');
  if (FModelFile = '') and (FEmbeddingModelFile = '') then raise Exception.Create('FATAL: no model specified!');
  if not(FModelFile = '') then
  begin
    if (Pos(' ', FModelFile) > 0) or (Pos(PathDelim, FModelFile) > 0) then
      raise Exception.Create('FATAL: model filename contains forbidden characters (spaces, slashes, or backslashes): ' + FModelFile);
    FinalFModelFile := FModelDir + FModelFile;
    if not(FileExists(FinalFModelFile)) then raise Exception.Create('Model file not found: ' + FinalFModelFile);
  end;
  if not(FEmbeddingModelFile = '') then
  begin
    if (Pos(' ', FEmbeddingModelFile) > 0) or (Pos(PathDelim, FEmbeddingModelFile) > 0) then
      raise Exception.Create('FATAL: model filename contains forbidden characters (spaces, slashes, or backslashes): ' + FEmbeddingModelFile);
    FinalFEmbeddingModelFile := FEmbeddingModelDir + FEmbeddingModelFile;
    if not(FileExists(FinalFEmbeddingModelFile)) then raise Exception.Create('Model file not found: ' + FinalFEmbeddingModelFile);
  end;
  // Set proxy host based on LLM/Embedding server host configuration
  // Priority: LLM host > Embedding host > default 127.0.0.1
  if not(FinalFModelFile = '') and not(FHost = '') then
    FProxyHost := FHost
  else if not(FinalFEmbeddingModelFile = '') and not(FEmbeddingHost = '') then
    FProxyHost := FEmbeddingHost
  else
    FProxyHost := '127.0.0.1';
  if FProxyPort >= 1 then
  begin
    if (FProxyTimeout < 1) then raise Exception.Create('Invalid Proxy Service Timeout: ' + IntToStr(FProxyTimeout));
    if (FProxyMaxConnections < 1) then raise Exception.Create('Invalid Proxy Service Connection Limit: ' + IntToStr(FProxyMaxConnections));
    if (FMaxPackageSize < 1) then raise Exception.Create('Invalid Package Size Limit: ' + IntToStr(FMaxPackageSize));
  end;
  if not(FileExists(FWebserverBinary)) then raise Exception.Create('Web server binary missing: ' + FWebserverBinary);
  if not(FileExists(FPhpBinary)) then raise Exception.Create('PHP binary missing: ' + FPhpBinary);
  if not(FileExists(FOpensslBinary)) then raise Exception.Create('OpenSSL binary missing: ' + FOpensslBinary);
  if not(DirectoryExists(FSSLcertDir)) then raise Exception.Create('SSL certificate directory missing: ' + FSSLcertDir);
  if (FWebserverHttpPort < 1) or (FWebserverHttpPort > 65535) then raise Exception.Create('Invalid HTTP port for web server: ' + IntToStr(FWebserverHttpPort));
  if (FWebserverHttpsPort < 1) or (FWebserverHttpsPort > 65535) then raise Exception.Create('Invalid HTTPS port for web server: ' + IntToStr(FWebserverHttpsPort));
  if (FPhpPort < 1) or (FPhpPort > 65535) then raise Exception.Create('Invalid PHP port: ' + IntToStr(FPhpPort));
  if FSSLexpiration < 1 then raise Exception.Create('Invalid SSL expiration: ' + IntToStr(FSSLexpiration));
  // Generate SSL certificate if needed
  if not(IsCertOnlyMode) then GenerateSslCertificateIfNeeded;
end;

{ TServiceWrapper.GenerateSslCertificate: Generates a self-signed SSL certificate using OpenSSL. }
procedure TServiceWrapper.GenerateSslCertificate(const CertFile, KeyFile: AnsiString);
var
  SslDir, CertFileFixed, KeyFileFixed, OpenSslCfg, KeyAlg: AnsiString;
  Parameters: TStringList;
begin
  CertFileFixed := trim(CertFile);
  if CertFileFixed = '' then raise Exception.Create('ERROR: no SSL certificate filename provided!');
  KeyFileFixed := trim(KeyFile);
  if KeyFileFixed = '' then raise Exception.Create('ERROR: no SSL key filename provided!');
  SslDir := IncludeTrailingPathDelimiter(ExtractFilePath(CertFileFixed));
  KeyAlg := FSSLencryption;
  WriteLn('[INFO] Generating self-signed SSL certificate...');
  WriteLn('[INFO] Certificate: ' + CertFileFixed);
  WriteLn('[INFO] Key file: ' + KeyFileFixed);
  // Create SSL directory if it doesn't exist
  if not(DirectoryExists(SslDir)) then ForceDirectories(SslDir);
  // Create OpenSSL config with inline SAN
  OpenSslCfg := SslDir + 'openssl.cnf';
  try
    with TStringList.Create do
    try
      Add('[req]');
      Add('default_bits = 2048');
      Add('distinguished_name = req_distinguished_name');
      Add('x509_extensions = v3_req');
      Add('prompt = no');
      Add('');
      Add('[req_distinguished_name]');
      Add('C = US');
      Add('ST = State');
      Add('L = City');
      Add('O = Organization');
      Add('CN = localhost');
      Add('');
      Add('[v3_req]');
      Add('subjectAltName = DNS:localhost,IP:127.0.0.1,IP:0:0:0:0:0:0:0:1');
      Add('keyUsage = digitalSignature,keyEncipherment');
      Add('extendedKeyUsage = serverAuth');
      Add('basicConstraints=CA:FALSE');
      SaveToFile(OpenSslCfg);
    finally
      Free;
    end;
    if not(FileExists(OpenSslCfg)) then raise Exception.Create('Cannot create OpenSSL config file.');
    // Generate certificate using OpenSSL
    Parameters := TStringList.Create;
    try
      Parameters.Add('req');
      Parameters.Add('-x509');
      Parameters.Add('-nodes');
      Parameters.Add('-days');
      Parameters.Add(IntToStr(FSSLexpiration));
      Parameters.Add('-newkey');
      Parameters.Add(KeyAlg);
      Parameters.Add('-sha256');
      Parameters.Add('-config');
      Parameters.Add(OpenSslCfg);
      Parameters.Add('-extensions');
      Parameters.Add('v3_req');
      Parameters.Add('-keyout');
      Parameters.Add(KeyFileFixed);
      Parameters.Add('-out');
      Parameters.Add(CertFileFixed);
      Parameters.Add('-subj');
      Parameters.Add('/C=US/ST=State/L=City/O=Organization/CN=localhost');
      if not(ExecAndCapture(FOpensslBinary, Parameters) = 0) then
        raise Exception.Create('Failed to generate SSL certificate.');
    finally
      FreeAndNil(Parameters);
    end;
    WriteLn('[INFO] SSL certificate generated successfully.');
  finally
    // Clean up OpenSSL config file
    if FileExists(OpenSslCfg) then DeleteFile(OpenSslCfg);
  end;
end;

{ TServiceWrapper.GenerateSslCertificateIfNeeded: Checks certificate expiration and generates if needed. }
procedure TServiceWrapper.GenerateSslCertificateIfNeeded;
var
  CertFile, KeyFile: AnsiString;
  NeedsCert: Boolean;
begin
  // Determine if we need to generate a certificate
  CertFile := FSSLcertificate;
  KeyFile := FSSLkey;
  NeedsCert := (not(FileExists(CertFile)) or not(FileExists(KeyFile)));
  // Check if certificate has expired if it exists
  if not(NeedsCert) then
  begin
    // Check actual certificate expiration by parsing the X.509 certificate
    // Use OpenSSL to extract the notAfter date and compare with current date
    NeedsCert := CheckCertificateExpiration(CertFile, FSSGeneration);
  end;
  if not(NeedsCert) then
  begin
    WriteLn('[INFO] SSL certificates found and valid.');
    Exit;
  end;
  GenerateSslCertificate(CertFile, KeyFile);
end;

{ TServiceWrapper.ExecAndCapture: Executes an external command and captures output, returning exit code. }
function TServiceWrapper.ExecAndCapture(const command: AnsiString; const parameters: TStringList): Integer;
var
  Process: TProcess;
  ExitCode: Integer;
  i: Integer;
begin
  Process := TProcess.Create(nil);
  try
    Process.Executable := command;
    Process.Parameters.Clear;
    if Assigned(parameters) then
    begin
      if parameters.Count > 0 then
      begin
        for i := 0 to parameters.Count - 1 do
        begin
          Process.Parameters.Add(parameters[i]);
        end;
      end;
    end;
    Process.Options := [poWaitOnExit];
    Process.ShowWindow := swoHide;
    Process.Execute;
    ExitCode := Process.ExitCode;
    Result := ExitCode;
  finally
    FreeAndNil(Process);
  end;
end;

{ TServiceWrapper.CheckCertificateExpiration: Checks if SSL certificate is expired or within renewal window. }
function TServiceWrapper.CheckCertificateExpiration(const CertFile: AnsiString; ExpirationDays: Integer): Boolean;
var
  Code: Integer;
  Seconds: Int64;
  CertFileFixed: AnsiString;
  Parameters: TStringList;
begin
  Result := true; // Default to needing cert renewal on any error
  try
    CertFileFixed := trim(CertFile);
    if CertFileFixed = '' then Exit;
    if ExpirationDays <= 0 then Exit;
    Seconds := Int64(ExpirationDays) * 24 * 60 * 60;
    // Use OpenSSL -checkend option to verify certificate validity
    // Returns 0 if cert will NOT expire within N seconds (still valid)
    // Returns 1 if cert WILL expire within N seconds (or already expired)
    Parameters := TStringList.Create;
    try
      Parameters.Add('x509');
      Parameters.Add('-in');
      Parameters.Add(CertFileFixed);
      Parameters.Add('-noout');
      Parameters.Add('-checkend');
      Parameters.Add(IntToStr(Seconds));
      Code := ExecAndCapture(FOpensslBinary, Parameters);
    finally
      FreeAndNil(Parameters);
    end;
    //WriteLn('[DEBUG] Code: ' + IntToStr(Code));
    Result := not(Code = 0);
    if Result then
    begin
      WriteLn('[INFO] Certificate expired or will expire within ' + IntToStr(ExpirationDays) + ' days, regenerating.');
      Exit;
    end;
    WriteLn('[INFO] Certificate is still valid for at least ' + IntToStr(ExpirationDays) + ' days.');
  except
    Result := true; // Default to needing cert renewal on exception
  end;
end;

{ TServiceWrapper.WaitUntilPortFree: Blocks until the specified port becomes available for binding. }
procedure TServiceWrapper.WaitUntilPortFree(APort: Integer);
begin
  while not(Terminated) do
  begin
    if IsPortFree(APort) then
    begin
      WriteLn(Format('[INFO] Port %d is free. Proceeding...', [APort]));
      Exit;
    end;
    WriteLn(Format('[WAIT] Port %d is busy or in TIME_WAIT. Retrying in 3s...', [APort]));
    Sleep(3000);
  end;
end;

{ TServiceWrapper.RunWatchdog: Main watchdog loop that monitors and restarts failed processes. }
procedure TServiceWrapper.RunWatchdog;
var
  LogFile, Buffer: AnsiString;
  BytesRead: LongInt;
  i, ChatPort, EmbeddingPort, pIdx: Integer;
  RelativeModelPath, RelativeEmbeddingModelPath, PHPfullPath: AnsiString;
  PortsReserved: TStringList;
  {$IFDEF MSWINDOWS}
  Info: JOBOBJECT_EXTENDED_LIMIT_INFORMATION;
  {$ENDIF}
  procedure LogAtomic(const LogStr: AnsiString);
  var
    F: TextFile;
    Err: Integer;
  begin
    try
      if trim(LogStr) = '' then Exit;
      if trim(LogFile) = '' then Exit;
      AssignFile(F, LogFile);
      {$I-} // Disable IO errors
      try
        if FileExists(LogFile) then
          Append(F)
        else
        begin
          ForceDirectories(ExtractFilePath(LogFile));
          Rewrite(F);
        end;
        Err := IOResult;
        if Err = 0 then
        begin
          Write(F, LogStr);
          Err := IOResult;
        end;
      finally
        if Err = 0 then
          CloseFile(F);
        {$I+} // Re-enable IO errors
      end;
    except
      // Silent skip
    end;
  end;
begin
  Buffer := '';
  {$IFDEF MSWINDOWS}
  Info.BasicLimitInformation.LimitFlags := 0;
  FillChar(Info, SizeOf(Info), 0);
  {$ENDIF}
  LogFile := FAppDir + 'log' + PathDelim + 'wrapper.log';
  PHPfullPath := IncludeTrailingPathDelimiter(ExtractFilePath(FPhpBinary));
  ChatPort := 8080; // Default
  pIdx := FParams.IndexOf('--port');
  if not(pIdx = -1) and (pIdx < FParams.Count - 1) then
    ChatPort := StrToIntDef(trim(FParams[pIdx+1]), 8080);
  EmbeddingPort := 8081; // Default
  pIdx := FEmbeddingParams.IndexOf('--port');
  if not(pIdx = -1) and (pIdx < FEmbeddingParams.Count - 1) then
    EmbeddingPort := StrToIntDef(trim(FEmbeddingParams[pIdx+1]), 8081);
  FProcess := TProcess.Create(nil);
  FEmbeddingProcess := TProcess.Create(nil);
  FPhpProcess := TProcess.Create(nil);
  FWebserverProcess := TProcess.Create(nil);
  PortsReserved := TStringList.Create;
  PortsReserved.Sorted := true;
  try
    // Check if all ports are actually unique and free
    if not(FinalFModelFile = '') then
    begin
      if not(IsPortFree(ChatPort)) then
      begin
        ExitCode := 7;
        raise EWatchdogFatal.Create('[ERROR] LLM port is not free: ' + IntToStr(ChatPort));
      end;
      PortsReserved.Add(IntToStr(ChatPort));
    end;
    if not(FinalFEmbeddingModelFile = '') then
    begin
      if not(IsPortFree(EmbeddingPort)) then
      begin
        ExitCode := 8;
        raise EWatchdogFatal.Create('[ERROR] Embedding port is not free: ' + IntToStr(EmbeddingPort));
      end;
      if not(PortsReserved.IndexOf(IntToStr(EmbeddingPort)) = -1) then
      begin
        ExitCode := 13;
        raise EWatchdogFatal.Create('[ERROR] Embedding port already reserved: ' + IntToStr(EmbeddingPort));
      end;
      PortsReserved.Add(IntToStr(EmbeddingPort));
    end;
    if FProxyPort >= 1 then
    begin
      if not(IsPortFree(FProxyPort)) then
      begin
        ExitCode := 9;
        raise EWatchdogFatal.Create('[ERROR] Proxy port is not free: ' + IntToStr(FProxyPort));
      end;
      if not(PortsReserved.IndexOf(IntToStr(FProxyPort)) = -1) then
      begin
        ExitCode := 14;
        raise EWatchdogFatal.Create('[ERROR] Proxy port already reserved: ' + IntToStr(FProxyPort));
      end;
      PortsReserved.Add(IntToStr(FProxyPort));
    end;
    if not(IsPortFree(FPhpPort)) then
    begin
      ExitCode := 10;
      raise EWatchdogFatal.Create('[ERROR] PHP port is not free: ' + IntToStr(FPhpPort));
    end;
    if not(PortsReserved.IndexOf(IntToStr(FPhpPort)) = -1) then
    begin
      ExitCode := 15;
      raise EWatchdogFatal.Create('[ERROR] PHP port already reserved: ' + IntToStr(FPhpPort));
    end;
    PortsReserved.Add(IntToStr(FPhpPort));
    if not(IsPortFree(FWebserverHttpPort)) then
    begin
      ExitCode := 11;
      raise EWatchdogFatal.Create('[ERROR] HTTP port is not free: ' + IntToStr(FWebserverHttpPort));
    end;
    if not(PortsReserved.IndexOf(IntToStr(FWebserverHttpPort)) = -1) then
    begin
      ExitCode := 16;
      raise EWatchdogFatal.Create('[ERROR] HTTP port already reserved: ' + IntToStr(FWebserverHttpPort));
    end;
    PortsReserved.Add(IntToStr(FWebserverHttpPort));
    if not(IsPortFree(FWebserverHttpsPort)) then
    begin
      ExitCode := 12;
      raise EWatchdogFatal.Create('[ERROR] HTTPS port is not free: ' + IntToStr(FWebserverHttpsPort));
    end;
    if not(PortsReserved.IndexOf(IntToStr(FWebserverHttpsPort)) = -1) then
    begin
      ExitCode := 17;
      raise EWatchdogFatal.Create('[ERROR] HTTPS port already reserved: ' + IntToStr(FWebserverHttpsPort));
    end;
    PortsReserved.Add(IntToStr(FWebserverHttpsPort));
    if FUseLogFile then LogAtomic('--- [SESSION START: ' + DateTimeToStr(Now) + '] ---' + LineEnding);
    // Cross-platform setup: We want the binary name + params
    FProcess.Executable := FServerBinary;
    FEmbeddingProcess.Executable := FServerBinary;
    FProcess.CurrentDirectory := FLlamaDir;
    FEmbeddingProcess.CurrentDirectory := FLlamaDir;
    // Common Llama-server args: --model <path>
    if not(FinalFModelFile = '') then
    begin
      RelativeModelPath := ExtractRelativePath(FLlamaDir, FinalFModelFile);
      FProcess.Parameters.Add('--model');
      FProcess.Parameters.Add(RelativeModelPath);
      if not(FDeviceID = '') then
      begin
        FProcess.Parameters.Add('--device');
        FProcess.Parameters.Add(FDeviceID);
      end;
      if FProcess.Parameters.IndexOf('--alias') = -1 then
      begin
        FProcess.Parameters.Add('--alias');
        FProcess.Parameters.Add(UpperCase(Trim(ChangeFileExt(ExtractFileName(FinalFModelFile), ''))));
      end;
    end;
    if not(FinalFEmbeddingModelFile = '') then
    begin
      RelativeEmbeddingModelPath := ExtractRelativePath(FLlamaDir, FinalFEmbeddingModelFile);
      FEmbeddingProcess.Parameters.Add('--model');
      FEmbeddingProcess.Parameters.Add(RelativeEmbeddingModelPath);
      FEmbeddingProcess.Parameters.Add('--embedding');
      if not(FDeviceID = '') then
      begin
        FEmbeddingProcess.Parameters.Add('--device');
        FEmbeddingProcess.Parameters.Add(FDeviceID);
      end;
      if FEmbeddingProcess.Parameters.IndexOf('--alias') = -1 then
      begin
        FEmbeddingProcess.Parameters.Add('--alias');
        FEmbeddingProcess.Parameters.Add(UpperCase(Trim(ChangeFileExt(ExtractFileName(FinalFEmbeddingModelFile), ''))));
      end;
    end;
    // Add all other params one-by-one
    for i := 0 to FParams.Count - 1 do
    begin
      if trim(FParams[i]) = '' then continue;
      FProcess.Parameters.Add(FParams[i]);
    end;
    for i := 0 to FEmbeddingParams.Count - 1 do
    begin
      if trim(FEmbeddingParams[i]) = '' then continue;
      FEmbeddingProcess.Parameters.Add(FEmbeddingParams[i]);
    end;
    // PHP process
    FPhpProcess.Executable := FPhpBinary;
    FPhpProcess.CurrentDirectory := PHPfullPath;
    FPhpProcess.Parameters.Add('-b');
    FPhpProcess.Parameters.Add(FPhpHost + ':' + IntToStr(FPhpPort));
    FPhpProcess.Parameters.Add('-c');
    FPhpProcess.Parameters.Add(PHPfullPath + PathDelim + 'php.ini');
    FPhpProcess.Parameters.Add('-d');
    FPhpProcess.Parameters.Add('sys_temp_dir=' + FAppDir + 'temp');
    FPhpProcess.Parameters.Add('-d');
    FPhpProcess.Parameters.Add('upload_tmp_dir=' + FAppDir + 'temp' + PathDelim + 'php_upload');
    FPhpProcess.Parameters.Add('-d');
    FPhpProcess.Parameters.Add('session.save_path=' + FAppDir + 'temp' + PathDelim + 'php_session');
    FPhpProcess.Parameters.Add('-d');
    FPhpProcess.Parameters.Add('opcache.file_cache=' + FAppDir + 'temp' + PathDelim + 'opcache');
    if FUseLogFile then
    begin
      FPhpProcess.Parameters.Add('-d');
      FPhpProcess.Parameters.Add('error_log=' + FAppDir + 'log' + PathDelim + 'error.log');
      FPhpProcess.Parameters.Add('-d');
      FPhpProcess.Parameters.Add('log_errors=1');
    end;
    ForceDirectories(FAppDir + 'temp' + PathDelim + 'php_upload' + PathDelim);
    ForceDirectories(FAppDir + 'temp' + PathDelim + 'php_session' + PathDelim);
    ForceDirectories(FAppDir + 'temp' + PathDelim + 'opcache' + PathDelim);
    // Webserver process
    FWebserverProcess.Executable := FWebserverBinary;
    FWebserverProcess.CurrentDirectory := IncludeTrailingPathDelimiter(ExtractFilePath(FWebserverBinary));
    // Logs
    ForceDirectories(FAppDir + 'log' + PathDelim);
    // Watchdog Loop
    while not(Terminated) do
    begin
      try
        try
          // BULLETPROOF STEP: Wait here until the port is actually available
          if not(FinalFModelFile = '') and not(FProcess.Running) then WaitUntilPortFree(ChatPort);
          if not(FinalFEmbeddingModelFile = '') and not(FEmbeddingProcess.Running) then WaitUntilPortFree(EmbeddingPort);
          if FProxyPort >= 1 then WaitUntilPortFree(FProxyPort);
          if not(FPhpProcess.Running) then WaitUntilPortFree(FPhpPort);
          if not(FWebserverProcess.Running) then
          begin
            WaitUntilPortFree(FWebserverHttpPort);
            WaitUntilPortFree(FWebserverHttpsPort);
          end;
          if Terminated then break;
          // PRINT THE ACTUAL COMMAND FOR VERIFICATION
          if not(FinalFModelFile = '') then
            WriteLn('[INFO] Launching conversational server: ', FProcess.Executable, ' ', FProcess.Parameters.Text);
          if not(FinalFEmbeddingModelFile = '') then
            WriteLn('[INFO] Launching embedding server: ', FEmbeddingProcess.Executable, ' ', FEmbeddingProcess.Parameters.Text);
          WriteLn('[INFO] PHP FastCGI started on ', FPhpHost, ':', FPhpPort);
          WriteLn('[INFO] Web server started on ports ', FWebserverHttpPort, ' (HTTP) and ', FWebserverHttpsPort, ' (HTTPS)');
          if FUseLogFile then
          begin
            FProcess.Options := [poUsePipes, poStderrToOutput];
            FEmbeddingProcess.Options := [poUsePipes, poStderrToOutput];
            FPhpProcess.Options := [poUsePipes, poStderrToOutput];
            FWebserverProcess.Options := [poUsePipes, poStderrToOutput];
          end
          else
          begin
            FProcess.Options := [];
            FEmbeddingProcess.Options := [];
            FPhpProcess.Options := [];
            FWebserverProcess.Options := [];
          end;
          {$IFDEF MSWINDOWS}
          FProcess.Options := FProcess.Options + [poNewProcessGroup];
          FEmbeddingProcess.Options := FEmbeddingProcess.Options + [poNewProcessGroup];
          FPhpProcess.Options := FPhpProcess.Options + [poNewProcessGroup];
          FWebserverProcess.Options := FWebserverProcess.Options + [poNewProcessGroup];
          {$ENDIF}
          {$IFDEF UNIX}
          FProcess.Options := FProcess.Options + [poNewProcessGroup];
          FEmbeddingProcess.Options := FEmbeddingProcess.Options + [poNewProcessGroup];
          FPhpProcess.Options := FPhpProcess.Options + [poNewProcessGroup];
          FWebserverProcess.Options := FWebserverProcess.Options + [poNewProcessGroup];
          {$ENDIF}
          if not(FinalFModelFile = '') and not(FProcess.Running) then FProcess.Execute;
          if not(FinalFEmbeddingModelFile = '') and not(FEmbeddingProcess.Running) then FEmbeddingProcess.Execute;
          if not(FPhpProcess.Running) then FPhpProcess.Execute;
          if not(FWebserverProcess.Running) then FWebserverProcess.Execute;
          //Start Proxy Service if defined
          if FProxyPort >= 1 then StartProxy(FProxyPort, ChatPort, EmbeddingPort);
          {$IFDEF MSWINDOWS}
          if FJob = 0 then
          begin
            FJob := CreateJobObjectW(nil, nil);
            if not(FJob = 0) then
            begin
              FillChar(Info, SizeOf(Info), 0);
              Info.BasicLimitInformation.LimitFlags := JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
              SetInformationJobObject(
                FJob,
                JobObjectExtendedLimitInformation,
                @Info,
                SizeOf(Info));
            end;
          end;
          if not(FJob = 0) then
          begin
            if not(FinalFModelFile = '') then AssignProcessToJobObject(FJob, FProcess.Handle);
            if not(FinalFEmbeddingModelFile = '') then AssignProcessToJobObject(FJob, FEmbeddingProcess.Handle);
            AssignProcessToJobObject(FJob, FPhpProcess.Handle);
            AssignProcessToJobObject(FJob, FWebserverProcess.Handle);
          end;
          {$ENDIF}
          // While the process is running, we pump the output to the log file
          while not(Terminated) and (
            (not(FinalFModelFile = '') and FProcess.Running) or
            (not(FinalFEmbeddingModelFile = '') and FEmbeddingProcess.Running) or
            FPhpProcess.Running or FWebserverProcess.Running)
          do
          begin
            if FUseLogFile then
            begin
              // Check FProcess Output only if it's assigned and valid
              if Assigned(FProcess) then
              begin
                if poUsePipes in FProcess.Options then
                begin
                  if Assigned(FProcess.Output) then
                  begin
                    while FProcess.Output.NumBytesAvailable > 0 do
                    begin
                      SetLength(Buffer, FProcess.Output.NumBytesAvailable);
                      BytesRead := FProcess.Output.Read(Buffer[1], length(Buffer));
                      if (BytesRead > 0) then
                      begin
                        SetLength(Buffer, BytesRead);
                        LogAtomic(Buffer);
                      end;
                    end;
                  end;
                end;
              end;
              // Check FEmbeddingProcess Output
              if Assigned(FEmbeddingProcess) then
              begin
                if poUsePipes in FEmbeddingProcess.Options then
                begin
                  if Assigned(FEmbeddingProcess.Output) then
                  begin
                    while FEmbeddingProcess.Output.NumBytesAvailable > 0 do
                    begin
                      SetLength(Buffer, FEmbeddingProcess.Output.NumBytesAvailable);
                      BytesRead := FEmbeddingProcess.Output.Read(Buffer[1], length(Buffer));
                      if (BytesRead > 0) then
                      begin
                        SetLength(Buffer, BytesRead);
                        LogAtomic(Buffer);
                      end;
                    end;
                  end;
                end;
              end;
              // Check PHP process Output
              if Assigned(FPhpProcess) then
              begin
                if poUsePipes in FPhpProcess.Options then
                begin
                  if Assigned(FPhpProcess.Output) then
                  begin
                    while FPhpProcess.Output.NumBytesAvailable > 0 do
                    begin
                      SetLength(Buffer, FPhpProcess.Output.NumBytesAvailable);
                      BytesRead := FPhpProcess.Output.Read(Buffer[1], length(Buffer));
                      if (BytesRead > 0) then
                      begin
                        SetLength(Buffer, BytesRead);
                        LogAtomic(Buffer);
                      end;
                    end;
                  end;
                end;
              end;
              // Check web server process Output
              if Assigned(FWebserverProcess) then
              begin
                if poUsePipes in FWebserverProcess.Options then
                begin
                  if Assigned(FWebserverProcess.Output) then
                  begin
                    while FWebserverProcess.Output.NumBytesAvailable > 0 do
                    begin
                      SetLength(Buffer, FWebserverProcess.Output.NumBytesAvailable);
                      BytesRead := FWebserverProcess.Output.Read(Buffer[1], length(Buffer));
                      if (BytesRead > 0) then
                      begin
                        SetLength(Buffer, BytesRead);
                        LogAtomic(Buffer);
                      end;
                    end;
                  end;
                end;
              end;
            end;
            // BREAK the loop if ANY required process has died so the watchdog can restart it
            if not(FinalFModelFile = '') and not(FProcess.Running) then break;
            if not(FinalFEmbeddingModelFile = '') and not(FEmbeddingProcess.Running) then break;
            if not(FPhpProcess.Running) then break;
            if not(FWebserverProcess.Running) then break;
            Sleep(100);
          end;
          StopProxy; // Stop proxy when any of the services stop
          if not(FinalFModelFile = '') and not(FProcess.Running) then
            WriteLn('LLM server stopped (ExitCode: ' + IntToStr(FProcess.ExitCode) + '). Restarting in 3s...');
          if not(FinalFEmbeddingModelFile = '') and not(FEmbeddingProcess.Running) then
            WriteLn('Embedding server stopped (ExitCode: ' + IntToStr(FEmbeddingProcess.ExitCode) + '). Restarting in 3s...');
          if not(FPhpProcess.Running) then
            WriteLn('PHP FastCGI stopped (ExitCode: ' + IntToStr(FPhpProcess.ExitCode) + '). Restarting in 3s...');
          if not(FWebserverProcess.Running) then
            WriteLn('Web server stopped (ExitCode: ' + IntToStr(FWebserverProcess.ExitCode) + '). Restarting in 3s...');
          if not(Terminated) then Sleep(3000);
        except
          on x: Exception do
          begin
            WriteLn('Internal error: ' + x.Message + '. Restarting in 3s...');
            if not(Terminated) then Sleep(3000);
          end;
        end;
      finally
        StopProxy; // Final safety
      end;
    end;
  finally
    if Assigned(FProcess) then FreeAndNil(FProcess);
    if Assigned(FEmbeddingProcess) then FreeAndNil(FEmbeddingProcess);
    if Assigned(FPhpProcess) then FreeAndNil(FPhpProcess);
    if Assigned(FWebserverProcess) then FreeAndNil(FWebserverProcess);
    if Assigned(PortsReserved) then FreeAndNil(PortsReserved);
  end;
end;

{ TServiceWrapper.ShowHelp: Displays command-line help and usage information. }
procedure TServiceWrapper.ShowHelp;
var AppName: AnsiString;
begin
  AppName := trim(ExtractFileName(ExeName));
  WriteLn('');
  WriteLn(AppName + ' - Service Wrapper');
  WriteLn('');
  WriteLn('SYNOPSIS');
  WriteLn('  ' + AppName + ' [OPTIONS]');
  WriteLn('');
  WriteLn('DESCRIPTION');
  WriteLn('  A cross-platform wrapper service for managing LLM server processes,');
  WriteLn('  web servers, PHP FastCGI and API proxy with SSL/TLS support.');
  WriteLn('');
  WriteLn('OPTIONS');
  WriteLn('  --help');
  WriteLn('          Display this help message and exit.');
  WriteLn('');
  WriteLn('  --certonly [NAME]');
  WriteLn('          Generate SSL certificate only and exit. Optionally specify');
  WriteLn('          a custom certificate name (without extension). If no name is');
  WriteLn('          provided, uses the configured certificate path from the database.');
  WriteLn('');
  WriteLn('  --certonly=NAME');
  WriteLn('          Alternative syntax for specifying certificate name.');
  WriteLn('');
  WriteLn('CONFIGURATION');
  WriteLn('  The application reads configuration from:');
  WriteLn('  - Database for default server settings');
  WriteLn('  - JSON configuration file (config/wrapper.json) for overrides');
  WriteLn('');
  WriteLn('EXAMPLES');
  WriteLn('  ' + AppName + ' --help');
  WriteLn('          Show this help message.');
  WriteLn('');
  WriteLn('  ' + AppName + ' --certonly');
  WriteLn('          Generate SSL certificate using configured paths.');
  WriteLn('');
  WriteLn('  ' + AppName + ' --certonly=mycert');
  WriteLn('          Generate SSL certificate as mycert.crt and mycert.key.');
  WriteLn('');
  WriteLn('EXIT CODES');
  WriteLn('  0      Success');
  WriteLn('  1      Error/Failure');
  WriteLn('');
end;

{ TServiceWrapper.Cleanup: Releases all resources and terminates child processes gracefully. }
procedure TServiceWrapper.Cleanup;
var
  CheckpointConn: TSQLite3Connection;
  CheckpointTrans: TSQLTransaction;
  {$IFDEF UNIX}
  LockFile: AnsiString;
  {$ENDIF}
begin
  StopProxy; // Ensure proxy is killed before everything else
  {$IFDEF MSWINDOWS}
  if not(FMutex = 0) then
  begin
    ReleaseMutex(FMutex);
    CloseHandle(FMutex);
    FMutex := 0;
  end;
  {$ENDIF}
  {$IFDEF UNIX}
  if not(FLockFileHandle = -1) then
  begin
    fpFlock(FLockFileHandle, LOCK_UN); // Unlock
    FpClose(FLockFileHandle);
    FLockFileHandle := -1;
    LockFile := INSTANCE_PREFIX + FInstanceID + '.pid';
    if FileExists(LockFile) then
      fpUnlink(PChar(LockFile));
  end;
  {$ENDIF}
  try
    // Use ProcessHandle (Windows) or ProcessID (Unix) to check existence
    if Assigned(FProcess) and not(FProcess.ProcessHandle = 0) then
    begin
      {$IFDEF MSWINDOWS}
      // Direct API call is more reliable than calling taskkill
      TerminateProcess(FProcess.ProcessHandle, 0);
      WaitForSingleObject(FProcess.ProcessHandle, 1000);
      {$ENDIF}
      {$IFDEF UNIX}
      // The minus sign kills the entire process group
      fpKill(-FProcess.ProcessID, SIGKILL);
      {$ENDIF}
    end;
    if Assigned(FEmbeddingProcess) and not(FEmbeddingProcess.ProcessHandle = 0) then
    begin
      {$IFDEF MSWINDOWS}
      // Direct API call is more reliable than calling taskkill
      TerminateProcess(FEmbeddingProcess.ProcessHandle, 0);
      WaitForSingleObject(FEmbeddingProcess.ProcessHandle, 1000);
      {$ENDIF}
      {$IFDEF UNIX}
      // The minus sign kills the entire process group
      fpKill(-FEmbeddingProcess.ProcessID, SIGKILL);
      {$ENDIF}
    end;
    if Assigned(FPhpProcess) and not(FPhpProcess.ProcessHandle = 0) then
    begin
      {$IFDEF MSWINDOWS}
      TerminateProcess(FPhpProcess.ProcessHandle, 0);
      WaitForSingleObject(FPhpProcess.ProcessHandle, 1000);
      {$ENDIF}
      {$IFDEF UNIX}
      fpKill(-FPhpProcess.ProcessID, SIGKILL);
      {$ENDIF}
    end;
    if Assigned(FWebserverProcess) and not(FWebserverProcess.ProcessHandle = 0) then
    begin
      {$IFDEF MSWINDOWS}
      TerminateProcess(FWebserverProcess.ProcessHandle, 0);
      WaitForSingleObject(FWebserverProcess.ProcessHandle, 1000);
      {$ENDIF}
      {$IFDEF UNIX}
      fpKill(-FWebserverProcess.ProcessID, SIGKILL);
      {$ENDIF}
    end;
  finally
    // Free the process object last
    if assigned(FProcess) then FreeAndNil(FProcess);
    if assigned(FEmbeddingProcess) then FreeAndNil(FEmbeddingProcess);
    if assigned(FPhpProcess) then FreeAndNil(FPhpProcess);
    if assigned(FWebserverProcess) then FreeAndNil(FWebserverProcess);
    // Be careful: if Cleanup is called twice, don't free these again
    if Assigned(FParams) then FreeAndNil(FParams);
    if Assigned(FEmbeddingParams) then FreeAndNil(FEmbeddingParams);
    // Close query properly
    if Assigned(FQuery) then
    begin
      try
        if FQuery.Active then FQuery.Close;
      except
        // Silent skip
      end;
      FreeAndNil(FQuery);
    end;
    // Close transaction properly
    if Assigned(FTrans) then
    begin
      try
        if FTrans.Active then FTrans.Commit;
      except
        try
          if FTrans.Active then FTrans.Rollback;
        except
          // Silent skip
        end;
      end;
      FreeAndNil(FTrans);
    end;
    // Now close connection
    if Assigned(FConn) then
    begin
      try
        if FConn.Connected then FConn.Close;
      except
        // Silent skip
      end;
      FreeAndNil(FConn);
    end;
    // Checkpoint and remove WAL files if they exist (after all connections are closed)
    if FileExists(DBPathWAL) then
    begin
      CheckpointConn := nil;
      CheckpointTrans := nil;
      try
        CheckpointConn := TSQLite3Connection.Create(nil);
        CheckpointTrans := TSQLTransaction.Create(CheckpointConn);
        CheckpointConn.Transaction := CheckpointTrans;
        CheckpointConn.DatabaseName := DBPath;
        CheckpointConn.Open;
        CheckpointConn.ExecuteDirect('PRAGMA busy_timeout = 500');
        CheckpointConn.ExecuteDirect('PRAGMA wal_checkpoint(TRUNCATE)');
      except
        // Silently skip if DB is locked or error
      end;
      if Assigned(CheckpointTrans) then
      begin
        try
          if CheckpointTrans.Active then CheckpointTrans.Commit;
        except
          // Silent skip
        end;
        FreeAndNil(CheckpointTrans);
      end;
      if Assigned(CheckpointConn) then
      begin
        try
          if CheckpointConn.Connected then CheckpointConn.Close;
        except
          // Silent skip
        end;
        FreeAndNil(CheckpointConn);
      end;
      try
        if FileExists(DBPathWAL) then DeleteFile(DBPathWAL);
        if FileExists(DBPathSHM) then DeleteFile(DBPathSHM);
      except
        // Ignore deletion errors
      end;
    end;
    // Note: WAL/SHM files are managed by SQLite automatically under normal operation.
  end;
end;

{$IFDEF UNIX}
{ DoSigInt: Signal handler for SIGINT/SIGTERM signals on Unix platforms. }
procedure DoSigInt(Sig: LongInt); cdecl;
begin
  // This tells TCustomApplication to stop
  if Assigned(Application) then
    Application.Terminate;
end;
{$ENDIF}

{ TServiceWrapper.DoRun: Main application entry point that processes command-line arguments and starts services. }
procedure TServiceWrapper.DoRun;
var
  i: Integer;
  CertName, CertFile, KeyFile: string;
begin
  ExitCode := 0;
  // Check for --help flag before any heavy initialization
  for i := 1 to ParamCount do
  begin
    if not(ParamStr(i) = '--help') then Continue;
    ShowHelp;
    Terminate;
    Exit;
  end;
  {$IFDEF UNIX}
  // Hook CTRL+C (SIGINT) and SIGTERM
  fpSignal(SIGINT, @DoSigInt);
  fpSignal(SIGTERM, @DoSigInt);
  {$ENDIF}
  //Disable output buffering to prevent console from blocking server operations
  //FPC flushes after every write/writeln on Windows, set FlushFunc to nil to disable
  try
    Textrec(Output).FlushFunc := nil;
    Textrec(StdErr).FlushFunc := nil;
  except
    on E: Exception do
    begin
      // Non-fatal: continue without disabling buffering
      WriteLn(StdErr, Format('[%s] WARNING: Could not disable output buffering: %s', [DateTimeToStr(Now), E.Message]));
    end;
  end;
  if not(CheckSingleInstance) then
  begin
    WriteLn('ERROR: another instance of Llama Service Wrapper is already running! Exiting...');
    ExitCode := 2;
    Terminate;
    Exit;
  end;
  // Check for --certonly [name] flag before any heavy initialization
  IsCertOnlyMode := False;
  CertName := '';
  for i := 1 to ParamCount do
  begin
    if ParamStr(i) = '--certonly' then
    begin
      IsCertOnlyMode := True;
      // Check if next arg exists and is not another option
      if (i < ParamCount) and not(ParamStr(i + 1) = '') and not(ParamStr(i + 1)[1] = '-') then
        CertName := trim(ParamStr(i + 1));
      Break;
    end;
    if Pos('--certonly=', ParamStr(i)) = 1 then
    begin
      IsCertOnlyMode := True;
      CertName := trim(Copy(ParamStr(i), Length('--certonly=') + 1, MaxInt));
      Break;
    end;
  end;
  // Initialize
  InitPaths;
  SetupDatabase;
  LoadConfiguration;
  // Close database after config loaded - no longer needed
  if Assigned(FQuery) then
  begin
    try
      if FQuery.Active then FQuery.Close;
    except
      // Silent skip
    end;
    FreeAndNil(FQuery);
  end;
  if Assigned(FTrans) then
  begin
    try
      if FTrans.Active then FTrans.Commit;
    except
      try
        if FTrans.Active then FTrans.Rollback;
      except
        // Silent skip
      end;
    end;
    FreeAndNil(FTrans);
  end;
  if Assigned(FConn) then
  begin
    try
      if FConn.Connected then FConn.Close;
    except
      // Silent skip
    end;
    FreeAndNil(FConn);
  end;
  // Clean up any WAL/SHM files after closing DB
  {if FileExists(DBPathWAL) then DeleteFile(DBPathWAL);
  if FileExists(DBPathSHM) then DeleteFile(DBPathSHM);}
  // SSL certificate-only mode
  if IsCertOnlyMode then
  begin
    // Determine certificate and key file paths
    if not(CertName = '') then CertName := trim(ExtractFileName(CertName));
    if not(CertName = '') then
    begin
      CertFile := FSSLcertDir + CertName + '.crt';
      KeyFile  := FSSLcertDir + CertName + '.key';
    end
    else
    begin
      // Use default certificate and key file paths (overwrite)
      CertFile := FSSLcertificate;
      KeyFile := FSSLkey;
    end;
    // Generate and exit with appropriate code
    try
      GenerateSslCertificate(CertFile, KeyFile);
      WriteLn('[INFO] SSL certificate generated successfully.');
      Cleanup;
      Halt(0);
    except
      on E: Exception do
      begin
        WriteLn(StdErr, 'ERROR: ', E.Message);
        Cleanup;
        Halt(3);
      end;
    end;
    WriteLn(StdErr, 'ERROR: internal error at SSL certificate generation!');
    Cleanup;
    Halt(4);
  end;
  //Normal (server) mode
  try
    try
      RunWatchdog;
    except
      on E: EWatchdogFatal do
      begin
        // Log the error to StdErr so the service manager sees it
        WriteLn(StdErr, Format('[%s] FATAL STARTUP ERROR: %s', [DateTimeToStr(Now), E.Message]));
        if ExitCode = 0 then ExitCode := 5;
      end;
      on E: Exception do
      begin
        // Use standard error output for fatal issues
        WriteLn(StdErr, Format('[%s] FATAL ERROR: %s', [DateTimeToStr(Now), E.Message]));
        ExitCode := 6;
      end;
    end;
  finally
    // This ensures that even if SetupDatabase fails,
    // we still try to free whatever was allocated.
    Cleanup;
    Terminate;
  end;
end;

{ TServiceWrapper.Create: Initializes the service wrapper application. }
constructor TServiceWrapper.Create(TheOwner: TComponent);
begin
  inherited Create(TheOwner);
  StopOnException := True;
  {$IFDEF MSWINDOWS}
  FJob := 0;
  {$ENDIF}
end;

{ TServiceWrapper.Destroy: Frees the service wrapper and all associated resources. }
destructor TServiceWrapper.Destroy;
begin
  Cleanup;
  inherited Destroy;
end;

{ Application entry point: Creates and runs the TServiceWrapper application. }
var Application: TServiceWrapper;

{$R *.res}

begin
  Application := TServiceWrapper.Create(nil);
  Application.OnException := @Application.HandleGlobalException;
  Application.Title := 'Llama Service Wrapper';
  Application.Run;
  Application.Free;
end.
