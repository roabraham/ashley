{ Main form unit for the LLM Service Manager application. Provides UI controls for service management. }
unit main_form;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, Menus, ExtCtrls,
  ComCtrls, LCLIntf, LCLType, md5, settings_form, process, about_form,
  progress_form,
  {$IFDEF MSWINDOWS}
  Windows, jwatlhelp32;
  {$ENDIF}
  {$IFDEF UNIX}
  BaseUnix;
  {$ENDIF}

{$IFDEF MSWINDOWS}
{ Platform-specific instance lock prefix for preventing multiple application instances. }
const INSTANCE_PREFIX = 'Global\llama_service_manager_';
{$ENDIF}
{$IFDEF UNIX}
{ Platform-specific instance lock prefix for preventing multiple application instances. }
const INSTANCE_PREFIX = '/tmp/llama_service_manager_';
{$ENDIF}

type

  { TMainForm: main application form with menu, status bar, and system tray icon. Manages LLM service lifecycle. }
  TMainForm = class(TForm)
    { Application banner image displayed on the main form. }
    MainFormImage: TImage;
    { Main application menu bar. }
    MainMenu: TMainMenu;
    { Context menu shown when clicking the system tray icon. }
    MainPopupMenu: TPopupMenu;
    { Exit/close option in the system tray popup menu. }
    ExitPopupMenu: TMenuItem;
    { Process component for running the LLM service wrapper. }
    LLMserverProcess: TProcess;
    { Help menu section in the main menu bar. }
    HelpMenu: TMenuItem;
    { About dialog option in the main menu. }
    AboutMenu: TMenuItem;
    { SSL certificate generation option in the main menu. }
    GenerateCertificateMenu: TMenuItem;
    { SSL certificate generation option in the system tray popup menu. }
    GenerateCertificatePopupMenu: TMenuItem;
    { Help options in the system tray popup menu. }
    HelpPopupMenu: TMenuItem;
    { About dialog option in the system tray popup menu. }
    AboutPopupMenu: TMenuItem;
    { Process component for running embedding vector generation. }
    EmbeddingGenerationProcess: TProcess;
    { Embedding generation option in the main menu. }
    GenerateEmbeddingsMenu: TMenuItem;
    { Embedding generation option in the system tray popup menu. }
    GenerateEmbeddingsPopupMenu: TMenuItem;
    { Database documentation option in the main menu. }
    DBdocMenu: TMenuItem;
    { Database documentation option in the system tray popup menu. }
    DBdocPopupMenu: TMenuItem;
    { Frontend documentation option in the main menu. }
    FrontendDocMenu: TMenuItem;
    { Frontend documentation option in the system tray popup menu. }
    FrontendDocPopupMenu: TMenuItem;
    { Service Manager documentation option in the system tray popup menu. }
    ServiceManagerDocPopupMenu: TMenuItem;
    { Service Manager documentation option in the main menu. }
    ServiceManagerDocMenu: TMenuItem;
    { Visual separator in the popup menu. }
    Separator12: TMenuItem;
    { User manual option in the system tray popup menu. }
    UserManualPopupMenu: TMenuItem;
    { Visual separator in the popup menu. }
    Separator11: TMenuItem;
    { User manual option in the main menu. }
    UserManualMenu: TMenuItem;
    { Personality database documentation option in the system tray popup menu. }
    PersonalityDBdocPopupMenu: TMenuItem;
    { Wrapper database documentation option in the system tray popup menu. }
    WrapperDBdocPopupMenu: TMenuItem;
    { Visual separator in the popup menu. }
    Separator10: TMenuItem;
    { Personality database documentation option in the main menu. }
    PersonalityDBdocMenu: TMenuItem;
    { Wrapper database documentation option in the main menu. }
    WrapperDBdocMenu: TMenuItem;
    { Visual separator in the popup menu. }
    Separator9: TMenuItem;
    { Process component for running SSL certificate generation. }
    SSLcertificateProcess: TProcess;
    { Visual separator in the popup menu. }
    Separator3: TMenuItem;
    { Settings option in the system tray popup menu. }
    SettingsPopupMenu: TMenuItem;
    { Tools section in the system tray popup menu. }
    ToolsPopupMenu: TMenuItem;
    { Open Web UI option in the main menu. }
    OpenWebUImenu: TMenuItem;
    { Open Web UI option in the system tray popup menu. }
    OpenWebUIpopupMenu: TMenuItem;
    { Visual separator in the popup menu. }
    Separator7: TMenuItem;
    { Visual separator in the popup menu. }
    Separator8: TMenuItem;
    { Process component for running the Web UI client. }
    WebUIprocess: TProcess;
    { Restart LLM service option in the system tray popup menu. }
    RestartLLMservicePopupMenu: TMenuItem;
    { Visual separator in the popup menu. }
    Separator6: TMenuItem;
    { Stop LLM service option in the system tray popup menu. }
    StopLLMservicePopupMenu: TMenuItem;
    { Start LLM service option in the system tray popup menu. }
    StartLLMservicePopupMenu: TMenuItem;
    { Visual separator in the popup menu. }
    Separator5: TMenuItem;
    { Service management section in the system tray popup menu. }
    ServicePopupMenu: TMenuItem;
    { Restart LLM service option in the main menu. }
    RestartLLMserviceMenu: TMenuItem;
    { Visual separator in the popup menu. }
    Separator4: TMenuItem;
    { Stop LLM service option in the main menu. }
    StopLLMserviceMenu: TMenuItem;
    { Start LLM service option in the main menu. }
    StartLLMserviceMenu: TMenuItem;
    { Visual separator in the main menu. }
    Separator2: TMenuItem;
    { Settings option in the main menu. }
    SettingsMenu: TMenuItem;
    { Timer component for periodic service status checks. }
    ProcessTimer: TTimer;
    { Tools menu section in the main menu bar. }
    ToolsMenu: TMenuItem;
    { Minimize to system tray option in the main menu. }
    MinimizeMenu: TMenuItem;
    { Show main window option in the system tray popup menu. }
    OpenServiceManagerPopupMenu: TMenuItem;
    { Visual separator in the popup menu. }
    Separator1: TMenuItem;
    { Service management section in the main menu bar. }
    ServiceMenu: TMenuItem;
    { Exit application option in the main menu. }
    ExitMenu: TMenuItem;
    { Status bar displaying application state and messages. }
    MainStatusBar: TStatusBar;
    { System tray icon for background operation. }
    SystemTrayIcon: TTrayIcon;
    { Opens frontend documentation from the main menu. }
    procedure FrontendDocMenuClick(Sender: TObject);
    { Opens frontend documentation from the popup menu. }
    procedure FrontendDocPopupMenuClick(Sender: TObject);
    { Opens a file using the system default application. }
    function OpenFile(const filename: AnsiString): Boolean;
    { Displays the about dialog from the main menu. }
    procedure AboutMenuClick(Sender: TObject);
    { Displays the about dialog from the popup menu. }
    procedure AboutPopupMenuClick(Sender: TObject);
    { Handles main form destruction for cleanup. }
    procedure FormDestroy(Sender: TObject);
    { Generates certificate from main menu. }
    procedure GenerateCertificateMenuClick(Sender: TObject);
    { Generates certificate from popup menu. }
    procedure GenerateCertificatePopupMenuClick(Sender: TObject);
    { Generates embeddings from popup menu. }
    procedure GenerateEmbeddingsPopupMenuClick(Sender: TObject);
    { Generates embeddings from main menu. }
    procedure GenerateEmbeddingsMenuClick(Sender: TObject);
    { Opens personality database documentation from main menu. }
    procedure PersonalityDBdocMenuClick(Sender: TObject);
    { Opens personality database documentation from popup menu. }
    procedure PersonalityDBdocPopupMenuClick(Sender: TObject);
    { Opens Service Manager documentation from main menu. }
    procedure ServiceManagerDocMenuClick(Sender: TObject);
    { Opens Service Manager documentation from popup menu. }
    procedure ServiceManagerDocPopupMenuClick(Sender: TObject);
    { Opens settings form from popup menu. }
    procedure SettingsPopupMenuClick(Sender: TObject);
    { Opens Web UI from main menu. }
    procedure OpenWebUImenuClick(Sender: TObject);
    { Opens Web UI from popup menu. }
    procedure OpenWebUIpopupMenuClick(Sender: TObject);
    { Periodic timer for service status updates. }
    procedure ProcessTimerTimer(Sender: TObject);
    { Restarts LLM service from popup menu. }
    procedure RestartLLMservicePopupMenuClick(Sender: TObject);
    { Displays appropriate error message based on error code from LLM service. }
    procedure ProcessLLMserviceError(ErrorCode: integer);
    { Controls the LLM service (START, STOP, RESTART). }
    procedure LLMserviceControl(ServiceAction: string);
    { Controls the LLM service with user confirmation dialog. }
    procedure LLMserviceControlQuery(ServiceAction: string);
    { Generates embedding vectors using the configured PHP process. }
    procedure GenerateEmbeddings;
    { Generates SSL certificate using the configured wrapper process. }
    procedure GenerateSSLcertificate;
    { Starts the Web UI client application. }
    procedure startWebUI;
    { Restarts LLM service from main menu. }
    procedure RestartLLMserviceMenuClick(Sender: TObject);
    { Opens the settings form and saves configuration if confirmed. }
    procedure SaveConfigData;
    { Closes application from main menu. }
    procedure ExitMenuClick(Sender: TObject);
    { Closes application from popup menu. }
    procedure ExitPopupMenuClick(Sender: TObject);
    { Handles close query with confirmation dialog. }
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    { Handles main form creation and initialization. }
    procedure FormCreate(Sender: TObject);
    { Minimizes application to system tray. }
    procedure FormWindowStateChange(Sender: TObject);
    { Minimizes to system tray from menu. }
    procedure MinimizeMenuClick(Sender: TObject);
    { Opens application from system tray popup. }
    procedure OpenServiceManagerPopupMenuClick(Sender: TObject);
    { Opens settings from main menu. }
    procedure SettingsMenuClick(Sender: TObject);
    { Starts LLM service from main menu. }
    procedure StartLLMserviceMenuClick(Sender: TObject);
    { Starts LLM service from popup menu. }
    procedure StartLLMservicePopupMenuClick(Sender: TObject);
    { Stops LLM service from main menu. }
    procedure StopLLMserviceMenuClick(Sender: TObject);
    { Stops LLM service from popup menu. }
    procedure StopLLMservicePopupMenuClick(Sender: TObject);
    { Handles system tray icon mouse down event. }
    procedure SystemTrayIconMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    { Opens user manual from main menu. }
    procedure UserManualMenuClick(Sender: TObject);
    { Opens user manual from popup menu. }
    procedure UserManualPopupMenuClick(Sender: TObject);
    { Opens wrapper database documentation from main menu. }
    procedure WrapperDBdocMenuClick(Sender: TObject);
    { Opens wrapper database documentation from popup menu. }
    procedure WrapperDBdocPopupMenuClick(Sender: TObject);
  protected
    {$IFDEF MSWINDOWS}
    { Windows mutex handle used for single-instance enforcement. }
    FMutex: THandle;
    {$ENDIF}
    {$IFDEF UNIX}
    { UNIX file lock handle used for single-instance enforcement. }
    FLockFileHandle: Integer;
    {$ENDIF}
    { Flag to trigger a delayed configuration dialog and service start on first run. }
    DelayedStartUpQuery: Boolean;
    { Checks if only one instance of the application is running. }
    function CheckSingleInstance: Boolean;
    { Releases the instance lock on application shutdown. }
    procedure ReleaseInstanceLock;
  public
    { Path to the application directory. }
    appdir: AnsiString;
    { Path to the configuration directory. }
    configdir: AnsiString;
    { Full path to the wrapper configuration JSON file. }
    wrapperConfigFile: AnsiString;
    { Path to the web server directory. }
    webserverDir: AnsiString;
    { Path to the documentation directory. }
    docDir: AnsiString;
    { Path to the developer documentation directory. }
    devDocDir: AnsiString;
    { Full path to the wrapper database documentation PDF. }
    wrapperDBdocFile: AnsiString;
    { Full path to the personality database documentation PDF. }
    personalityDBdocFile: AnsiString;
    { Full path to the frontend documentation HTML file. }
    frontendDocFile: AnsiString;
    { Full path to the service manager documentation HTML file. }
    serviceManagerDocFile: AnsiString;
    { Full path to the user manual PDF. }
    userManualFile: AnsiString;
  end;

{ Global instance of the main form. }
var
  MainForm: TMainForm;

implementation

{$IFDEF MSWINDOWS}
{ Recursively terminates a process and all its child processes. }
procedure KillProcessTree(const AProcessID: DWORD);
var
  hSnap: THandle;
  Proc: TPROCESSENTRY32;
begin
  try
    hSnap := CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if hSnap = INVALID_HANDLE_VALUE then Exit;
    Proc.dwSize := SizeOf(Proc);
    if Process32First(hSnap, Proc) then
    repeat
      if Proc.th32ParentProcessID = AProcessID then
        KillProcessTree(Proc.th32ProcessID);
    until not(Process32Next(hSnap, Proc));
    CloseHandle(hSnap);
    hSnap := OpenProcess(PROCESS_TERMINATE, False, AProcessID);
    if not(hSnap = 0) then
    begin
      TerminateProcess(hSnap, 0);
      CloseHandle(hSnap);
    end;
  except
    on x: Exception do
      MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);
  end;
end;
{$ENDIF}

{$R *.lfm}

{ TMainForm }

//Check if only 1 instance is running
function TMainForm.CheckSingleInstance: Boolean;
var
  MutexName: string;
  InstanceID: string;
  {$IFDEF UNIX}
  LockFile: AnsiString;
  {$ENDIF}
begin
  Result := true;
  try
    InstanceID := LowerCase(MD5Print(MD5String(trim(ParamStr(0)))));
    {$IFDEF MSWINDOWS}
    MutexName := INSTANCE_PREFIX + InstanceID;
    FMutex := CreateMutex(nil, False, PChar(MutexName));
    if not(FMutex = 0) and (GetLastError = ERROR_ALREADY_EXISTS) then
    begin
      CloseHandle(FMutex);
      FMutex := 0;
      Result := false;
      Exit;
    end;
    {$ENDIF}
    {$IFDEF UNIX}
    LockFile := INSTANCE_PREFIX + InstanceID + '.lock';
    FLockFileHandle := fpOpen(LockFile, O_CREAT or O_RDWR, 438);
    if FLockFileHandle = -1 then
    begin
      Result := false;
      Exit;
    end;
    if not(fpFlock(FLockFileHandle, LOCK_EX or LOCK_NB) = 0) then
    begin
      fpClose(FLockFileHandle);
      FLockFileHandle := -1;
      Result := false;
      Exit;
    end;
    {$ENDIF}
  except
    on x: Exception do
    begin
      Result := false;
      MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);
    end;
  end;
end;

//Open File (used for opening documentation)
function TMainForm.OpenFile(const filename: AnsiString): Boolean;
var filenameFixed: AnsiString;
begin
  Result := false;
  try
    filenameFixed := trim(filename);
    if not(length(filenameFixed) >= 1) then
    begin
      MainStatusBar.SimpleText := 'Filename not specified!';
      MessageDlg('Error', MainStatusBar.SimpleText, mtError, [mbOK], 0);
      Exit;
    end;
    if not(FileExists(filenameFixed)) then
    begin
      MainStatusBar.SimpleText := 'File does not exist: ' + filenameFixed;
      MessageDlg('Error', MainStatusBar.SimpleText, mtError, [mbOK], 0);
      Exit;
    end;
    OpenDocument(filenameFixed);
    MainStatusBar.SimpleText := 'Document opened: ' + filenameFixed;
    Result := true;
  except
    on x: Exception do
    begin
      MainStatusBar.SimpleText := 'Internal error: ' + x.Message;
      MessageDlg('Error', MainStatusBar.SimpleText, mtError, [mbOK], 0);
    end;
  end;
end;

//Open frontend documentation
procedure TMainForm.FrontendDocMenuClick(Sender: TObject);
begin
  OpenFile(frontendDocFile);
end;

//Open frontend documentation
procedure TMainForm.FrontendDocPopupMenuClick(Sender: TObject);
begin
  OpenFile(frontendDocFile);
end;

//Release lock
procedure TMainForm.ReleaseInstanceLock;
{$IFDEF UNIX}
var
  InstanceID: string;
  LockFile: AnsiString;
{$ENDIF}
begin
  try
    {$IFDEF MSWINDOWS}
    if not(FMutex = 0) then
    begin
      ReleaseMutex(FMutex);
      CloseHandle(FMutex);
      FMutex := 0;
      Exit;
    end;
    {$ENDIF}
    {$IFDEF UNIX}
    if FLockFileHandle = -1 then Exit;
    fpFlock(FLockFileHandle, LOCK_UN);
    fpClose(FLockFileHandle);
    FLockFileHandle := -1;
    InstanceID := LowerCase(MD5Print(MD5String(trim(ParamStr(0)))));
    LockFile := INSTANCE_PREFIX + InstanceID + '.lock';
    if FileExists(LockFile) then
      fpUnlink(PChar(LockFile));
    {$ENDIF}
  except
    on x: Exception do
      MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);
  end;
end;

//Config Data Save wrapper
procedure TMainForm.SaveConfigData;
var LLMserverProcessPreviousState: boolean;
begin
  try
    if SettingsForm.IsVisible then Exit;
    SettingsForm.configDataSaved := false;
    LLMserverProcessPreviousState := LLMserverProcess.Running;
    repeat
      SettingsForm.MainLLMserverProcessRunning := LLMserverProcess.Running;
      SettingsForm.WebUIprocessRunning := WebUIprocess.Running;
      if SettingsForm.showModal = mrOk then SettingsForm.SaveConfigData;
    until not(SettingsForm.saveSettingsError);
    if not(SettingsForm.configDataSaved) then Exit;
    MainStatusBar.SimpleText := 'Config data saved.';
    if LLMserverProcessPreviousState then
    begin
      {$IFDEF DEBUG}
      MainStatusBar.SimpleText := 'Service restart skipped.';
      {$ELSE}
      MainStatusBar.SimpleText := 'Config changed, restarting services...';
      LLMserviceControl('RESTART');
      {$ENDIF}
    end;
  except
    on x: Exception do
    begin
      MainStatusBar.SimpleText := 'Internal error: ' + x.Message;
      MessageDlg('Error', MainStatusBar.SimpleText, mtError, [mbOK], 0);
    end;
  end;
end;

//Process service errors
procedure TMainForm.ProcessLLMserviceError(ErrorCode: integer);
begin
  try
    case ErrorCode of
      0: MainStatusBar.SimpleText := 'Service stopped immediately after start!';
      1: MainStatusBar.SimpleText := 'Error: Global fatal exception occurred!';
      2: MainStatusBar.SimpleText := 'Error: Another instance is already running!';
      3: MainStatusBar.SimpleText := 'Error: Database connection failed!';
      4: MainStatusBar.SimpleText := 'Error: Failed to load configuration!';
      5: MainStatusBar.SimpleText := 'Error: Fatal startup error (Watchdog)!';
      6: MainStatusBar.SimpleText := 'Error: Unhandled system exception!';
      7: MainStatusBar.SimpleText := 'Error: LLM port is not free!';
      8: MainStatusBar.SimpleText := 'Error: Embedding port is not free!';
      9: MainStatusBar.SimpleText := 'Error: Proxy port is not free!';
      10: MainStatusBar.SimpleText := 'Error: PHP port is not free!';
      11: MainStatusBar.SimpleText := 'Error: HTTP port is not free!';
      12: MainStatusBar.SimpleText := 'Error: HTTPS port is not free!';
      13: MainStatusBar.SimpleText := 'Error: Embedding port already reserved!';
      14: MainStatusBar.SimpleText := 'Error: Proxy port already reserved!';
      15: MainStatusBar.SimpleText := 'Error: PHP port already reserved!';
      16: MainStatusBar.SimpleText := 'Error: HTTP port already reserved!';
      17: MainStatusBar.SimpleText := 'Error: HTTPS port already reserved!';
      else MainStatusBar.SimpleText := 'Internal Server Error (Code: ' + IntToStr(ErrorCode) + ')!';
    end;
    MessageDlg('Error', MainStatusBar.SimpleText, mtError, [mbOK], 0);
  except
    on x: Exception do
    begin
      MainStatusBar.SimpleText := 'Internal error: ' + x.Message;
      MessageDlg('Error', MainStatusBar.SimpleText, mtError, [mbOK], 0);
    end;
  end;
end;

//Service Controller
procedure TMainForm.LLMserviceControl(ServiceAction: string);
var
  ActionFixed: string;
  WrapperPath: string;
  WaitCount: Integer;
  PForm: TProgressForm;
begin
  PForm := nil;
  try
    try
      //Check action parameter
      ActionFixed := UpperCase(trim(ServiceAction));
      if not(length(ActionFixed)>0) then
      begin
        MainStatusBar.SimpleText := 'Action not specified!';
        MessageDlg('Error', MainStatusBar.SimpleText, mtError, [mbOK], 0);
        Exit;
      end;
      //Check wrapper binary
      {$IFDEF WINDOWS}
      WrapperPath := appdir + 'wrapper.exe';
      {$ELSE}
      WrapperPath := appdir + 'wrapper';
      {$ENDIF}
      //Start services
      if ActionFixed = 'START' then
      begin
        if LLMserverProcess.Running then
        begin
          MainStatusBar.SimpleText := 'The services are already running.';
          MessageDlg('Warning', MainStatusBar.SimpleText, mtWarning, [mbOK], 0);
          Exit;
        end;
        if SSLcertificateProcess.Running then
        begin
          MainStatusBar.SimpleText := 'Cannot start until SSL certificate generation is finished!';
          MessageDlg('Error', MainStatusBar.SimpleText, mtError, [mbOK], 0);
          Exit;
        end;
        chdir(appdir);
        if not(FileExists(WrapperPath)) then
        begin
          MainStatusBar.SimpleText := 'Wrapper binary not found: ' + WrapperPath;
          MessageDlg('Error', MainStatusBar.SimpleText, mtError, [mbOK], 0);
          Exit;
        end;
        PForm := TProgressForm.Create(Application);
        PForm.ProgressTimer.Enabled := true;
        PForm.Show;
        Application.ProcessMessages;
        LLMserverProcess.Active := false;
        LLMserverProcess.Parameters.Clear;
        LLMserverProcess.CommandLine := '';
        LLMserverProcess.ApplicationName := '';
        LLMserverProcess.Executable := WrapperPath;
        LLMserverProcess.CurrentDirectory := appdir;
        LLMserverProcess.Options := [poNewConsole];
        LLMserverProcess.ShowWindow := swoHide;
        LLMserverProcess.Execute;
        // Wait a moment to see if it crashes immediately (e.g., port already in use, DB locked)
        WaitCount := 0;
        while LLMserverProcess.Running and (WaitCount < 10) do // Wait up to 1 second
        begin
          Sleep(100);
          Application.ProcessMessages;
          Inc(WaitCount);
        end;
        PForm.ProgressTimer.Enabled := false;
        PForm.Hide;
        FreeAndNil(PForm);
        // Check if it's still running or if it exited with an error
        if not(LLMserverProcess.Running) then
        begin
          ProcessLLMserviceError(LLMserverProcess.ExitStatus);
          Exit;
        end;
        MainStatusBar.SimpleText := 'All services started.';
        Exit;
      end;
      //Stop LLM service
      if ActionFixed = 'STOP' then
      begin
        if not(LLMserverProcess.Running) then
        begin
          MainStatusBar.SimpleText := 'The services are not currently running.';
          MessageDlg('Information', MainStatusBar.SimpleText, mtInformation, [mbOK], 0);
          Exit;
        end;
        if EmbeddingGenerationProcess.Running then
        begin
          MainStatusBar.SimpleText := 'Cannot stop until embedding vector generation is finished!';
          MessageDlg('Error', MainStatusBar.SimpleText, mtError, [mbOK], 0);
          Exit;
        end;
        {$IFDEF MSWINDOWS}
        KillProcessTree(LLMserverProcess.ProcessID);
        {$ELSE}
        LLMserverProcess.Terminate(0);
        {$ENDIF}
        MainStatusBar.SimpleText := 'All services stopped.';
        Exit;
      end;
      //Restart services
      if ActionFixed = 'RESTART' then
      begin
        if SSLcertificateProcess.Running then
        begin
          MainStatusBar.SimpleText := 'Cannot restart until SSL certificate generation is finished!';
          MessageDlg('Error', MainStatusBar.SimpleText, mtError, [mbOK], 0);
          Exit;
        end;
        if EmbeddingGenerationProcess.Running then
        begin
          MainStatusBar.SimpleText := 'Cannot restart until embedding vector generation is finished!';
          MessageDlg('Error', MainStatusBar.SimpleText, mtError, [mbOK], 0);
          Exit;
        end;
        chdir(appdir);
        if not(FileExists(WrapperPath)) then
        begin
          MainStatusBar.SimpleText := 'Wrapper binary not found: ' + WrapperPath;
          MessageDlg('Error', MainStatusBar.SimpleText, mtError, [mbOK], 0);
          Exit;
        end;
        PForm := TProgressForm.Create(Application);
        PForm.ProgressTimer.Enabled := true;
        PForm.Show;
        Application.ProcessMessages;
        if LLMserverProcess.Running then
        begin
          {$IFDEF MSWINDOWS}
          KillProcessTree(LLMserverProcess.ProcessID);
          {$ELSE}
          LLMserverProcess.Terminate(0);
          {$ENDIF}
          WaitCount := 0;
          while (LLMserverProcess.Running) and (WaitCount < 100) do
          begin
            Sleep(100);
            Application.ProcessMessages;
            Inc(WaitCount);
          end;
        end;
        LLMserverProcess.Active := false;
        LLMserverProcess.Parameters.Clear;
        LLMserverProcess.CommandLine := '';
        LLMserverProcess.ApplicationName := '';
        LLMserverProcess.Executable := WrapperPath;
        LLMserverProcess.CurrentDirectory := appdir;
        LLMserverProcess.Options := [poNewConsole];
        LLMserverProcess.ShowWindow := swoHide;
        LLMserverProcess.Execute;
        // Wait a moment to see if it crashes immediately (e.g., port already in use, DB locked)
        WaitCount := 0;
        while LLMserverProcess.Running and (WaitCount < 10) do // Wait up to 1 second
        begin
          Sleep(100);
          Application.ProcessMessages;
          Inc(WaitCount);
        end;
        PForm.ProgressTimer.Enabled := false;
        PForm.Hide;
        FreeAndNil(PForm);
        // Check if it's still running or if it exited with an error
        if not(LLMserverProcess.Running) then
        begin
          ProcessLLMserviceError(LLMserverProcess.ExitStatus);
          Exit;
        end;
        MainStatusBar.SimpleText := 'All services restarted.';
        Exit;
      end;
      //Invalid action
      MainStatusBar.SimpleText := 'Invalid action: ' + ActionFixed + '!';
      MessageDlg('Error', MainStatusBar.SimpleText, mtError, [mbOK], 0);
      Exit;
    except
      on E: Exception do
      begin
        if Assigned(PForm) then
        begin
          if PForm.Visible then
          begin
            PForm.ProgressTimer.Enabled := false;
            PForm.Hide;
          end;
          FreeAndNil(PForm);
        end;
        MainStatusBar.SimpleText := 'Failed to ' + LowerCase(ActionFixed) + ' services: ' + E.Message;
        MessageDlg('Service Error', MainStatusBar.SimpleText, mtError, [mbOK], 0);
      end;
    end;
  finally
    if Assigned(PForm) then
    begin
      if PForm.Visible then
      begin
        PForm.ProgressTimer.Enabled := false;
        PForm.Hide;
      end;
      FreeAndNil(PForm);
    end;
  end;
end;

//Service Controller (interactive mode)
procedure TMainForm.LLMserviceControlQuery(ServiceAction: string);
var ActionFixed, ActionQuery: string;
begin
  try
    //Check action parameter
    ActionFixed := UpperCase(trim(ServiceAction));
    if not(length(ActionFixed)>0) then
    begin
      MainStatusBar.SimpleText := 'Action not specified!';
      MessageDlg('Error', MainStatusBar.SimpleText, mtError, [mbOK], 0);
      Exit;
    end;
    //User Interaction
    if ActionFixed = 'START' then
      ActionQuery := 'Do you really want to START the server?'
    else if ActionFixed = 'STOP' then
      ActionQuery := 'Do you really want to STOP the server?'
    else if ActionFixed = 'RESTART' then
      ActionQuery := 'Do you really want to RESTART the server?'
    else
    begin
      //Invalid action
      MainStatusBar.SimpleText := 'Invalid action: ' + ActionFixed + '!';
      MessageDlg('Error', MainStatusBar.SimpleText, mtError, [mbOK], 0);
      Exit;
    end;
    if not(MessageDlg(
      'Confirm Action',
      ActionQuery,
      mtConfirmation,
      [mbYes, mbNo],
      0) = mrYes) then
    Begin
      MainStatusBar.SimpleText := 'Action ' + ActionFixed + ' canceled.';
      Exit;
    end;
    //Perform the actual task
    LLMserviceControl(ActionFixed);
  except
    on E: Exception do
    begin
      MainStatusBar.SimpleText := 'Failed to ' + LowerCase(ActionFixed) + ' services: ' + E.Message;
      MessageDlg('Service Error', MainStatusBar.SimpleText, mtError, [mbOK], 0);
    end;
  end;
end;

//Generate Embedding Vectors
procedure TMainForm.GenerateEmbeddings;
begin
  try
    {//Temporarily disabled
    MainStatusBar.SimpleText := 'Embedding generation GUI is currently not available.';
    ShowMessage(MainStatusBar.SimpleText);
    Exit;}
    if not(LLMserverProcess.Running) then
    begin
      MainStatusBar.SimpleText := 'The server is not running! You have to start it first!';
      MessageDlg('Error', MainStatusBar.SimpleText, mtError, [mbOK], 0);
      Exit;
    end;
    if EmbeddingGenerationProcess.Running then
    begin
      MainStatusBar.SimpleText := 'The process is already running! Please wait until it is finished.';
      MessageDlg('Error', MainStatusBar.SimpleText, mtError, [mbOK], 0);
      Exit;
    end;
    if not(MessageDlg(
       'Confirm Process',
       'Do you really want to generate the missing embedding vectors?',
       mtConfirmation,
       [mbYes, mbNo],
       0) = mrYes) then
    begin
      MainStatusBar.SimpleText := 'Embedding vector generation canceled.';
      Exit;
    end;
    if not(length(trim(EmbeddingGenerationProcess.Executable)) >= 1) then
    begin
      MainStatusBar.SimpleText := 'PHP binary location not defined!';
      MessageDlg('Error', MainStatusBar.SimpleText, mtError, [mbOK], 0);
      Exit;
    end;
    chdir(appdir);
    if not(FileExists(EmbeddingGenerationProcess.Executable)) then
    begin
      MainStatusBar.SimpleText := 'PHP binary not found at: ' + EmbeddingGenerationProcess.Executable;
      MessageDlg('Error', MainStatusBar.SimpleText, mtError, [mbOK], 0);
      Exit;
    end;
    MainStatusBar.SimpleText := 'Generating missing embedding vectors...';
    EmbeddingGenerationProcess.Options := [poWaitOnExit, poNewConsole];
    EmbeddingGenerationProcess.Execute;
    while EmbeddingGenerationProcess.Running do
    begin
      Application.ProcessMessages;
      if Application.Terminated then Break;
      Sleep(100);
    end;
    MainStatusBar.SimpleText := 'Embedding vector generation completed.';
    ShowMessage(MainStatusBar.SimpleText);
  except
    on x: Exception do
    begin
      MainStatusBar.SimpleText := 'Internal error: ' + x.Message;
      MessageDlg('Error', MainStatusBar.SimpleText, mtError, [mbOK], 0);
    end;
  end;
end;

//Generate SSL certificate
procedure TMainForm.GenerateSSLcertificate;
begin
  try
    if LLMserverProcess.Running then
    begin
      MainStatusBar.SimpleText := 'The server is running! You have to stop it first!';
      MessageDlg('Error', MainStatusBar.SimpleText, mtError, [mbOK], 0);
      Exit;
    end;
    if SSLcertificateProcess.Running then
    begin
      MainStatusBar.SimpleText := 'The process is already running! Please wait until it is finished.';
      MessageDlg('Error', MainStatusBar.SimpleText, mtError, [mbOK], 0);
      Exit;
    end;
    if not(MessageDlg(
       'Confirm Process',
       'Do you really want to generate a new SSL certificate?',
       mtConfirmation,
       [mbYes, mbNo],
       0) = mrYes) then
    begin
      MainStatusBar.SimpleText := 'SSL certificate generation canceled.';
      Exit;
    end;
    if not(length(trim(SSLcertificateProcess.Executable)) >= 1) then
    begin
      MainStatusBar.SimpleText := 'Service Wrapper binary not defined!';
      MessageDlg('Error', MainStatusBar.SimpleText, mtError, [mbOK], 0);
      Exit;
    end;
    chdir(appdir);
    if not(FileExists(SSLcertificateProcess.Executable)) then
    begin
      MainStatusBar.SimpleText := 'Service Wrapper binary not found at: ' + SSLcertificateProcess.Executable;
      MessageDlg('Error', MainStatusBar.SimpleText, mtError, [mbOK], 0);
      Exit;
    end;
    MainStatusBar.SimpleText := 'Generating SSL certificate...';
    SSLcertificateProcess.Options := [poWaitOnExit, poNewConsole];
    SSLcertificateProcess.Execute;
    while SSLcertificateProcess.Running do
    begin
      Application.ProcessMessages;
      if Application.Terminated then Break;
      Sleep(100);
    end;
    if SSLcertificateProcess.ExitStatus = 0 then
    begin
      MainStatusBar.SimpleText := 'Certificate generated successfully.';
      ShowMessage(MainStatusBar.SimpleText);
    end
    else
    begin
      MainStatusBar.SimpleText := 'Process exited with error code: ' + IntToStr(SSLcertificateProcess.ExitStatus);
      MessageDlg('Error', MainStatusBar.SimpleText, mtError, [mbOK], 0);
    end;
  except
    on x: Exception do
    begin
      MainStatusBar.SimpleText := 'Internal error: ' + x.Message;
      MessageDlg('Error', MainStatusBar.SimpleText, mtError, [mbOK], 0);
    end;
  end;
end;

//Start Web UI
procedure TMainForm.startWebUI;
begin
  try
    if WebUIprocess.Running then
    begin
      MainStatusBar.SimpleText := 'Web UI is already running.';
      Exit;
    end;
    if not(LLMserverProcess.Running) then
    begin
      MainStatusBar.SimpleText := 'You have to start the services first!';
      MessageDlg('Error', MainStatusBar.SimpleText, mtError, [mbOK], 0);
      Exit;
    end;
    MainStatusBar.SimpleText := 'Launching Web UI...';
    if not(length(trim(WebUIprocess.Executable)) >= 1) then
    begin
      MainStatusBar.SimpleText := 'Web UI binary not defined!';
      MessageDlg('Error', MainStatusBar.SimpleText, mtError, [mbOK], 0);
      Exit;
    end;
    chdir(appdir);
    if not(FileExists(WebUIprocess.Executable)) then
    begin
      MainStatusBar.SimpleText := 'Web UI binary not found at: ' + WebUIprocess.Executable;
      MessageDlg('Error', MainStatusBar.SimpleText, mtError, [mbOK], 0);
      Exit;
    end;
    WebUIprocess.Execute;
    Sleep(1000);
    if WebUIprocess.Running then
    begin
      MainStatusBar.SimpleText := 'Web UI started.';
      Exit;
    end;
    MainStatusBar.SimpleText := 'Web UI failed to start!';
    MessageDlg('Error', MainStatusBar.SimpleText, mtError, [mbOK], 0);
  except
    on x: Exception do
    begin
      MainStatusBar.SimpleText := 'Internal error: ' + x.Message;
      MessageDlg('Error', MainStatusBar.SimpleText, mtError, [mbOK], 0);
    end;
  end;
end;

//Restart services from system tray
procedure TMainForm.RestartLLMservicePopupMenuClick(Sender: TObject);
begin
  LLMserviceControlQuery('RESTART');
end;

//Destroy main form
procedure TMainForm.FormDestroy(Sender: TObject);
begin
  try
    ReleaseInstanceLock;
    //Shutdown Services
    if Assigned(LLMserverProcess) and LLMserverProcess.Running then
    begin
      {$IFDEF MSWINDOWS}
      KillProcessTree(LLMserverProcess.ProcessID);
      {$ELSE}
      LLMserverProcess.Terminate(0);
      {$ENDIF}
    end;
    //Shutdown Web UI Process
    if Assigned(WebUIprocess) and WebUIprocess.Running then
    begin
      {$IFDEF MSWINDOWS}
      KillProcessTree(WebUIprocess.ProcessID);
      {$ELSE}
      WebUIprocess.Terminate(0);
      {$ENDIF}
    end;
    //Shutdown Certificate Generation Process
    if Assigned(SSLcertificateProcess) and SSLcertificateProcess.Running then
    begin
      {$IFDEF MSWINDOWS}
      KillProcessTree(SSLcertificateProcess.ProcessID);
      {$ELSE}
      SSLcertificateProcess.Terminate(0);
      {$ENDIF}
    end;
    //Shutdown Embedding Vector Generation Process
    if Assigned(EmbeddingGenerationProcess) and EmbeddingGenerationProcess.Running then
    begin
      {$IFDEF MSWINDOWS}
      KillProcessTree(EmbeddingGenerationProcess.ProcessID);
      {$ELSE}
      EmbeddingGenerationProcess.Terminate(0);
      {$ENDIF}
    end;
  except
    on x: Exception do
      MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);
  end;
end;

//Call SSL certificate generation
procedure TMainForm.GenerateCertificateMenuClick(Sender: TObject);
begin
  GenerateSSLcertificate;
end;

//Call SSL certificate generation
procedure TMainForm.GenerateCertificatePopupMenuClick(Sender: TObject);
begin
  GenerateSSLcertificate;
end;

//Call embedding vector generation
procedure TMainForm.GenerateEmbeddingsPopupMenuClick(Sender: TObject);
begin
  GenerateEmbeddings;
end;

//Call embedding vector generation
procedure TMainForm.GenerateEmbeddingsMenuClick(Sender: TObject);
begin
  GenerateEmbeddings;
end;

//Open Personality Database documentation
procedure TMainForm.PersonalityDBdocMenuClick(Sender: TObject);
begin
  OpenFile(personalityDBdocFile);
end;

//Open Personality Database documentation
procedure TMainForm.PersonalityDBdocPopupMenuClick(Sender: TObject);
begin
  OpenFile(personalityDBdocFile);
end;

//Open Service Manager documentation
procedure TMainForm.ServiceManagerDocMenuClick(Sender: TObject);
begin
  OpenFile(serviceManagerDocFile);
end;

//Open Service Manager documentation
procedure TMainForm.ServiceManagerDocPopupMenuClick(Sender: TObject);
begin
  OpenFile(serviceManagerDocFile);
end;

//Open Settings menu
procedure TMainForm.SettingsPopupMenuClick(Sender: TObject);
begin
  SaveConfigData;
end;

//Start Web UI from main menu
procedure TMainForm.OpenWebUImenuClick(Sender: TObject);
begin
  startWebUI;
end;

//Start Web UI from popup menu
procedure TMainForm.OpenWebUIpopupMenuClick(Sender: TObject);
begin
  startWebUI;
end;

//Open About Form (from main menu)
procedure TMainForm.AboutMenuClick(Sender: TObject);
begin
  AboutForm.ShowModal;
end;

//Open About Form (from popup menu)
procedure TMainForm.AboutPopupMenuClick(Sender: TObject);
begin
  AboutForm.ShowModal;
end;

//Check services periodically
procedure TMainForm.ProcessTimerTimer(Sender: TObject);
begin
  try
    StartLLMserviceMenu.Enabled := (not(LLMserverProcess.Running) and not(SSLcertificateProcess.Running));
    StopLLMserviceMenu.Enabled := (LLMserverProcess.Running and not(EmbeddingGenerationProcess.Running));
    RestartLLMserviceMenu.Enabled := (LLMserverProcess.Running and not(SSLcertificateProcess.Running) and not(EmbeddingGenerationProcess.Running));
    StartLLMservicePopupMenu.Enabled := StartLLMserviceMenu.Enabled;
    StopLLMservicePopupMenu.Enabled := StopLLMserviceMenu.Enabled;
    RestartLLMservicePopupMenu.Enabled := RestartLLMserviceMenu.Enabled;
    GenerateEmbeddingsMenu.Enabled := (LLMserverProcess.Running and not(EmbeddingGenerationProcess.Running));
    GenerateEmbeddingsPopupMenu.Enabled := GenerateEmbeddingsMenu.Enabled;
    GenerateCertificateMenu.Enabled := (not(LLMserverProcess.Running) and not(SSLcertificateProcess.Running));
    GenerateCertificatePopupMenu.Enabled := GenerateCertificateMenu.Enabled;
    OpenWebUImenu.Enabled := (LLMserverProcess.Running and not(WebUIprocess.Running));
    OpenWebUIpopupMenu.Enabled := OpenWebUImenu.Enabled;
    OpenServiceManagerPopupMenu.Enabled := (not(Visible) or (WindowState = wsMinimized));
    if DelayedStartUpQuery then
    begin
      DelayedStartUpQuery := false;
      SaveConfigData;
      LLMserviceControlQuery('START');
    end;
  except
    on x: Exception do
    begin
      MainStatusBar.SimpleText := 'Internal error: ' + x.Message;
      MessageDlg('Error', MainStatusBar.SimpleText, mtError, [mbOK], 0);
    end;
  end;
end;

//Restart Services
procedure TMainForm.RestartLLMserviceMenuClick(Sender: TObject);
begin
  LLMserviceControlQuery('RESTART');
end;

//Close application
procedure TMainForm.ExitMenuClick(Sender: TObject);
begin
  Close;
end;

//Close application
procedure TMainForm.ExitPopupMenuClick(Sender: TObject);
begin
  Close;
end;

//Confirm exit
procedure TMainForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
var WaitCount: Integer;
begin
  try
    if Application.Terminated then
    begin
      CanClose := true;
      Exit;
    end;
    if not(MessageDlg(
       'Confirm Shutdown',
       'Do you really want to stop all running services and close the application?',
       mtConfirmation,
       [mbYes, mbNo],
       0) = mrYes) then
    begin
      CanClose := false;
      Exit;
    end;
    //Shutdown Services
    if LLMserverProcess.Running then
    begin
      MainStatusBar.SimpleText := 'Stopping services...';
      {$IFDEF MSWINDOWS}
      KillProcessTree(LLMserverProcess.ProcessID);
      {$ELSE}
      LLMserverProcess.Terminate(0);
      {$ENDIF}
      WaitCount := 0;
      while LLMserverProcess.Running and (WaitCount < 30) do
      begin
        Sleep(100);
        Application.ProcessMessages;
        Inc(WaitCount);
      end;
      if LLMserverProcess.Running then
        MainStatusBar.SimpleText := 'Service did not stop in time, forcing exit...'
      else
        MainStatusBar.SimpleText := 'Service stopped cleanly.';
    end;
    //Shutdown Web UI
    if WebUIprocess.Running then
    begin
      MainStatusBar.SimpleText := 'Stopping Web UI...';
      {$IFDEF MSWINDOWS}
      KillProcessTree(WebUIprocess.ProcessID);
      {$ELSE}
      WebUIprocess.Terminate(0);
      {$ENDIF}
      WaitCount := 0;
      while WebUIprocess.Running and (WaitCount < 30) do
      begin
        Sleep(100);
        Application.ProcessMessages;
        Inc(WaitCount);
      end;
      if WebUIprocess.Running then
        MainStatusBar.SimpleText := 'Web UI did not stop in time, forcing exit...'
      else
        MainStatusBar.SimpleText := 'Web UI stopped cleanly.';
    end;
    //Shutdown Certificate Generation
    if SSLcertificateProcess.Running then
    begin
      MainStatusBar.SimpleText := 'Stopping SSL certificate generation...';
      {$IFDEF MSWINDOWS}
      KillProcessTree(SSLcertificateProcess.ProcessID);
      {$ELSE}
      SSLcertificateProcess.Terminate(0);
      {$ENDIF}
      WaitCount := 0;
      while SSLcertificateProcess.Running and (WaitCount < 30) do
      begin
        Sleep(100);
        Application.ProcessMessages;
        Inc(WaitCount);
      end;
      if SSLcertificateProcess.Running then
        MainStatusBar.SimpleText := 'SSL certificate generation did not stop in time, forcing exit...'
      else
        MainStatusBar.SimpleText := 'SSL certificate generation stopped cleanly.';
    end;
    //Shutdown Embedding Vector Generation
    if EmbeddingGenerationProcess.Running then
    begin
      MainStatusBar.SimpleText := 'Stopping embedding vector generation...';
      {$IFDEF MSWINDOWS}
      KillProcessTree(EmbeddingGenerationProcess.ProcessID);
      {$ELSE}
      EmbeddingGenerationProcess.Terminate(0);
      {$ENDIF}
      WaitCount := 0;
      while EmbeddingGenerationProcess.Running and (WaitCount < 30) do
      begin
        Sleep(100);
        Application.ProcessMessages;
        Inc(WaitCount);
      end;
      if EmbeddingGenerationProcess.Running then
        MainStatusBar.SimpleText := 'Embedding vector generation did not stop in time, forcing exit...'
      else
        MainStatusBar.SimpleText := 'Embedding vector generation stopped cleanly.';
    end;
    SystemTrayIcon.Visible := false;
    CanClose := true;
  except
    on x: Exception do
      MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);
  end;
end;

//Initial settings
procedure TMainForm.FormCreate(Sender: TObject);
begin
  try
    //Check minimum OS version
    {$IFDEF MSWINDOWS}
    if not(CheckWin32Version(10, 0)) then
    begin
      MessageDlg('Error', 'This application requires Windows 10 or later to run.', mtError, [mbOK], 0);
      Application.Terminate;
      Exit;
    end;
    {$ENDIF}
    //Make sure only 1 instance can run
    if not(CheckSingleInstance) then
    begin
      MessageDlg('Error', 'The application is already running!', mtError, [mbOK], 0);
      Application.Terminate;
      Exit;
    end;
    //Set main directories
    {$IFDEF MSWINDOWS}
    appdir := IncludeTrailingPathDelimiter(extractfilepath(application.ExeName));
    {$ELSE}
    appdir := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));
    {$ENDIF}
    chdir(appdir);
    configdir := appdir + 'config' + PathDelim;
    if not(DirectoryExists(configdir)) then ForceDirectories(configdir);
    wrapperConfigFile := configdir + 'wrapper.json';
    webserverDir := appdir + 'webserver' + PathDelim;
    if not(DirectoryExists(webserverDir)) then
    begin
      MessageDlg('Error', 'ERROR: web server directory not found at: ' + webserverDir, mtError, [mbOK], 0);
      Application.Terminate;
      Exit;
    end;
    //Set documentation directory and files (do not terminate when not found)
    docDir := appdir + 'doc' + PathDelim;
    devDocDir := docDir + 'dev' + PathDelim;
    wrapperDBdocFile := devDocDir + 'database' + PathDelim + 'wrapper.pdf';
    personalityDBdocFile := devDocDir + 'database' + PathDelim + 'personality.pdf';
    frontendDocFile := devDocDir + 'frontend' + PathDelim + 'index.html';
    serviceManagerDocFile := devDocDir + 'manager' + PathDelim + 'index.html';
    userManualFile := docDir + 'user_manual.pdf';
    //Application settings
    Caption := trim(application.Title);
    SystemTrayIcon.Visible := true;
    WebUIprocess.Active := false;
    WebUIprocess.Parameters.Clear;
    WebUIprocess.CommandLine := '';
    WebUIprocess.ApplicationName := '';
    WebUIprocess.Executable := webserverDir + 'webclient.exe';
    WebUIprocess.CurrentDirectory := IncludeTrailingPathDelimiter(extractfilepath(WebUIprocess.Executable));
    WebUIprocess.Options := [poNoConsole];
    SSLcertificateProcess.Active := false;
    SSLcertificateProcess.CommandLine := '';
    SSLcertificateProcess.ApplicationName := '';
    {$IFDEF WINDOWS}
    SSLcertificateProcess.Executable := appdir + 'wrapper.exe';
    {$ELSE}
    SSLcertificateProcess.Executable := appdir + 'wrapper';
    {$ENDIF}
    SSLcertificateProcess.CurrentDirectory := IncludeTrailingPathDelimiter(extractfilepath(SSLcertificateProcess.Executable));
    SSLcertificateProcess.Options := [poWaitOnExit,poNewConsole];
    EmbeddingGenerationProcess.Active := false;
    EmbeddingGenerationProcess.CommandLine := '';
    EmbeddingGenerationProcess.ApplicationName := '';
    {$IFDEF WINDOWS}
    EmbeddingGenerationProcess.Executable := webserverDir + 'php' + PathDelim + 'php.exe';
    {$ELSE}
    EmbeddingGenerationProcess.Executable := webserverDir + 'php' + PathDelim + 'php';
    {$ENDIF}
    EmbeddingGenerationProcess.CurrentDirectory := webserverDir + 'www' + PathDelim + 'frontend' + PathDelim;
    EmbeddingGenerationProcess.Parameters.Clear;
    EmbeddingGenerationProcess.Parameters.Append('bin' + PathDelim + 'console');
    EmbeddingGenerationProcess.Parameters.Append('app:generate-embeddings');
    EmbeddingGenerationProcess.Options := [poWaitOnExit,poNewConsole];
    DelayedStartUpQuery := false;
    {$IFDEF DEBUG}
    MainStatusBar.SimpleText := 'Debug mode, not starting services.';
    {$ELSE}
    if FileExists(wrapperConfigFile) then
      LLMserviceControl('START')
    else
      DelayedStartUpQuery := true;
    {$ENDIF}
  except
    on x: Exception do
      MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);
  end;
end;

//Minimize application to system tray
procedure TMainForm.FormWindowStateChange(Sender: TObject);
begin
  try
    if WindowState = wsMinimized then
    begin
      WindowState := wsNormal;
      Hide;
    end;
  except
    on x: Exception do
    begin
      MainStatusBar.SimpleText := 'Internal error: ' + x.Message;
      MessageDlg('Error', MainStatusBar.SimpleText, mtError, [mbOK], 0);
    end;
  end;
end;

//Minimize to System Tray
procedure TMainForm.MinimizeMenuClick(Sender: TObject);
begin
  Hide;
end;

//Open application
procedure TMainForm.OpenServiceManagerPopupMenuClick(Sender: TObject);
begin
  try
    WindowState := wsNormal;
    Position := poScreenCenter;
    Show;
    BringToFront;
    SetFocus;
  except
    on x: Exception do
    begin
      MainStatusBar.SimpleText := 'Internal error: ' + x.Message;
      MessageDlg('Error', MainStatusBar.SimpleText, mtError, [mbOK], 0);
    end;
  end;
end;

//Open Settings menu
procedure TMainForm.SettingsMenuClick(Sender: TObject);
begin
  SaveConfigData;
end;

//Start services
procedure TMainForm.StartLLMserviceMenuClick(Sender: TObject);
begin
  LLMserviceControlQuery('START');
end;

//Start services from system tray
procedure TMainForm.StartLLMservicePopupMenuClick(Sender: TObject);
begin
  LLMserviceControlQuery('START');
end;

//Stop services
procedure TMainForm.StopLLMserviceMenuClick(Sender: TObject);
begin
  LLMserviceControlQuery('STOP');
end;

//Stop service from system tray
procedure TMainForm.StopLLMservicePopupMenuClick(Sender: TObject);
begin
  LLMserviceControlQuery('STOP');
end;

//Open popup menu
procedure TMainForm.SystemTrayIconMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  try
    if Button = mbLeft then
      MainPopupMenu.PopUp(Mouse.CursorPos.X, Mouse.CursorPos.Y);
  except
    on x: Exception do
    begin
      MainStatusBar.SimpleText := 'Internal error: ' + x.Message;
      MessageDlg('Error', MainStatusBar.SimpleText, mtError, [mbOK], 0);
    end;
  end;
end;

//Open User Manual
procedure TMainForm.UserManualMenuClick(Sender: TObject);
begin
  OpenFile(userManualFile);
end;

//Open User Manual
procedure TMainForm.UserManualPopupMenuClick(Sender: TObject);
begin
  OpenFile(userManualFile);
end;

//Open Service Wrapper Database documentation
procedure TMainForm.WrapperDBdocMenuClick(Sender: TObject);
begin
  OpenFile(wrapperDBdocFile);
end;

//Open Service Wrapper Database documentation
procedure TMainForm.WrapperDBdocPopupMenuClick(Sender: TObject);
begin
  OpenFile(wrapperDBdocFile);
end;

end.

