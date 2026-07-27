{ Settings form unit for configuring LLM engines, models, and persona settings. }
unit settings_form;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, LCLIntf, SysUtils, DB, SQLite3Conn, SQLDB, Forms, Controls, Graphics,
  Dialogs, StdCtrls, ExtCtrls, ValEdit, ComCtrls, DBCtrls, Grids, Spin, fpjson,
  jsonparser, StrUtils, RegExpr, process, FileUtil, SynHighlighterCss, SynEdit,
  math, base64, Types, progress_form;

type

  { TEngineComboBoxItem: item in the LLM engine combo box containing engine configuration from database. }
  TEngineComboBoxItem = class
    { Unique identifier for the engine configuration. }
    ID: string;
    { Path to the server executable binary. }
    ServerBinary: ansistring;
    { Proxy port number configured for this engine. }
    ProxyPort: string;
    { Timeout in seconds for proxy connections. }
    ProxyTimeout: integer;
    { Maximum number of concurrent proxy connections. }
    ProxyMaxConnections: integer;
    { Maximum package size in bytes for proxy transfers. }
    ProxyMaxPackageSize: integer;
  end;

  { TDeviceComboBoxItem: item in the device combo box containing GPU/device information. }
  TDeviceComboBoxItem = class
    { Device identifier string. }
    ID: string;
    { Display title for the device. }
    Title: string;
  end;

  { TPersonaComboBoxItem: item in the persona combo box containing persona configuration from database. }
  TPersonaComboBoxItem = class
    { Unique identifier for the persona. }
    ID: string;
    { Short persona name/key. }
    Name: string;
    { Full display name of the persona. }
    FullName: string;
    { Description text for the persona. }
    Description: string;
    { System prompt that defines the persona behavior. }
    SystemPrompt: AnsiString;
    { Summary prompt for generating conversation summaries. }
    SummaryPrompt: AnsiString;
    { Initial message sent when persona is loaded. }
    InitialMessage: AnsiString;
    { Threshold for behavior similarity matching. }
    BehaviorSimilarityThreshold: integer;
    { Base64-encoded avatar image data. }
    Avatar: AnsiString;
    { Base64-encoded background image data. }
    BackgroundImage: AnsiString;
    { CSS override string for custom styling. }
    CSSoverride: AnsiString;
  end;

  { TResponseModeComboBoxItem: item in the response mode combo box for selecting chat completion behavior. }
  TResponseModeComboBoxItem = class
    { Numeric identifier for the response mode. }
    ID: integer;
    { Display title for the response mode. }
    Title: string;
  end;

  { TMemoryModeComboBoxItem: item in the memory mode combo box for selecting chat completion behavior. }
  TMemoryModeComboBoxItem = class
    { Numeric identifier for the memory mode. }
    ID: integer;
    { Display title for the memory mode. }
    Title: string;
  end;

  { SaveSettingsFatal: exception raised when invalid settings prevent saving configuration. }
  SaveSettingsFatal = class(Exception);

  { TSettingsForm: settings dialog form for configuring LLM engines, proxy settings, models, and personas. }
  TSettingsForm = class(TForm)
    { Checkbox to enable or disable the LLM service. }
    EnableLLMcheckBox: TCheckBox;
    { Button to clear the temporary directory contents. }
    ClearTempDirButton: TButton;
    { Label for the PHP time zone combobox. }
    PHPtimezoneComboBox: TComboBox;
    { Combobox for the PHP time zone. }
    PHPtimezoneLabel: TLabel;
    { Button to open the temporary directory in the file explorer. }
    OpenTempDirButton: TButton;
    { Label for the persona summary prompt field. }
    PersonaSummaryPromptLabel: TLabel;
    { Memo control for editing the persona summary prompt. }
    PersonaSummaryPrompt: TMemo;
    { Group box containing temporary directory controls. }
    TempDirGroupBox: TGroupBox;
    { SQL query component for loading PHP time zones from the database. }
    TimezoneQuery: TSQLQuery;
    { Scrollable container for the web server configuration tab sheet. }
    WebServerTabSheetScrollBox: TScrollBox;
    { SQL query component for loading web server configuration from the database. }
    WebServerConfigQuery: TSQLQuery;
    { File open dialog for selecting SSL certificate files. }
    OpenCertificateDialog: TOpenDialog;
    { File open dialog for selecting SSL private key files. }
    OpenKeyDialog: TOpenDialog;
    { Label for the PHP HTTP port field. }
    PHPhttpPortLabel: TLabel;
    { Spin edit control for the PHP-FPM HTTP port number. }
    PHPhttpPort: TSpinEdit;
    { Group box containing PHP settings. }
    PHPsettingsGroupBox: TGroupBox;
    { Button to open the SSL certificate file selection dialog. }
    OpenSSLcertificateButton: TButton;
    { Button to add a new embedding model parameter row. }
    AddEmbeddingParameterButton: TButton;
    { Button to add a new embedding model to the list. }
    AddEmbeddingModelButton: TButton;
    { Button to apply and save the current settings configuration. }
    ApplyButton: TButton;
    { Horizontal bevel separator at the bottom of the form. }
    BottomBevel: TBevel;
    { Button to add a new LLM parameter row. }
    AddButton: TButton;
    { Button to add a new LLM model to the list. }
    AddModelButton: TButton;
    { Label for the HTTP port field. }
    HTTPportLabel: TLabel;
    { Label for the HTTPS port field. }
    HTTPSportLabel: TLabel;
    { Spin edit control for the nginx HTTPS port number. }
    NginxHTTPSport: TSpinEdit;
    { Group box containing nginx settings. }
    NginxSettingsGroupBox: TGroupBox;
    { Button to open the SSL private key file selection dialog. }
    OpenSSLkeyButton: TButton;
    { Input field for the SSL certificate file path. }
    SSLcertificate: TLabeledEdit;
    { Combo box for selecting the persona memory mode. }
    PersonaMemoryMode: TComboBox;
    { Label for the persona memory mode combo box. }
    PersonaMemoryModeLabel: TLabel;
    { Combo box for selecting the persona response mode. }
    PersonaResponseMode: TComboBox;
    { Label for the persona response mode combo box. }
    PersonaResponseModeLabel: TLabel;
    { Label for the persona behavior similarity threshold field. }
    PersonaBehaviorSimilarityThresholdLabel: TLabel;
    { Group box containing persona system prompt settings. }
    PersonaSystemGroupBox: TGroupBox;
    { File open dialog for selecting image files. }
    OpenImageDialog: TOpenDialog;
    { SQLite connection to the persona database. }
    PersonaDBconnection: TSQLite3Connection;
    { SQL query component for loading persona data from the database. }
    PersonaQuery: TSQLQuery;
    { Transaction component for the persona database connection. }
    PersonaTransaction: TSQLTransaction;
    { Memo control for editing the persona system prompt. }
    PersonaSystemPrompt: TMemo;
    { Label for the persona system prompt field. }
    PersonaSystemPromptLabel: TLabel;
    { Input field for the persona initial message. }
    PersonaInitialMessage: TLabeledEdit;
    { Auto-generated bound label for the persona description field. }
    PersonaDescriptionLabel: TBoundLabel;
    { Input field for the persona full display name. }
    PersonaFullName: TLabeledEdit;
    { Input field for the persona description text. }
    PersonaDescription: TLabeledEdit;
    { Auto-generated bound label for the persona full name field. }
    PersonaFullNameLabel: TBoundLabel;
    { Auto-generated bound label for the persona initial message field. }
    PersonaInitialMessageLabel: TBoundLabel;
    { Label for the persona CSS override field. }
    PersonaCSSoverrideLabel: TLabel;
    { Scrollable container for the persona tab sheet. }
    PersonaTabSheetScrollBox: TScrollBox;
    { Group box containing persona background image settings. }
    PersonaBackgroundGroupBox: TGroupBox;
    { Image control displaying the persona avatar. }
    PersonaAvatarImage: TImage;
    { Group box containing persona avatar image settings. }
    PersonaAvatarGroupBox: TGroupBox;
    { Image control displaying the persona background image. }
    PersonaBackgroundImage: TImage;
    { Group box containing persona property fields. }
    PersonaPropertiesGroupBox: TGroupBox;
    { Button to load the selected persona from the database. }
    LoadPersonaButton: TButton;
    { Combo box for selecting the default persona. }
    DefaultPersonaComboBox: TComboBox;
    { Group box containing default persona selection. }
    DefaultPersonaGroupBox: TGroupBox;
    { File open dialog for selecting LLM model files to import. }
    ImportModelDialog: TOpenDialog;
    { Button to open the log directory in the file explorer. }
    OpenLogFolderButton: TButton;
    { Button to clear all log files. }
    ClearLogButton: TButton;
    { Combo box for selecting the GPU/CPU device to use. }
    DeviceCombobox: TComboBox;
    { Checkbox to enable or disable the embedding service. }
    EnableEmbeddingCheckBox: TCheckBox;
    { Combo box for selecting the embedding model. }
    EmbeddingModelComboBox: TComboBox;
    { Group box containing embedding model configuration. }
    EmbeddingModelGroupBox: TGroupBox;
    { Label for the device selection combo box. }
    DeviceLabel: TLabel;
    { Label for the maximum package size field. }
    MaxPackageSizeLabel: TLabel;
    { Label for the maximum connections field. }
    MaxConnectionsLabel: TLabel;
    { Spin edit control for maximum concurrent proxy connections. }
    LLMproxyServiceMaxConnections: TSpinEdit;
    { Spin edit control for maximum proxy package size in bytes. }
    LLMproxyServiceMaxPackageSize: TSpinEdit;
    { Tab sheet containing embedding model settings. }
    EmbeddingTabSheet: TTabSheet;
    { Group box containing embedding model parameters. }
    EmbeddingParameterGroupBox: TGroupBox;
    { Value list editor grid for embedding model parameters. }
    EmbeddingParameterListEditor: TValueListEditor;
    { Process component for running the LLM server. }
    LLMserverProcess: TProcess;
    { Button to remove the selected embedding parameter row. }
    RemoveEmbeddingParameterButton: TButton;
    { Scrollable container for the engine tab sheet. }
    EngineTabSheetScrollBox: TScrollBox;
    { Tab sheet containing persona configuration settings. }
    PersonaTabSheet: TTabSheet;
    { Syntax-highlighted editor for persona CSS overrides. }
    PersonaCSSoverride: TSynEdit;
    { Syntax definition component for CSS highlighting in the persona CSS editor. }
    CSSsyntaxDefinition: TSynCssSyn;
    { Spin edit control for the persona behavior similarity threshold. }
    PersonaBehaviorSimilarityThreshold: TSpinEdit;
    { Spin edit control for the nginx HTTP port number. }
    NginxHTTPport: TSpinEdit;
    { Input field for the SSL private key file path. }
    SSLkey: TLabeledEdit;
    { Tab sheet containing web server configuration settings. }
    WebServerTabSheet: TTabSheet;
    { Label for the proxy timeout field. }
    TimeoutLabel: TLabel;
    { Input field for the LLM proxy service port number. }
    LLMproxyServicePort: TLabeledEdit;
    { Group box containing the LLM proxy service settings. }
    LLMproxyServiceGroup: TGroupBox;
    { Checkbox to enable or disable LLM service logging. }
    LLMloggingCheckBox: TCheckBox;
    { Group box containing logging settings. }
    LLMloggingGroupBox: TGroupBox;
    { Auto-generated bound label for the LLM proxy service port field. }
    LLMproxyServicePortLabel: TBoundLabel;
    { Page control organizing settings into tab sheets. }
    SettingsPageControl: TPageControl;
    { Button to remove the selected parameter row. }
    RemoveButton: TButton;
    { Button to load default engine configuration values. }
    LoadDefaultsButton: TButton;
    { Group box containing LLM engine parameter settings. }
    ParameterGroupBox: TGroupBox;
    { Combo box for selecting the LLM model. }
    ModelComboBox: TComboBox;
    { Label for the LLM model combo box. }
    ModelLabel: TLabel;
    { Combo box for selecting the LLM engine. }
    LlamaEngineComboBox: TComboBox;
    { Group box containing LLM engine selection. }
    EngineGroupBox: TGroupBox;
    { Label for the LLM engine combo box. }
    EngineLabel: TLabel;
    { OK/apply button for the settings dialog. }
    OKbutton: TButton;
    { Cancel button for the settings dialog. }
    CancelButton: TButton;
    { SQLite connection to the wrapper database. }
    LlamaDBconnection: TSQLite3Connection;
    { Transaction component for the wrapper database connection. }
    LlamaTransaction: TSQLTransaction;
    { SQL query component for loading engine data from the wrapper database. }
    LlamaQuery: TSQLQuery;
    { Value list editor grid for LLM engine parameters. }
    ParameterListEditor: TValueListEditor;
    { SQL query component for loading generic configuration from the database. }
    ConfigDataQuery: TSQLQuery;
    { Tab sheet containing LLM engine settings. }
    EngineTabSheet: TTabSheet;
    { Tab sheet containing logging and proxy settings. }
    LoggingAndProxyTabSheet: TTabSheet;
    { Spin edit control for the LLM proxy service timeout in seconds. }
    LLMproxyServiceTimeout: TSpinEdit;
    { Opens a folder in the system default file explorer. }
    function OpenFolder(const FolderName: AnsiString): Boolean;
    { Converts an image control's picture to a Base64 encoded string. }
    function GetImageBase64(ImageControl: TImage): AnsiString;
    { Gets the filename for an image control based on stored format. }
    function GetImageFileName(ImageControl: TImage): string;
    { Converts a stream to its string representation. }
    function StreamToString(Stream: TStream): string;
    { Enables or disables LLM parameters based on checkbox. }
    procedure EnableLLMcheckBoxChange(Sender: TObject);
    { Clears all temporary files and directories. }
    procedure ClearTempDir;
    { Handles clear temp dir button click event. }
    procedure ClearTempDirButtonClick(Sender: TObject);
    { Handles persona selection change in the combo box. }
    procedure DefaultPersonaComboBoxChange(Sender: TObject);
    { Handles certificate open button click. }
    procedure OpenSSLcertificateButtonClick(Sender: TObject);
    { Handles key open button click. }
    procedure OpenSSLkeyButtonClick(Sender: TObject);
    { Handles open temp dir button click. }
    procedure OpenTempDirButtonClick(Sender: TObject);
    { Handles avatar image click to open image selector. }
    procedure PersonaAvatarImageClick(Sender: TObject);
    { Handles background image click to open image selector. }
    procedure PersonaBackgroundImageClick(Sender: TObject);
    { Handles add embedding model button click. }
    procedure AddEmbeddingModelButtonClick(Sender: TObject);
    { Handles add embedding parameter button click. }
    procedure AddEmbeddingParameterButtonClick(Sender: TObject);
    { Handles add model button click. }
    procedure AddModelButtonClick(Sender: TObject);
    { Clears the engine combo box and frees all associated items. }
    procedure ClearEngineComboBox;
    { Clears the device combo box and frees all associated items. }
    procedure ClearDeviceComboBox;
    { Loads LLM model files from the model or embedding directory. }
    procedure LoadLLMfiles(const LLMtype: string; const DefaultFile: string = '');
    { Clears log files or directory based on server running state. }
    procedure ClearLog;
    { Handles clear log button click event. }
    procedure ClearLogButtonClick(Sender: TObject);
    { Handles mouse move over embedding parameter grid for tooltip display. }
    procedure EmbeddingParameterListEditorMouseMove(Sender: TObject;
      Shift: TShiftState; X, Y: Integer);
    { Enables or disables embedding parameters based on checkbox. }
    procedure EnableEmbeddingCheckBoxChange(Sender: TObject);
    { Initializes the form display and enables buttons. }
    procedure FormShow(Sender: TObject);
    { Handles LLM engine selection change in the combo box. }
    procedure LlamaEngineComboBoxChange(Sender: TObject);
    { Enables or disables proxy service settings based on port input. }
    procedure LLMproxyServicePortChange(Sender: TObject);
    { Loads default configuration values for the selected engine. }
    procedure LoadDefaultConfig;
    { Loads configuration data from wrapper.json file. }
    procedure LoadConfigData;
    { Loads the list of personas from the database. }
    procedure LoadBasePersonaList;
    { Loads persona configuration from the personality.json file. }
    procedure LoadPersonaConfig;
    { Loads the selected persona into the form fields. }
    procedure LoadSelectedPersona;
    { Opens a confirmation dialog before loading selected persona. }
    procedure LoadSelectedPersonaQuery;
    { Loads persona images from JSON data into image controls. }
    procedure LoadPersonaImages(RootObj: TJSONObject; const FieldName: string; ImageControl: TImage);
    { Clears the persona combo box and frees all associated items. }
    procedure ClearPersonaComboBox;
    { Handles apply button click to save settings. }
    procedure ApplyButtonClick(Sender: TObject);
    { Handles add button click to add a new parameter. }
    procedure AddButtonClick(Sender: TObject);
    { Handles form creation and initialization. }
    procedure FormCreate(Sender: TObject);
    { Handles form destruction and cleanup. }
    procedure FormDestroy(Sender: TObject);
    { Handles load defaults button click. }
    procedure LoadDefaultsButtonClick(Sender: TObject);
    { Handles load persona button click. }
    procedure LoadPersonaButtonClick(Sender: TObject);
    { Handles open log folder button click. }
    procedure OpenLogFolderButtonClick(Sender: TObject);
    { Handles mouse move over parameter grid for tooltip display. }
    procedure ParameterListEditorMouseMove(Sender: TObject; Shift: TShiftState;
      X, Y: Integer);
    { Handles remove button click to remove a parameter. }
    procedure RemoveButtonClick(Sender: TObject);
    { Handles remove embedding parameter button click. }
    procedure RemoveEmbeddingParameterButtonClick(Sender: TObject);
  protected
    { Flag to prevent engine change handling during initialization. }
    canHandleEngineChange: boolean;
    { List of parameter titles for grid hints. }
    TitleList: TStringList;
    { List of embedding parameter titles for grid hints. }
    EmbeddingTitleList: TStringList;
    { Image format for avatar (png, jpg, etc.). }
    AvatarImageFormat: string;
    { Image format for background (png, jpg, etc.). }
    BackgroundImageFormat: string;
    { Stored filename for avatar image. }
    AvatarStoredFileName: string;
    { Stored filename for background image. }
    BackgroundStoredFileName: string;
    { Memory stream for avatar image data. }
    AvatarImageData: TMemoryStream;
    { Memory stream for background image data. }
    BackgroundImageData: TMemoryStream;
    { Conversational LLM service port number. }
    llmConversationalPort: integer;
    { Embedding service port number. }
    llmEmbeddingPort: integer;
    { Proxy location path for nginx. }
    llmProxyLocation: AnsiString;
    { Copies a file progressively while updating the progress bar (helper). }
    function CopyFileWithProgress(const SourceFile, DestFile: AnsiString): Boolean;
  public
    { Path to the application directory. }
    appdir: AnsiString;
    { Path to the database directory. }
    dbdir: AnsiString;
    { Path to the conversational LLM models directory. }
    modeldir: AnsiString;
    { Path to the embedding models directory. }
    embeddingModeldir: AnsiString;
    { Path to the configuration directory. }
    configdir: AnsiString;
    { Full path to the wrapper SQLite database. }
    wrapperDbFile: AnsiString;
    { Full path to the wrapper SQLite write-ahead log file. }
    wrapperDbFileWAL: AnsiString;
    { Full path to the wrapper SQLite shared memory file. }
    wrapperDbFileSHM: AnsiString;
    { Path to the web server directory. }
    webserverdir: AnsiString;
    { Full path to the PHP configuration file. }
    phpConfigFile: AnsiString;
    { Full path to the nginx configuration file. }
    webserverConfigFile: AnsiString;
    { Path to the SSL certificate directory. }
    sslCertificateDir: Ansistring;
    { Full path to the personality SQLite database. }
    personaDbFile: AnsiString;
    { Full path to the personality SQLite write-ahead log file. }
    personaDbFileWAL: AnsiString;
    { Full path to the personality SQLite shared memory file. }
    personaDbFileSHM: AnsiString;
    { Full path to the wrapper configuration JSON file. }
    wrapperConfigFile: AnsiString;
    { Full path to the personality configuration JSON file. }
    personaConfigFile: AnsiString;
    { Full path to the redirect PHP file. }
    redirectFile: AnsiString;
    { Path to the log directory. }
    logDirectory: AnsiString;
    { Full path to the log file. }
    logFile: AnsiString;
    { Path to the temporary files directory. }
    TempDirectory: AnsiString;
    { Path to the cache directory. }
    CacheDirectory: AnsiString;
    { Indicates whether configuration was saved successfully. }
    configDataSaved: boolean;
    { Indicates whether an error occurred during save. }
    saveSettingsError: boolean;
    { Indicates whether the LLM server process is currently running. }
    MainLLMserverProcessRunning: boolean;
    { Stores the default PHP time zone read from the database. }
    DefaultPHPtimezone: integer;
    { Saves configuration data to JSON and webserver config files. }
    procedure SaveConfigData;
    { Checkpoints and removes SQLite WAL/SHM files after database close. }
    procedure CleanupWALFiles(const DBFile, WALFile, SHMFile: AnsiString);
  end;

var
  SettingsForm: TSettingsForm;

implementation

{$R *.lfm}

{ TSettingsForm }

//Open Folder
function TSettingsForm.OpenFolder(const FolderName: AnsiString): Boolean;
var FolderNameFixed: AnsiString;
begin
  Result := false;
  try
    FolderNameFixed := trim(FolderName);
    if not(length(FolderNameFixed) >= 1) then
    begin
      MessageDlg('Error', 'Folder name not specified!', mtError, [mbOK], 0);
      Exit;
    end;
    if not(DirectoryExists(FolderNameFixed)) then
    begin
      MessageDlg('Error', 'Folder does not exist: ' + FolderNameFixed, mtError, [mbOK], 0);
      Exit;
    end;
    OpenDocument(FolderNameFixed);
    Result := true;
  except
    on x: Exception do
      MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);
  end;
end;

//Enable or disable LLM server
procedure TSettingsForm.EnableLLMcheckBoxChange(Sender: TObject);
var enable_llm: boolean;
begin
  try
    enable_llm := EnableLLMcheckBox.Checked;
    ModelLabel.Enabled := enable_llm;
    ModelComboBox.Enabled := enable_llm;
    AddModelButton.Enabled := enable_llm;
    ParameterGroupBox.Enabled := enable_llm;
  except
    on x: Exception do
      MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);
  end;
end;

//Clear Engine Combobox
procedure TSettingsForm.ClearEngineComboBox;
var i: Integer;
begin
  try
    EngineLabel.Enabled := false;
    LlamaEngineComboBox.Enabled := false;
    if not(LlamaEngineComboBox.Items.Count >= 1) then Exit;
    for i := 0 to LlamaEngineComboBox.Items.Count - 1 do
    begin
      try
        if not(Assigned(LlamaEngineComboBox.Items.Objects[i])) then continue;
        LlamaEngineComboBox.Items.Objects[i].Free;
      except
        on x: Exception do
          MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);
      end;
    end;
    LlamaEngineComboBox.Items.Clear;
  except
    on x: Exception do
      MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);
  end;
end;

//Clear Device Combobox
procedure TSettingsForm.ClearDeviceComboBox;
var i: Integer;
begin
  try
    DeviceLabel.Enabled := false;
    DeviceComboBox.Enabled := false;
    if not(DeviceComboBox.Items.Count >= 1) then Exit;
    for i := 0 to DeviceComboBox.Items.Count - 1 do
    begin
      try
        if not(Assigned(DeviceComboBox.Items.Objects[i])) then continue;
        DeviceComboBox.Items.Objects[i].Free;
      except
        on x: Exception do
          MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);
      end;
    end;
    DeviceComboBox.Items.Clear;
  except
    on x: Exception do
      MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);
  end;
end;

//Load LLM files
procedure TSettingsForm.LoadLLMfiles(const LLMtype: string; const DefaultFile: string = '');
var
  LLMtypeFixed, ModelFile, EmbeddingModelFile, DefaultFileFixed: string;
  FoundIndex: Integer;
  SR: TSearchRec;
begin
  try
    //Validate parameter and variables
    LLMtypeFixed := uppercase(trim(LLMtype));
    if not(length(LLMtypeFixed) >= 1) then
    begin
      MessageDlg('Error', 'LLM type not specified!', mtError, [mbOK], 0);
      Exit;
    end;
    FoundIndex := -1;
    DefaultFileFixed := trim(DefaultFile);
    //Load conversational models
    if LLMtypeFixed = 'CONVERSATIONAL' then
    begin
      if not(length(modeldir) >= 1) then
      begin
        MessageDlg('Error', 'LLM directory not specified!', mtError, [mbOK], 0);
        Exit;
      end;
      if not(DirectoryExists(modeldir)) then
      begin
        MessageDlg('Error', 'LLM directory does not exist: ' + modeldir, mtError, [mbOK], 0);
        Exit;
      end;
      ModelComboBox.Items.Clear;
      ModelComboBox.ItemIndex := -1;
      if FindFirst(modeldir + '*.gguf', faAnyFile, SR) = 0 then
      begin
        try
          repeat
            if not((SR.Attr and faDirectory) = 0) then continue;
            ModelFile := trim(SR.Name);
            if (Pos(' ', ModelFile) > 0) or (Pos(PathDelim, ModelFile) > 0) then continue;
            ModelComboBox.Items.Add(ModelFile);
          until not(FindNext(SR) = 0);
        finally
          FindClose(SR);
        end;
      end;
      if ModelComboBox.Items.Count >= 1 then
      begin
        if length(DefaultFileFixed) >= 1 then FoundIndex := ModelComboBox.Items.IndexOf(DefaultFileFixed);
        ModelComboBox.ItemIndex := max(FoundIndex, 0);
        if (ModelComboBox.Items.Count > 1) and EnableLLMcheckBox.Checked then ModelComboBox.Enabled := true;
      end;
      if (ModelComboBox.Items.Count <= 1) or not(EnableLLMcheckBox.Checked) then ModelComboBox.Enabled := false;
      Exit;
    end;
    //Load embedding models
    if LLMtypeFixed = 'EMBEDDING' then
    begin
      if not(length(embeddingModeldir) >= 1) then
      begin
        MessageDlg('Error', 'Embedding directory not specified!', mtError, [mbOK], 0);
        Exit;
      end;
      if not(DirectoryExists(embeddingModeldir)) then
      begin
        MessageDlg('Error', 'Embedding directory does not exist: ' + embeddingModeldir, mtError, [mbOK], 0);
        Exit;
      end;
      EmbeddingModelComboBox.Items.Clear;
      EmbeddingModelComboBox.ItemIndex := -1;
      if FindFirst(embeddingModeldir + '*.gguf', faAnyFile, SR) = 0 then
      begin
        try
          repeat
            if not((SR.Attr and faDirectory) = 0) then continue;
            EmbeddingModelFile := trim(SR.Name);
            if (Pos(' ', EmbeddingModelFile) > 0) or (Pos(PathDelim, EmbeddingModelFile) > 0) then continue;
            EmbeddingModelComboBox.Items.Add(EmbeddingModelFile);
          until not(FindNext(SR) = 0);
        finally
          FindClose(SR);
        end;
      end;
      if EmbeddingModelComboBox.Items.Count >= 1 then
      begin
        EnableEmbeddingCheckBox.Enabled := true;
        if length(DefaultFileFixed) >= 1 then FoundIndex := EmbeddingModelComboBox.Items.IndexOf(DefaultFileFixed);
        EmbeddingModelComboBox.ItemIndex := max(FoundIndex, 0);
        if EmbeddingModelComboBox.Items.Count > 1 then EmbeddingModelComboBox.Enabled := true;
      end
      else
        EnableEmbeddingCheckBox.Enabled := false;
      if EmbeddingModelComboBox.Items.Count <= 1 then EmbeddingModelComboBox.Enabled := false;
      Exit;
    end;
    MessageDlg('Error', 'Invalid LLM type!', mtError, [mbOK], 0);
  except
    on x: Exception do
      MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);
  end;
end;

//Load persona from database (with confirmation dialog)
procedure TSettingsForm.LoadSelectedPersonaQuery;
begin
  try
    if DefaultPersonaComboBox.ItemIndex < 0 then Exit;
    if MessageDlg(
      'Load Default Persona',
      'Do you really want to load the selected persona from the database and discard current changes?',
      mtConfirmation,
      [mbYes, mbNo],
      0) = mrYes then
      LoadSelectedPersona;
  except
    on x: Exception do
      MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);
  end;
end;

//Clear Log
procedure TSettingsForm.ClearLog;
begin
  try
    if MainLLMserverProcessRunning then
    begin
      if not(length(logFile) >= 1) then
      begin
        MessageDlg('Error', 'Log file not specified!', mtError, [mbOK], 0);
        Exit;
      end;
      if not(FileExists(logFile)) then
      begin
        MessageDlg('Error', 'The log file does not exist: ' + logFile, mtError, [mbOK], 0);
        Exit;
      end;
      if not(MessageDlg(
        'Confirm Deletion',
        'Do you really want to clear the LLM service log?',
        mtConfirmation,
        [mbYes, mbNo],
        0) = mrYes) then Exit;
      deleteFile(logFile);
      ClearLogButton.Enabled := false;
      ShowMessage('Log file deleted: ' + logFile);
      Exit;
    end;
    if not(length(logDirectory) >= 1) then
    begin
      MessageDlg('Error', 'Log directory not specified!', mtError, [mbOK], 0);
      Exit;
    end;
    if not(DirectoryExists(logDirectory)) then
    begin
      MessageDlg('Error', 'Log directory does not exist: ' + logDirectory, mtError, [mbOK], 0);
      Exit;
    end;
    if not(MessageDlg(
      'Confirm Cleanup',
      'Do you really want to clear ALL logs in ' + logDirectory + '?',
      mtConfirmation,
      [mbYes, mbNo],
      0) = mrYes) then Exit;
    DeleteDirectory(logDirectory, true);
    ClearLogButton.Enabled := false;
    ShowMessage('All logs cleared recursively!');
  except
    on x: Exception do
      MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);
  end;
end;

//Clear temporary files and folders
procedure TSettingsForm.ClearTempDir;
begin
  try
    if MainLLMserverProcessRunning then
    begin
      if not(MessageDlg(
        'Confirm Cleanup',
        'Do you really want to clear the cache?',
        mtConfirmation,
        [mbYes, mbNo],
        0) = mrYes) then Exit;
    end
    else
    begin
      if not(MessageDlg(
        'Confirm Cleanup',
        'Do you really want to clear ALL temporary files, folders and the cache?',
        mtConfirmation,
        [mbYes, mbNo],
        0) = mrYes) then Exit;
      if length(TempDirectory) >= 1 then
      begin
        if DirectoryExists(TempDirectory) then DeleteDirectory(TempDirectory, true);
      end;
    end;
    if length(CacheDirectory) >= 1 then
    begin
      if DirectoryExists(CacheDirectory) then DeleteDirectory(CacheDirectory, false);
    end;
    ClearTempDirButton.Enabled := false;
    if MainLLMserverProcessRunning then
    begin
      ShowMessage('Cache cleared successfully!');
      Exit;
    end;
    ShowMessage('All temporary files, folders and the cache cleared successfully!');
  except
    on x: Exception do
      MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);
  end;
end;

//Copy file progressively while updating the progress bar (helper)
function TSettingsForm.CopyFileWithProgress(const SourceFile, DestFile: AnsiString): Boolean;
var
  SrcStream: TFileStream;
  DstStream: TFileStream;
  Buffer: array[0..65535] of Byte;
  TotalSize, Copied, ReadBytes: Int64;
  Percent: Integer;
  PForm: TProgressForm;
begin
  Result := false;
  SrcStream := nil;
  DstStream := nil;
  PForm := nil;
  try
    try
      PForm := TProgressForm.Create(Application);
      PForm.MainProgressBar.BarShowText := true;
      PForm.Show;
      Application.ProcessMessages;
      SrcStream := TFileStream.Create(SourceFile, fmOpenRead or fmShareDenyWrite);
      TotalSize := SrcStream.Size;
      if TotalSize <= 0 then
      begin
        PForm.Hide;
        MessageDlg('Error', 'Cannot import empty file: ' + SourceFile, mtError, [mbOK], 0);
        Exit;
      end;
      if FileExists(DestFile) then DeleteFile(DestFile);
      DstStream := TFileStream.Create(DestFile, fmCreate);
      Copied := 0;
      while Copied < TotalSize do
      begin
        ReadBytes := SrcStream.Read(Buffer, Min(Max(TotalSize - Copied, 0), SizeOf(Buffer)));
        if ReadBytes <= 0 then Break;
        DstStream.Write(Buffer, ReadBytes);
        Inc(Copied, ReadBytes);
        Percent := Min(Round((Copied / TotalSize) * 100), 100);
        PForm.MainProgressBar.Position := Percent;
        Application.ProcessMessages;
      end;
      if Copied = TotalSize then
      begin
        Result := true;
        PForm.Hide;
        ShowMessage('File successfully imported to: ' + DestFile);
        Exit;
      end;
      PForm.Hide;
      MessageDlg('Error', 'Failed to import file: ' + SourceFile, mtError, [mbOK], 0);
    except
      on x: Exception do
      begin
        if PForm.Visible then PForm.Hide;
        MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);
      end;
    end;
  finally
    if PForm.Visible then PForm.Hide;
    if Assigned(SrcStream) then FreeAndNil(SrcStream);
    if Assigned(DstStream) then FreeAndNil(DstStream);
    if Assigned(PForm) then FreeAndNil(PForm);
  end;
end;

//Call log clearing
procedure TSettingsForm.ClearLogButtonClick(Sender: TObject);
begin
  ClearLog;
end;

//Show title for each embedding parameter
procedure TSettingsForm.EmbeddingParameterListEditorMouseMove(Sender: TObject;
  Shift: TShiftState; X, Y: Integer);
var
  gc: TGridCoord;
  KeyName, NewHint: string;
begin
  try
    gc := EmbeddingParameterListEditor.MouseToCell(Point(X, Y));
    if (gc.Y <= 0) or (gc.Y >= EmbeddingParameterListEditor.RowCount) or (gc.X < 0) then Exit;
    KeyName := trim(EmbeddingParameterListEditor.Keys[gc.Y]);
    if KeyName = '' then
    begin
      EmbeddingParameterListEditor.Hint := '';
      Exit;
    end;
    NewHint := '';
    if Assigned(EmbeddingTitleList) then NewHint := EmbeddingTitleList.Values[KeyName];
    if NewHint = '' then NewHint := KeyName;
    if not(EmbeddingParameterListEditor.Hint = NewHint) then
    begin
      EmbeddingParameterListEditor.Hint := NewHint;
      Application.ActivateHint(Mouse.CursorPos);
    end;
  except
    {on x: Exception do
      MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);}
  end;
end;

//Enable or Disable Embedding Model
procedure TSettingsForm.EnableEmbeddingCheckBoxChange(Sender: TObject);
var enable_embedding: boolean;
begin
  try
    enable_embedding := EnableEmbeddingCheckBox.Checked;
    EmbeddingModelGroupBox.Enabled := enable_embedding;
    EmbeddingParameterGroupBox.Enabled := enable_embedding;
  except
    on x: Exception do
      MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);
  end;
end;

//Add Embedding Parameter
procedure TSettingsForm.AddEmbeddingParameterButtonClick(Sender: TObject);
var
  ParameterName: String;
  RowIndex: Integer;
begin
  try
    ParameterName := '';
    if not(InputQuery('New Parameter', 'Enter parameter name:', ParameterName)) then Exit;
    ParameterName := trim(ParameterName);
    if ParameterName = '' then
    begin
      MessageDlg('Error', 'Parameter name cannot be empty!', mtError, [mbOK], 0);
      Exit;
    end;
    if EmbeddingParameterListEditor.FindRow(ParameterName, RowIndex) then
    begin
      MessageDlg('Error', 'Parameter already exists!', mtError, [mbOK], 0);
      Exit;
    end;
    EmbeddingParameterListEditor.InsertRow(ParameterName, '', true);
  except
    on x: Exception do
      MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);
  end;
end;

//Import embedding model file
procedure TSettingsForm.AddEmbeddingModelButtonClick(Sender: TObject);
var FileToImport, FileExtension, BaseName, TargetFileName, TargetFilePath: ansistring;
begin
  try
    if not(length(embeddingModeldir) >= 1) then
    begin
      MessageDlg('Error', 'Embedding directory not specified!', mtError, [mbOK], 0);
      Exit;
    end;
    if not(ImportModelDialog.Execute) then
    begin
      chdir(appdir);
      Exit;
    end;
    FileToImport := trim(ImportModelDialog.FileName);
    if not(length(FileToImport) >= 1) then
    begin
      MessageDlg('Error', 'Embedding model filename not specified!', mtError, [mbOK], 0);
      chdir(appdir);
      Exit;
    end;
    if not(FileExists(FileToImport)) then
    begin
      MessageDlg('Error', 'The embedding model file doesn not exist: ' + FileToImport, mtError, [mbOK], 0);
      chdir(appdir);
      Exit;
    end;
    if
      not(MessageDlg(
        'Do you really want to import the model file?' + sLineBreak +
          'This may take a while and the application may seem unresponsive.',
        mtConfirmation,
        [mbYes, mbNo],
        0) = mrYes)
    then
    begin
      chdir(appdir);
      Exit;
    end;
    BaseName := trim(ExtractFileName(FileToImport));
    if not(length(BaseName) >= 1) then
    begin
      MessageDlg('Error', 'Invalid filename!', mtError, [mbOK], 0);
      chdir(appdir);
      Exit;
    end;
    FileExtension := trim(ExtractFileExt(BaseName));
    if not(length(FileExtension) >= 1) then
    begin
      MessageDlg('Error', 'Invalid file extension!', mtError, [mbOK], 0);
      chdir(appdir);
      Exit;
    end;
    BaseName := trim(ChangeFileExt(BaseName, ''));
    if not(length(BaseName) >= 1) then
    begin
      MessageDlg('Error', 'Invalid filename!', mtError, [mbOK], 0);
      chdir(appdir);
      Exit;
    end;
    BaseName := ReplaceRegExpr('[^a-zA-Z0-9_]', BaseName, '_');
    BaseName := ReplaceRegExpr('_+', BaseName, '_');
    TargetFileName := BaseName + FileExtension;
    TargetFilePath := embeddingModeldir + TargetFileName;
    ForceDirectories(ExtractFilePath(TargetFilePath));
    if CopyFileWithProgress(FileToImport, TargetFilePath) then
    begin
      chdir(appdir);
      LoadLLMfiles('EMBEDDING', String(TargetFileName));
      Exit;
    end;
    chdir(appdir);
  except
    on x: Exception do
    begin
      MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);
      chdir(appdir);
    end;
  end;
end;

//Import model file
procedure TSettingsForm.AddModelButtonClick(Sender: TObject);
var FileToImport, FileExtension, BaseName, TargetFileName, TargetFilePath: ansistring;
begin
  try
    if not(length(modeldir) >= 1) then
    begin
      MessageDlg('Error', 'LLM directory not specified!', mtError, [mbOK], 0);
      Exit;
    end;
    if not(ImportModelDialog.Execute) then
    begin
      chdir(appdir);
      Exit;
    end;
    FileToImport := trim(ImportModelDialog.FileName);
    if not(length(FileToImport) >= 1) then
    begin
      MessageDlg('Error', 'Model filename not specified!', mtError, [mbOK], 0);
      chdir(appdir);
      Exit;
    end;
    if not(FileExists(FileToImport)) then
    begin
      MessageDlg('Error', 'The model file doesn not exist: ' + FileToImport, mtError, [mbOK], 0);
      chdir(appdir);
      Exit;
    end;
    if
      not(MessageDlg(
        'Do you really want to import the model file?' + sLineBreak +
          'This may take a while and the application may seem unresponsive.',
        mtConfirmation,
        [mbYes, mbNo],
        0) = mrYes)
    then
    begin
      chdir(appdir);
      Exit;
    end;
    BaseName := trim(ExtractFileName(FileToImport));
    if not(length(BaseName) >= 1) then
    begin
      MessageDlg('Error', 'Invalid filename!', mtError, [mbOK], 0);
      chdir(appdir);
      Exit;
    end;
    FileExtension := trim(ExtractFileExt(BaseName));
    if not(length(FileExtension) >= 1) then
    begin
      MessageDlg('Error', 'Invalid file extension!', mtError, [mbOK], 0);
      chdir(appdir);
      Exit;
    end;
    BaseName := trim(ChangeFileExt(BaseName, ''));
    if not(length(BaseName) >= 1) then
    begin
      MessageDlg('Error', 'Invalid filename!', mtError, [mbOK], 0);
      chdir(appdir);
      Exit;
    end;
    BaseName := ReplaceRegExpr('[^a-zA-Z0-9_]', BaseName, '_');
    BaseName := ReplaceRegExpr('_+', BaseName, '_');
    TargetFileName := BaseName + FileExtension;
    TargetFilePath := modeldir + TargetFileName;
    ForceDirectories(ExtractFilePath(TargetFilePath));
    if CopyFileWithProgress(FileToImport, TargetFilePath) then
    begin
      chdir(appdir);
      LoadLLMfiles('CONVERSATIONAL', String(TargetFileName));
      Exit;
    end;
    chdir(appdir);
  except
    on x: Exception do
    begin
      MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);
      chdir(appdir);
    end;
  end;
end;

//Load default settings
procedure TSettingsForm.LoadDefaultConfig;
var
  engineItem: TEngineComboBoxItem;
  deviceItem: TDeviceComboBoxItem;
  configID, i, j: Integer;
  modelFromDB, embeddingModelFromDB: String;
  paramFound, embeddingParamFound: boolean;
  paramName, paramTitle, paramType, configName, configValue, output_line: String;
  foundDeviceEntry, foundDeviceHeader: boolean;
  SL: TStringList;
begin
  try
    saveSettingsError := false;
    EnableLLMcheckBox.Checked := true;
    EnableEmbeddingCheckBox.Checked := true;
    LLMloggingCheckBox.Checked := true;
    LLMproxyServicePort.Text := '';
    LLMproxyServiceTimeout.Value := 60;
    LLMproxyServiceMaxConnections.Value := 200;
    LLMproxyServiceMaxPackageSize.Value := 2097152;
    llmConversationalPort := 8080;
    llmEmbeddingPort := 8081;
    llmProxyLocation := '/llamacpp/';
    if LlamaEngineComboBox.ItemIndex < 0 then Exit;
    engineItem := TEngineComboBoxItem(LlamaEngineComboBox.Items.Objects[LlamaEngineComboBox.ItemIndex]);
    if engineItem = nil then Exit;
    configID := StrToIntDef(engineItem.ID, 0);
    if configID = 0 then Exit;
    if length(engineItem.ProxyPort) >= 1 then
      LLMproxyServicePort.Text := engineItem.ProxyPort;
    if engineItem.ProxyTimeout >= 1 then
      LLMproxyServiceTimeout.Value := engineItem.ProxyTimeout;
    if engineItem.ProxyMaxConnections >= 1 then
      LLMproxyServiceMaxConnections.Value := engineItem.ProxyMaxConnections;
    if engineItem.ProxyMaxPackageSize >= 1 then
      LLMproxyServiceMaxPackageSize.Value := engineItem.ProxyMaxPackageSize;
    ClearDeviceComboBox;
    ParameterListEditor.Strings.Clear;
    EmbeddingParameterListEditor.Strings.Clear;
    TitleList.Clear;
    EmbeddingTitleList.Clear;
    modelFromDB := '';
    embeddingModelFromDB := '';
    if not(LlamaDBconnection.Connected) then
    begin
      // DO NOT delete WAL/SHM files before opening - let SQLite handle them
      {if FileExists(wrapperDbFileWAL) then DeleteFile(wrapperDbFileWAL);
      if FileExists(wrapperDbFileSHM) then DeleteFile(wrapperDbFileSHM);}
      LlamaDBconnection.DatabaseName := wrapperDbFile;
      LlamaDBconnection.Open;
      LlamaTransaction.Active := true;
      // Set busy timeout to wait for transient locks instead of failing immediately
      LlamaDBconnection.ExecuteDirect('PRAGMA busy_timeout = 5000');
    end;
    ConfigDataQuery.Close;
    ConfigDataQuery.ParamByName('cid').AsInteger := configID;
    ConfigDataQuery.Open;
    paramFound := false;
    embeddingParamFound := false;
    foundDeviceEntry := false;
    foundDeviceHeader := false;
    while not(ConfigDataQuery.EOF) do
    begin
      paramName := trim(ConfigDataQuery.FieldByName('name').AsString);
      paramTitle := trim(ConfigDataQuery.FieldByName('title').AsString) + ': ' + trim(ConfigDataQuery.FieldByName('description').AsString);
      paramType := uppercase(trim(ConfigDataQuery.FieldByName('type_name').AsString));
      if SameText(paramName, 'model') then
      begin
        if paramType = 'EMBEDDING' then
          embeddingModelFromDB := trim(ConfigDataQuery.FieldByName('value').AsString)
        else
          modelFromDB := trim(ConfigDataQuery.FieldByName('value').AsString);
      end
      else if SameText(paramName, 'device') then
        foundDeviceEntry := true
      else
      begin
        if SameText(paramName, 'port') then
        begin
          if paramType = 'EMBEDDING' then
            llmEmbeddingPort := StrToIntDef(trim(ConfigDataQuery.FieldByName('value').AsString), 8081)
          else
            llmConversationalPort := StrToIntDef(trim(ConfigDataQuery.FieldByName('value').AsString), 8080);
        end;
        if paramType = 'EMBEDDING' then
        begin
          EmbeddingParameterListEditor.InsertRow(
            paramName,
            trim(ConfigDataQuery.FieldByName('value').AsString),
            true);
          EmbeddingTitleList.Values[paramName] := paramTitle;
          embeddingParamFound := true;
        end
        else
        begin
          ParameterListEditor.InsertRow(
            paramName,
            trim(ConfigDataQuery.FieldByName('value').AsString),
            true);
          TitleList.Values[ParamName] := paramTitle;
          paramFound := true;
        end;
      end;
      ConfigDataQuery.Next;
    end;
    ConfigDataQuery.Close;
    WebServerConfigQuery.Close;
    WebServerConfigQuery.Open;
    while not(WebServerConfigQuery.EOF) do
    begin
      configName := trim(WebServerConfigQuery.FieldByName('name').AsString);
      configValue := trim(WebServerConfigQuery.FieldByName('value').AsString);
      if SameText(configName, 'NGINX_HTTP_PORT') then
        NginxHTTPport.Value := StrToIntDef(configValue, 80)
      else if SameText(configName, 'NGINX_HTTPS_PORT') then
        NginxHTTPSport.Value := StrToIntDef(configValue, 443)
      else if SameText(configName, 'NGINX_SSL_CERTIFICATE') then
        SSLcertificate.Text := StringReplace(configValue, '/', PathDelim, [rfReplaceAll])
      else if SameText(configName, 'NGINX_SSL_KEY') then
        SSLkey.Text := StringReplace(configValue, '/', PathDelim, [rfReplaceAll])
      else if SameText(configName, 'NGINX_PROXY_LOCATION') then
        llmProxyLocation := configValue
      else if SameText(configName, 'PHP_HTTP_PORT') then
        PHPhttpPort.Value := StrToIntDef(configValue, 9000);
      WebServerConfigQuery.Next;
    end;
    WebServerConfigQuery.Close;
    PHPtimezoneCombobox.ItemIndex := DefaultPHPtimezone;
    try
      if foundDeviceEntry then
      begin
        SL := TStringList.Create;
        try
          chdir(appdir);
          LLMserverProcess.Executable := engineItem.ServerBinary;
          LLMserverProcess.CurrentDirectory := ExtractFilePath(engineItem.ServerBinary);
          LLMserverProcess.Execute;
          SL.LoadFromStream(LLMserverProcess.Output);
          if LLMserverProcess.Running then
          begin
            LLMserverProcess.Terminate(0);
            LLMserverProcess.WaitOnExit;
          end;
          LLMserverProcess.Active := false;
          if SL.Count >= 1 then
          begin
            try
              for i := 0 to SL.Count - 1 do
              begin
                output_line := trim(SL[i]);
                if not(foundDeviceHeader) then
                begin
                  if Pos('available devices:', lowercase(output_line)) > 0 then
                  begin
                    DeviceComboBox.Items.BeginUpdate;
                    foundDeviceHeader := true;
                  end;
                  continue;
                end;
                j := Pos(':', output_line);
                if not(j > 0) then continue;
                deviceItem := TDeviceComboBoxItem.Create;
                deviceItem.ID := trim(Copy(output_line, 1, j - 1));
                deviceItem.Title := deviceItem.ID + ': ' + trim(Copy(output_line, j + 1, length(output_line)));
                if (length(deviceItem.ID) >= 1) and (length(deviceItem.Title) >= 1) then
                begin
                  DeviceComboBox.Items.AddObject(deviceItem.Title, deviceItem);
                  continue;
                end;
                FreeAndNil(deviceItem);
              end;
            finally
              if foundDeviceHeader then DeviceComboBox.Items.EndUpdate;
            end;
            if DeviceComboBox.Items.Count >= 1 then
            begin
              DeviceComboBox.ItemIndex := 0;
              DeviceLabel.Enabled := true;
              DeviceComboBox.Enabled := true;
            end;
          end;
        finally
          FreeAndNil(SL);
        end;
      end;
      if not(DeviceComboBox.Items.Count >= 1) then
      begin
        DeviceComboBox.Items.Add('N/A');
        DeviceComboBox.ItemIndex := 0;
      end;
      if paramFound then ParameterListEditor.Row := 1;
      if embeddingParamFound then EmbeddingParameterListEditor.Row := 1;
      if not(modelFromDB = '') then
      begin
        ModelComboBox.ItemIndex := ModelComboBox.Items.IndexOf(modelFromDB);
        if ModelComboBox.ItemIndex = -1 then
        begin
          if ModelComboBox.Items.Count >= 1 then ModelComboBox.ItemIndex := 0;
          MessageDlg('Error', 'The selected language model not found in model directory!', mtError, [mbOK], 0);
        end;
      end;
      if not(embeddingModelFromDB = '') then
      begin
        EmbeddingModelComboBox.ItemIndex := EmbeddingModelComboBox.Items.IndexOf(embeddingModelFromDB);
        if EmbeddingModelComboBox.ItemIndex = -1 then
        begin
          if EmbeddingModelComboBox.Items.Count >= 1 then EmbeddingModelComboBox.ItemIndex := 0;
          MessageDlg('Error', 'The selected embedding model not found in model directory!', mtError, [mbOK], 0);
        end;
      end;
    finally
      LlamaTransaction.Active := false;
      LlamaDBconnection.Close;
      // Note: WAL/SHM files are managed by SQLite automatically. Do not delete them.
      {if FileExists(wrapperDbFileWAL) then DeleteFile(wrapperDbFileWAL);
      if FileExists(wrapperDbFileSHM) then DeleteFile(wrapperDbFileSHM);}
    end;
  except
    on x: Exception do
      MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);
  end;
end;

//Clear Persona Combobox
procedure TSettingsForm.ClearPersonaComboBox;
var i: Integer;
begin
  try
    DefaultPersonaComboBox.Enabled := false;
    LoadPersonaButton.Enabled := false;
    if not(DefaultPersonaComboBox.Items.Count >= 1) then Exit;
    for i := 0 to DefaultPersonaComboBox.Items.Count - 1 do
    begin
      try
        if not(Assigned(DefaultPersonaComboBox.Items.Objects[i])) then continue;
        DefaultPersonaComboBox.Items.Objects[i].Free;
      except
        on x: Exception do
          MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);
      end;
    end;
    DefaultPersonaComboBox.Items.Clear;
    DefaultPersonaComboBox.ItemIndex := -1;
  except
    on x: Exception do
      MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);
  end;
end;

//Load Default Persona from Database
procedure TSettingsForm.LoadBasePersonaList;
var personaItem: TPersonaComboBoxItem;
begin
  try
    ClearPersonaComboBox;
    if not(length(personaDbFile) >= 1) then
    begin
      MessageDlg('Error', 'Persona database not specified!', mtError, [mbOK], 0);
      Exit;
    end;
    chdir(appdir);
    if not(FileExists(personaDbFile)) then
    begin
      MessageDlg('Error', 'Persona database file does not exist: ' + personaDbFile, mtError, [mbOK], 0);
      Exit;
    end;
    {if FileExists(personaDbFileWAL) then DeleteFile(personaDbFileWAL);
    if FileExists(personaDbFileSHM) then DeleteFile(personaDbFileSHM);}
    try
      PersonaDBconnection.DatabaseName := personaDbFile;
      PersonaDBconnection.Open;
      // Set busy timeout to wait for transient locks instead of failing immediately
      PersonaDBconnection.ExecuteDirect('PRAGMA busy_timeout = 5000');
      if not(PersonaDBconnection.Connected) then
      begin
        MessageDlg('Error', 'Failed to connect to persona database!', mtError, [mbOK], 0);
        Exit;
      end;
      PersonaTransaction.Active := true;
      PersonaQuery.Open;
      while not(PersonaQuery.EOF) do
      begin
        try
          personaItem := TPersonaComboBoxItem.Create;
          personaItem.ID := trim(PersonaQuery.FieldByName('id').AsString);
          personaItem.Name := trim(PersonaQuery.FieldByName('name').AsString);
          personaItem.FullName := trim(PersonaQuery.FieldByName('full_name').AsString);
          personaItem.Description := trim(PersonaQuery.FieldByName('description').AsString);
          personaItem.SystemPrompt := trim(PersonaQuery.FieldByName('system_prompt').AsString);
          personaItem.SummaryPrompt := trim(PersonaQuery.FieldByName('summary_prompt').AsString);
          personaItem.InitialMessage := trim(PersonaQuery.FieldByName('initial_message').AsString);
          personaItem.BehaviorSimilarityThreshold := PersonaQuery.FieldByName('behavior_similarity_threshold').AsInteger;
          personaItem.Avatar := trim(PersonaQuery.FieldByName('avatar').AsString);
          personaItem.BackgroundImage := trim(PersonaQuery.FieldByName('background_image').AsString);
          personaItem.CSSoverride := trim(PersonaQuery.FieldByName('css_override').AsString);
          if (length(personaItem.FullName) >= 1) and (length(personaItem.Description) >= 1) then
            DefaultPersonaComboBox.Items.AddObject(personaItem.FullName + ': ' + personaItem.Description, personaItem)
          else if length(personaItem.FullName) >= 1 then
            DefaultPersonaComboBox.Items.AddObject(personaItem.FullName, personaItem)
          else
            DefaultPersonaComboBox.Items.AddObject(personaItem.Name, personaItem);
        except
          on x: Exception do
            MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);
        end;
        PersonaQuery.Next;
      end;
      PersonaQuery.Close;
      PersonaTransaction.Active := false;
      PersonaDBconnection.Close;
    finally
      // Note: WAL/SHM files are managed by SQLite automatically. Do not delete them.
      {if FileExists(personaDbFileWAL) then DeleteFile(personaDbFileWAL);
      if FileExists(personaDbFileSHM) then DeleteFile(personaDbFileSHM);}
    end;
    if DefaultPersonaComboBox.Items.Count >= 1 then
    begin
      DefaultPersonaComboBox.ItemIndex := 0;
      LoadPersonaButton.Enabled := true;
      if DefaultPersonaComboBox.Items.Count > 1 then DefaultPersonaComboBox.Enabled := true;
    end;
  except
    on x: Exception do
      MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);
  end;
end;

//Load Persona from JSON file
procedure TSettingsForm.LoadPersonaConfig;
var
  JSONData: TJSONData;
  RootObj: TJSONObject;
  JSONList: TStringList;
  paramValue: String;
  i, foundIndex: Integer;
  memoryModeID: integer;
  memoryModeNode: TJSONData;
  responseModeID: integer;
  responseModeNode: TJSONData;
begin
  try
    chdir(appdir);
    if not(length(personaConfigFile) >= 1) then
    begin
      LoadSelectedPersona;
      Exit;
    end;
    if not(FileExists(personaConfigFile)) then
    begin
      LoadSelectedPersona;
      Exit;
    end;
    JSONList := TStringList.Create;
    JSONData := nil;
    try
      JSONList.LoadFromFile(personaConfigFile);
      if not(length(JSONList.Text) >= 1) then
      begin
        LoadSelectedPersona;
        Exit;
      end;
      JSONData := GetJSON(JSONList.Text);
      if not(Assigned(JSONData)) then
      begin
        LoadSelectedPersona;
        Exit;
      end;
      if not(JSONData is TJSONObject) then
      begin
        LoadSelectedPersona;
        Exit;
      end;
      RootObj := TJSONObject(JSONData);
      paramValue := trim(RootObj.Get('personality', ''));
      if length(paramValue) >= 1 then
      begin
        if DefaultPersonaComboBox.Items.Count >= 1 then
        begin
          foundIndex := -1;
          for i := 0 to DefaultPersonaComboBox.Items.Count - 1 do
          begin
            if not(Assigned(DefaultPersonaComboBox.Items.Objects[i])) then continue;
            if not(DefaultPersonaComboBox.Items.Objects[i] is TPersonaComboBoxItem) then continue;
            if not(TPersonaComboBoxItem(DefaultPersonaComboBox.Items.Objects[i]).Name = paramValue) then continue;
            foundIndex := i;
            break;
          end;
          if foundIndex >= 0 then DefaultPersonaComboBox.ItemIndex := foundIndex;
        end;
      end;
      paramValue := trim(RootObj.Get('full_name', ''));
      if length(paramValue) >= 1 then PersonaFullName.Text := paramValue;
      paramValue := trim(RootObj.Get('description', ''));
      if length(paramValue) >= 1 then PersonaDescription.Text := paramValue;
      paramValue := trim(RootObj.Get('initial_message', ''));
      if length(paramValue) >= 1 then PersonaInitialMessage.Text := paramValue;
      paramValue := trim(RootObj.Get('system_prompt', ''));
      if length(paramValue) >= 1 then PersonaSystemPrompt.Lines.Text := paramValue;
      paramValue := trim(RootObj.Get('summary_prompt', ''));
      if length(paramValue) >= 1 then PersonaSummaryPrompt.Lines.Text := paramValue;
      paramValue := trim(RootObj.Get('css_override', ''));
      if length(paramValue) >= 1 then PersonaCSSoverride.Lines.Text := paramValue;
      paramValue := trim(RootObj.Get('behavior_similarity_threshold', ''));
      if length(paramValue) >= 1 then PersonaBehaviorSimilarityThreshold.Value := StrToIntDef(paramValue, 80);
      if PersonaMemoryMode.Items.Count >= 1 then
      begin
        PersonaMemoryMode.ItemIndex := 0;
        memoryModeNode := RootObj.Find('memory_mode');
        if Assigned(memoryModeNode) then
        begin
          foundIndex := -1;
          if memoryModeNode.JSONType = jtNumber then
            memoryModeID := memoryModeNode.AsInteger
          else
            memoryModeID := StrToIntDef(trim(memoryModeNode.AsString), 1);
          for i := 0 to PersonaMemoryMode.Items.Count - 1 do
          begin
            if not(Assigned(PersonaMemoryMode.Items.Objects[i])) then continue;
            if not(PersonaMemoryMode.Items.Objects[i] is TMemoryModeComboBoxItem) then continue;
            if not(TMemoryModeComboBoxItem(PersonaMemoryMode.Items.Objects[i]).ID = memoryModeID) then continue;
            foundIndex := i;
            break;
          end;
          if foundIndex >= 0 then PersonaMemoryMode.ItemIndex := foundIndex;
        end;
      end;
      if PersonaResponseMode.Items.Count >= 1 then
      begin
        PersonaResponseMode.ItemIndex := 0;
        responseModeNode := RootObj.Find('response_mode');
        if Assigned(responseModeNode) then
        begin
          foundIndex := -1;
          if responseModeNode.JSONType = jtNumber then
            responseModeID := responseModeNode.AsInteger
          else
            responseModeID := StrToIntDef(trim(responseModeNode.AsString), 1);
          for i := 0 to PersonaResponseMode.Items.Count - 1 do
          begin
            if not(Assigned(PersonaResponseMode.Items.Objects[i])) then continue;
            if not(PersonaResponseMode.Items.Objects[i] is TResponseModeComboBoxItem) then continue;
            if not(TResponseModeComboBoxItem(PersonaResponseMode.Items.Objects[i]).ID = responseModeID) then continue;
            foundIndex := i;
            break;
          end;
          if foundIndex >= 0 then PersonaResponseMode.ItemIndex := foundIndex;
        end;
      end;
      LoadPersonaImages(RootObj, 'avatar', PersonaAvatarImage);
      LoadPersonaImages(RootObj, 'background_image', PersonaBackgroundImage);
    finally
      if Assigned(JSONList) then FreeAndNil(JSONList);
      if Assigned(JSONData) then FreeAndNil(JSONData);
    end;
  except
    on x: Exception do
      MessageDlg('Error', 'Could not parse ' + personaConfigFile + ': ' + x.Message, mtError, [mbOK], 0);
  end;
end;

//Load images from JSON
procedure TSettingsForm.LoadPersonaImages(RootObj: TJSONObject; const FieldName: string; ImageControl: TImage);
var
  ImageJSONData: TJSONData;
  ImageJSONObj: TJSONObject;
  TempJSON: TJSONData;
  ImageBase64: String;
  ImageStream: TMemoryStream;
  DecodedStr: AnsiString;
  StoredFileName: string;
begin
  ImageControl.AutoSize := False;
  ImageControl.Proportional := True;
  ImageControl.Stretch := True;
  ImageControl.Center := True;
  ImageControl.Align := alNone;
  ImageControl.Picture.Clear;
  ImageControl.Constraints.MaxWidth := ImageControl.Width;
  ImageControl.Constraints.MaxHeight := ImageControl.Height;
  if ImageControl = PersonaAvatarImage then
    AvatarStoredFileName := ''
  else
    BackgroundStoredFileName := '';
  ImageStream := TMemoryStream.Create;
  TempJSON := nil;
  try
    ImageJSONData := RootObj.Find(FieldName);
    if not(Assigned(ImageJSONData)) then Exit;
    TempJSON := GetJSON(ImageJSONData.AsJSON);
    if not(Assigned(TempJSON)) then Exit;
    if not(TempJSON is TJSONObject) then Exit;
    ImageJSONObj := TJSONObject(TempJSON);
    StoredFileName := trim(ImageJSONObj.Get('filename', ''));
    if length(StoredFileName) >= 1 then
    begin
      if ImageControl = PersonaAvatarImage then
        AvatarStoredFileName := StoredFileName
      else
        BackgroundStoredFileName := StoredFileName;
    end;
    ImageBase64 := trim(ImageJSONObj.Get('content', ''));
    if not(length(ImageBase64) >= 1) then Exit;
    try
      DecodedStr := DecodeStringBase64(ImageBase64);
      if Length(DecodedStr) > 0 then
      begin
        ImageStream.Clear;
        ImageStream.WriteBuffer(DecodedStr[1], Length(DecodedStr));
        ImageStream.Position := 0;
        ImageControl.Picture.LoadFromStream(ImageStream);
        if ImageControl = PersonaAvatarImage then
        begin
          try
            if Assigned(AvatarImageData) then FreeAndNil(AvatarImageData);
          except
            on x: Exception do
              MessageDlg('Error', 'Image processing error: ' + x.Message, mtError, [mbOK], 0);
          end;
          AvatarImageData := TMemoryStream.Create;
          AvatarImageData.LoadFromStream(ImageStream);
          AvatarImageData.Position := 0;
        end
        else if ImageControl = PersonaBackgroundImage then
        begin
          try
            if Assigned(BackgroundImageData) then FreeAndNil(BackgroundImageData);
          except
            on x: Exception do
              MessageDlg('Error', 'Image processing error: ' + x.Message, mtError, [mbOK], 0);
          end;
          BackgroundImageData := TMemoryStream.Create;
          BackgroundImageData.LoadFromStream(ImageStream);
          BackgroundImageData.Position := 0;
        end;
      end;
    except
      ImageControl.Picture.Clear;
    end;
  finally
    if Assigned(TempJSON) then FreeAndNil(TempJSON);
    FreeAndNil(ImageStream);
  end;
end;

//Get image as base64 string
function TSettingsForm.GetImageBase64(ImageControl: TImage): AnsiString;
var
  TempStream: TMemoryStream;
  Source: TStream;
begin
  Result := '';
  if not(Assigned(ImageControl)) then Exit;
  if not(Assigned(ImageControl.Picture.Graphic)) then Exit;
  if ImageControl.Picture.Graphic.Empty then Exit;
  TempStream := TMemoryStream.Create;
  try
    // 1. Default to saving the current graphic
    ImageControl.Picture.Graphic.SaveToStream(TempStream);
    Source := TempStream;
    // 2. Override with high-quality cache only if it exists
    if (ImageControl = PersonaAvatarImage) then
    begin
      if Assigned(AvatarImageData) then Source := AvatarImageData;
    end;
    if (ImageControl = PersonaBackgroundImage) then
    begin
      if Assigned(BackgroundImageData) then Source := BackgroundImageData;
    end;
    // 3. Final conversion from the chosen source
    if not(Source.Size > 0) then Exit;
    Source.Position := 0;
    Result := EncodeStringBase64(StreamToString(Source));
  finally
    FreeAndNil(TempStream);
  end;
end;

//Load selected persona
procedure TSettingsForm.DefaultPersonaComboBoxChange(Sender: TObject);
begin
  LoadSelectedPersonaQuery;
end;

//Call temporary files and folders cleanup
procedure TSettingsForm.ClearTempDirButtonClick(Sender: TObject);
begin
  ClearTempDir;
end;

{ Converts a stream to its string representation. }
function TSettingsForm.StreamToString(Stream: TStream): string;
var StringStream: TStringStream;
begin
  Result := '';
  StringStream := TStringStream.Create('');
  try
    StringStream.CopyFrom(Stream, 0);
    Result := StringStream.DataString;
  finally
    FreeAndNil(StringStream);
  end;
end;

{ Gets the image format string from a filename extension. Returns 'png', 'jpg', 'bmp', 'gif', or 'tiff' based on file extension. }
function GetImageFormatFromFileName(const FileName: AnsiString): string;
var Ext: string;
begin
  Result := 'png';
  Ext := lowercase(trim(ExtractFileExt(FileName)));
  if (Ext = '.jpg') or (Ext = '.jpeg') then
  begin
    Result := 'jpg';
    Exit;
  end;
  if Ext = '.png' then
  begin
    Result := 'png';
    Exit;
  end;
  if Ext = '.bmp' then
  begin
    Result := 'bmp';
    Exit;
  end;
  if Ext = '.gif' then
  begin
    Result := 'gif';
    Exit;
  end;
  if (Ext = '.tiff') or (Ext = '.tif') then
    Result := 'tiff';
end;

//Get image filename
function TSettingsForm.GetImageFileName(ImageControl: TImage): string;
var FormatExt: string;
begin
  Result := 'image.png';
  if not(Assigned(ImageControl)) then Exit;
  if not(Assigned(ImageControl.Picture.Graphic)) then Exit;
  FormatExt := '';
  if ImageControl = PersonaAvatarImage then
    FormatExt := AvatarImageFormat
  else if ImageControl = PersonaBackgroundImage then
    FormatExt := BackgroundImageFormat
  else
    FormatExt := 'png';
  if FormatExt = '' then FormatExt := 'png';
  Result := 'image.' + FormatExt;
end;

//Open SSL certificate
procedure TSettingsForm.OpenSSLcertificateButtonClick(Sender: TObject);
var SSLcertificateFullPath, SSLcertificateFilePath, SSLcertificateFileName: AnsiString;
begin
  try
    OpenCertificateDialog.InitialDir := sslCertificateDir;
    if not(OpenCertificateDialog.Execute) then
    begin
      chdir(appdir);
      Exit;
    end;
    SSLcertificateFullPath := trim(OpenCertificateDialog.FileName);
    if not(length(SSLcertificateFullPath) >= 1) then
    begin
      MessageDlg('Error', 'Certificate not specified!', mtError, [mbOK], 0);
      chdir(appdir);
      Exit;
    end;
    if FileExists(SSLcertificateFullPath) then
      SSLcertificate.Text := trim(ExtractRelativePath(appdir, SSLcertificateFullPath))
    else
    begin
      SSLcertificateFilePath := IncludeTrailingPathDelimiter(ExtractFilePath(SSLcertificateFullPath));
      if not(DirectoryExists(SSLcertificateFilePath)) then
      begin
        MessageDlg('Error', 'SSL certificate directory not found: ' + SSLcertificateFilePath, mtError, [mbOK], 0);
        chdir(appdir);
        Exit;
      end;
      SSLcertificateFilePath := trim(IncludeTrailingPathDelimiter(ExtractRelativePath(appdir, SSLcertificateFilePath)));
      if SSLcertificateFilePath = PathDelim then SSLcertificateFilePath := '';
      SSLcertificateFileName := trim(ExtractFileName(SSLcertificateFullPath));
      SSLcertificate.Text := SSLcertificateFilePath + SSLcertificateFileName;
    end;
    chdir(appdir);
  except
    on x: Exception do
    begin
      MessageDlg('Error', 'Error loading image: ' + x.Message, mtError, [mbOK], 0);
      chdir(appdir);
    end;
  end;
end;

//Open SSL key
procedure TSettingsForm.OpenSSLkeyButtonClick(Sender: TObject);
var SSLkeyFullPath, SSLkeyFilePath, SSLkeyFileName: AnsiString;
begin
  try
    OpenKeyDialog.InitialDir := sslCertificateDir;
    if not(OpenKeyDialog.Execute) then
    begin
      chdir(appdir);
      Exit;
    end;
    SSLkeyFullPath := trim(OpenKeyDialog.FileName);
    if not(length(SSLkeyFullPath) >= 1) then
    begin
      MessageDlg('Error', 'Key not specified!', mtError, [mbOK], 0);
      chdir(appdir);
      Exit;
    end;
    if FileExists(SSLkeyFullPath) then
      SSLkey.Text := trim(ExtractRelativePath(appdir, SSLkeyFullPath))
    else
    begin
      SSLkeyFilePath := IncludeTrailingPathDelimiter(ExtractFilePath(SSLkeyFullPath));
      if not(DirectoryExists(SSLkeyFilePath)) then
      begin
        MessageDlg('Error', 'SSL key directory not found: ' + SSLkeyFilePath, mtError, [mbOK], 0);
        chdir(appdir);
        Exit;
      end;
      SSLkeyFilePath := trim(IncludeTrailingPathDelimiter(ExtractRelativePath(appdir, SSLkeyFilePath)));
      if SSLkeyFilePath = PathDelim then SSLkeyFilePath := '';
      SSLkeyFileName := trim(ExtractFileName(SSLkeyFullPath));
      SSLkey.Text := SSLkeyFilePath + SSLkeyFileName;
    end;
    chdir(appdir);
  except
    on x: Exception do
    begin
      MessageDlg('Error', 'Error loading image: ' + x.Message, mtError, [mbOK], 0);
      chdir(appdir);
    end;
  end;
end;

//Open directory of temporary files and folders
procedure TSettingsForm.OpenTempDirButtonClick(Sender: TObject);
begin
  try
    if not(OpenFolder(TempDirectory)) then OpenTempDirButton.Enabled := false;
  except
    on x: Exception do
      MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);
  end;
end;

//Load Avatar Image
procedure TSettingsForm.PersonaAvatarImageClick(Sender: TObject);
var AvatarImagePath: AnsiString;
begin
  try
    if not(OpenImageDialog.Execute) then
    begin
      chdir(appdir);
      Exit;
    end;
    AvatarImagePath := trim(OpenImageDialog.FileName);
    if not(length(AvatarImagePath) >= 1) then
    begin
      MessageDlg('Error', 'Image file not specified!', mtError, [mbOK], 0);
      chdir(appdir);
      Exit;
    end;
    if not(FileExists(AvatarImagePath)) then
    begin
      MessageDlg('Error', 'The image file doesn not exist: ' + AvatarImagePath, mtError, [mbOK], 0);
      chdir(appdir);
      Exit;
    end;
    PersonaAvatarImage.AutoSize := False;
    PersonaAvatarImage.Proportional := True;
    PersonaAvatarImage.Stretch := True;
    PersonaAvatarImage.Center := True;
    PersonaAvatarImage.Align := alNone;
    PersonaAvatarImage.Picture.Clear;
    PersonaAvatarImage.Constraints.MaxWidth := PersonaAvatarImage.Width;
    PersonaAvatarImage.Constraints.MaxHeight := PersonaAvatarImage.Height;
    try
      if Assigned(AvatarImageData) then FreeAndNil(AvatarImageData);
    except
      on x: Exception do
        MessageDlg('Error', 'Image processing error: ' + x.Message, mtError, [mbOK], 0);
    end;
    AvatarImageData := TMemoryStream.Create;
    try
      AvatarImageData.LoadFromFile(AvatarImagePath);
      AvatarImageData.Position := 0;
      PersonaAvatarImage.Picture.LoadFromStream(AvatarImageData);
      AvatarImageFormat := GetImageFormatFromFileName(AvatarImagePath);
      AvatarStoredFileName := trim(ExtractFileName(AvatarImagePath));
    except
      on x: Exception do
      begin
        PersonaAvatarImage.Picture.Clear;
        AvatarImageFormat := '';
        MessageDlg('Error', 'Could not load image: ' + x.Message, mtError, [mbOK], 0);
      end;
    end;
    chdir(appdir);
  except
    on x: Exception do
    begin
      MessageDlg('Error', 'Error loading image: ' + x.Message, mtError, [mbOK], 0);
      chdir(appdir);
    end;
  end;
end;

//Load Background Image
procedure TSettingsForm.PersonaBackgroundImageClick(Sender: TObject);
var BackgroundImagePath: AnsiString;
begin
  try
    if not(OpenImageDialog.Execute) then
    begin
      chdir(appdir);
      Exit;
    end;
    BackgroundImagePath := trim(OpenImageDialog.FileName);
    if not(length(BackgroundImagePath) >= 1) then
    begin
      MessageDlg('Error', 'Image file not specified!', mtError, [mbOK], 0);
      chdir(appdir);
      Exit;
    end;
    if not(FileExists(BackgroundImagePath)) then
    begin
      MessageDlg('Error', 'The image file doesn not exist: ' + BackgroundImagePath, mtError, [mbOK], 0);
      chdir(appdir);
      Exit;
    end;
    PersonaBackgroundImage.AutoSize := False;
    PersonaBackgroundImage.Proportional := True;
    PersonaBackgroundImage.Stretch := True;
    PersonaBackgroundImage.Center := True;
    PersonaBackgroundImage.Align := alNone;
    PersonaBackgroundImage.Picture.Clear;
    PersonaBackgroundImage.Constraints.MaxWidth := PersonaBackgroundImage.Width;
    PersonaBackgroundImage.Constraints.MaxHeight := PersonaBackgroundImage.Height;
    try
      if Assigned(BackgroundImageData) then FreeAndNil(BackgroundImageData);
    except
      on x: Exception do
        MessageDlg('Error', 'Image processing error: ' + x.Message, mtError, [mbOK], 0);
    end;
    BackgroundImageData := TMemoryStream.Create;
    try
      BackgroundImageData.LoadFromFile(BackgroundImagePath);
      BackgroundImageData.Position := 0;
      PersonaBackgroundImage.Picture.LoadFromStream(BackgroundImageData);
      BackgroundImageFormat := GetImageFormatFromFileName(BackgroundImagePath);
      BackgroundStoredFileName := trim(ExtractFileName(BackgroundImagePath));
    except
      on x: Exception do
      begin
        PersonaBackgroundImage.Picture.Clear;
        BackgroundImageFormat := '';
        MessageDlg('Error', 'Could not load image: ' + x.Message, mtError, [mbOK], 0);
      end;
    end;
    chdir(appdir);
  except
    on x: Exception do
    begin
      MessageDlg('Error', 'Error loading image: ' + x.Message, mtError, [mbOK], 0);
      chdir(appdir);
    end;
  end;
end;

//Load selected persona from combobox to form
procedure TSettingsForm.LoadSelectedPersona;
var
  personaItem: TPersonaComboBoxItem;
  ImageJSONData: TJSONData;
  ImageJSONObj: TJSONObject;
  ImageJSONList: TStringList;
  ImageBase64: String;
  ImageStream: TMemoryStream;
  ImageFileName: string;
  procedure ProcessImage(const JSONStr: AnsiString; TargetImage: TImage);
    var ImageFileName: string;
    begin
      TargetImage.AutoSize := False;
      TargetImage.Proportional := True;
      TargetImage.Stretch := True;
      TargetImage.Center := True;
      TargetImage.Align := alNone;
      TargetImage.Picture.Clear;
      TargetImage.Constraints.MaxWidth := TargetImage.Width;
      TargetImage.Constraints.MaxHeight := TargetImage.Height;
      if TargetImage = PersonaAvatarImage then
        AvatarStoredFileName := ''
      else
        BackgroundStoredFileName := '';
      if length(JSONStr) < 1 then
      begin
        TargetImage.Picture.Clear;
        Exit;
      end;
      try
        ImageJSONList.Text := JSONStr;
        ImageJSONData := GetJSON(ImageJSONList.Text);
        if not(Assigned(ImageJSONData)) then
        begin
          TargetImage.Picture.Clear;
          Exit;
        end;
        if not(ImageJSONData is TJSONObject) then
        begin
          TargetImage.Picture.Clear;
          Exit;
        end;
        ImageJSONObj := TJSONObject(ImageJSONData);
        ImageFileName := trim(ImageJSONObj.Get('filename', ''));
        if length(ImageFileName) >= 1 then
        begin
          if TargetImage = PersonaAvatarImage then
            AvatarStoredFileName := ImageFileName
          else
            BackgroundStoredFileName := ImageFileName;
        end;
        ImageBase64 := trim(ImageJSONObj.Get('content', ''));
        if not(length(ImageBase64) >= 1) then
        begin
          TargetImage.Picture.Clear;
          Exit;
        end;
        ImageStream.Clear;
        ImageStream.WriteBuffer(DecodeStringBase64(ImageBase64)[1], Length(DecodeStringBase64(ImageBase64)));
        ImageStream.Position := 0;
        TargetImage.Picture.LoadFromStream(ImageStream);
        if TargetImage = PersonaAvatarImage then
        begin
          try
            if Assigned(AvatarImageData) then FreeAndNil(AvatarImageData);
          except
            on x: Exception do
              MessageDlg('Error', 'Image processing error: ' + x.Message, mtError, [mbOK], 0);
          end;
          AvatarImageData := TMemoryStream.Create;
          AvatarImageData.LoadFromStream(ImageStream);
          AvatarImageData.Position := 0;
        end
        else if TargetImage = PersonaBackgroundImage then
        begin
          try
            if Assigned(BackgroundImageData) then FreeAndNil(BackgroundImageData);
          except
            on x: Exception do
              MessageDlg('Error', 'Image processing error: ' + x.Message, mtError, [mbOK], 0);
          end;
          BackgroundImageData := TMemoryStream.Create;
          BackgroundImageData.LoadFromStream(ImageStream);
          BackgroundImageData.Position := 0;
        end;
      finally
        if Assigned(ImageJSONData) then FreeAndNil(ImageJSONData);
      end;
    end;
begin
  try
    if DefaultPersonaComboBox.ItemIndex < 0 then Exit;
    if not(DefaultPersonaComboBox.Items.Objects[DefaultPersonaComboBox.ItemIndex] is TPersonaComboBoxItem) then Exit;
    personaItem := TPersonaComboBoxItem(DefaultPersonaComboBox.Items.Objects[DefaultPersonaComboBox.ItemIndex]);
    PersonaFullName.Text := personaItem.FullName;
    PersonaDescription.Text := personaItem.Description;
    PersonaInitialMessage.Text := personaItem.InitialMessage;
    PersonaSystemPrompt.Lines.Text := personaItem.SystemPrompt;
    PersonaSummaryPrompt.Lines.Text := personaItem.SummaryPrompt;
    PersonaCSSoverride.Lines.Text := personaItem.CSSoverride;
    if personaItem.BehaviorSimilarityThreshold >= 1 then
      PersonaBehaviorSimilarityThreshold.Value := personaItem.BehaviorSimilarityThreshold
    else
      PersonaBehaviorSimilarityThreshold.Value := 80;
    ImageJSONList := TStringList.Create;
    ImageStream := TMemoryStream.Create;
    ImageJSONData := nil;
    try
      ProcessImage(personaItem.Avatar, PersonaAvatarImage);
      ProcessImage(personaItem.BackgroundImage, PersonaBackgroundImage);
    finally
      FreeAndNil(ImageJSONList);
      FreeAndNil(ImageStream);
    end;
  except
    on x: Exception do
      MessageDlg('Error', 'Error loading persona: ' + x.Message, mtError, [mbOK], 0);
  end;
end;

//Handle LLM engine change
procedure TSettingsForm.LlamaEngineComboBoxChange(Sender: TObject);
begin
  try
    if canHandleEngineChange then
    begin
      if MessageDlg(
           'Load Defaults',
           'Load default configuration for the selected engine?',
           mtConfirmation,
           [mbYes, mbNo],
           0
         ) = mrYes then
        LoadDefaultConfig;
    end;
  except
    on x: Exception do
      MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);
  end;
end;

//Enable or Disable Proxy Service settings
procedure TSettingsForm.LLMproxyServicePortChange(Sender: TObject);
var settings_enabled: boolean;
begin
  try
    settings_enabled := (length(trim(LLMproxyServicePort.Text)) >= 1);
    LLMproxyServiceTimeout.Enabled := settings_enabled;
    TimeoutLabel.Enabled := settings_enabled;
    LLMproxyServiceMaxConnections.Enabled := settings_enabled;
    MaxConnectionsLabel.Enabled := settings_enabled;
    LLMproxyServiceMaxPackageSize.Enabled := settings_enabled;
    MaxPackageSizeLabel.Enabled := settings_enabled;
  except
    on x: Exception do
      MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);
  end;
end;

//Load configuration
procedure TSettingsForm.FormShow(Sender: TObject);
var SR: TSearchRec;
begin
  try
    chdir(appdir);
    saveSettingsError := false;
    OpenLogFolderButton.Enabled := false;
    ClearLogButton.Enabled := false;
    if length(logDirectory) >= 1 then
    begin
      if DirectoryExists(logDirectory) then
      begin
        OpenLogFolderButton.Enabled := true;
        if MainLLMserverProcessRunning then
        begin
          if length(logFile) >= 1 then
          begin
            if FileExists(logFile) then
              ClearLogButton.Enabled := true;
          end;
        end
        else
        begin
          if FindFirst(logDirectory + '*', faAnyFile, SR) = 0 then
          begin
            try
              repeat
                if SR.Name = '.' then continue;
                if SR.Name = '..' then continue;
                ClearLogButton.Enabled := true;
                break;
              until not(FindNext(SR) = 0);
            finally
              SysUtils.FindClose(SR);
            end;
          end;
        end;
      end;
    end;
    OpenTempDirButton.Enabled := false;
    ClearTempDirButton.Enabled := false;
    if length(TempDirectory) >= 1 then
    begin
      if DirectoryExists(TempDirectory) then
      begin
        OpenTempDirButton.Enabled := true;
        if not(MainLLMserverProcessRunning) then
        begin
          if FindFirst(TempDirectory + '*', faAnyFile, SR) = 0 then
          begin
            try
              repeat
                if SR.Name = '.' then continue;
                if SR.Name = '..' then continue;
                ClearTempDirButton.Enabled := true;
                break;
              until not(FindNext(SR) = 0);
            finally
              SysUtils.FindClose(SR);
            end;
          end;
        end;
      end;
    end;
    if not(ClearTempDirButton.Enabled) then
    begin
      if length(CacheDirectory) >= 1 then
      begin
        if DirectoryExists(CacheDirectory) then ClearTempDirButton.Enabled := true;
      end;
    end;
    if LlamaEngineComboBox.Items.Count = 0 then Exit;
    canHandleEngineChange := false;
    LoadConfigData;
    LoadBasePersonaList;
    LoadPersonaConfig;
    canHandleEngineChange := true;
    SettingsPageControl.TabIndex := 0;
  except
    on x: Exception do
      MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);
  end;
end;

//Load JSON Configuration
procedure TSettingsForm.LoadConfigData;
var
  JSONData, EngineNode, LLMnode, EmbeddingNode, LogNode: TJSONData;
  WebServerData, ProxyPortNode, ProxyTimeoutNode, ProxyMaxConnectionsNode, ProxyMaxPackageSizeNode: TJSONData;
  httpPortNode, httpsPortNode, sslCertNode, sslKeyNode, phpPortNode: TJSONData;
  RootObj, ParamsObj, WebServerObj: TJSONObject;
  JSONList: TStringList;
  loadedEngineID, loadedModel, loadedEmbeddingModel, loadedTimezone: String;
  item: TEngineComboBoxItem;
  i, foundIndex: Integer;
  paramFound: boolean;
  paramName, paramValue: String;
begin
  saveSettingsError := false;
  JSONList := TStringList.Create;
  JSONData := nil;
  try
    try
      chdir(appdir);
      if not(FileExists(wrapperConfigFile)) then
      begin
        if LlamaEngineComboBox.Items.Count > 0 then
        begin
          LlamaEngineComboBox.ItemIndex := 0;
          LoadDefaultConfig;
        end;
        Exit;
      end;
      JSONList.LoadFromFile(wrapperConfigFile);
      JSONData := GetJSON(JSONList.Text);
      if not(JSONData is TJSONObject) then Exit;
      RootObj := TJSONObject(JSONData);
      EngineNode := RootObj.Find('llama_engine');
      if Assigned(EngineNode) then
        loadedEngineID := trim(EngineNode.AsString)
      else
        loadedEngineID := '';
      if not(loadedEngineID = '') then
      begin
        if LlamaEngineComboBox.Items.Count >= 1 then
        begin
          for i := 0 to LlamaEngineComboBox.Items.Count - 1 do
          begin
            item := TEngineComboBoxItem(LlamaEngineComboBox.Items.Objects[i]);
            if not(Assigned(item)) then continue;
            if not(item.ID = loadedEngineID) then continue;
            LlamaEngineComboBox.ItemIndex := i;
            //We must trigger LoadDefaultConfig here because changing the engine
            //usually changes which parameters and models are valid in the DB
            LoadDefaultConfig;
            break;
          end;
        end;
      end;
      if DeviceComboBox.Enabled and (DeviceComboBox.Items.Count >= 1) then
      begin
        paramName := trim(RootObj.Get('llama_device', ''));
        if not(paramName = '') then
        begin
          foundIndex := -1;
          for i := 0 to DeviceComboBox.Items.Count -1 do
          begin
             if TDeviceComboBoxItem(DeviceComboBox.Items.Objects[i]).ID = paramName then
             begin
               foundIndex := i;
               break;
             end;
          end;
          if not(foundIndex = -1) then DeviceComboBox.ItemIndex := foundIndex;
        end;
      end;
      loadedModel := trim(RootObj.Get('model', ''));
      if not(loadedModel = '') then
      begin
        foundIndex := ModelComboBox.Items.IndexOf(loadedModel);
        if foundIndex = -1 then
        begin
          if ModelComboBox.Items.Count >= 1 then ModelComboBox.ItemIndex := 0;
          MessageDlg('Error', 'The selected model not found in model directory!', mtError, [mbOK], 0);
        end
        else
          ModelComboBox.ItemIndex := foundIndex;
      end;
      loadedEmbeddingModel := trim(RootObj.Get('embedding_model', ''));
      if not(loadedEmbeddingModel = '') then
      begin
        foundIndex := EmbeddingModelComboBox.Items.IndexOf(loadedEmbeddingModel);
        if foundIndex = -1 then
        begin
          if EmbeddingModelComboBox.Items.Count >= 1 then EmbeddingModelComboBox.ItemIndex := 0;
          MessageDlg('Error', 'The selected model not found in embedding directory!', mtError, [mbOK], 0);
        end
        else
          EmbeddingModelComboBox.ItemIndex := foundIndex;
      end;
      LLMnode := RootObj.Find('llm_enabled');
      if Assigned(LLMnode) then
      begin
        if LLMnode.JSONType = jtNumber then
          EnableLLMcheckBox.Checked := not(LLMnode.AsInteger = 0)
        else
          EnableLLMcheckBox.Checked := (IndexStr(LowerCase(trim(LLMnode.AsString)), ['0', 'false', 'no']) = -1);
      end;
      EmbeddingNode := RootObj.Find('embedding');
      if Assigned(EmbeddingNode) then
      begin
        if EmbeddingNode.JSONType = jtNumber then
          EnableEmbeddingCheckBox.Checked := not(EmbeddingNode.AsInteger = 0)
        else
          EnableEmbeddingCheckBox.Checked := (IndexStr(LowerCase(trim(EmbeddingNode.AsString)), ['0', 'false', 'no']) = -1);
      end;
      LogNode := RootObj.Find('logging');
      if Assigned(LogNode) then
      begin
        if LogNode.JSONType = jtNumber then
          LLMloggingCheckBox.Checked := not(LogNode.AsInteger = 0)
        else
          LLMloggingCheckBox.Checked := (IndexStr(LowerCase(trim(LogNode.AsString)), ['0', 'false', 'no']) = -1);
      end;
      ProxyPortNode := RootObj.Find('proxy_port');
      if Assigned(ProxyPortNode) then
        LLMproxyServicePort.Text := trim(ProxyPortNode.AsString)
      else
        LLMproxyServicePort.Text := '';
      ProxyTimeoutNode := RootObj.Find('proxy_timeout');
      if Assigned(ProxyTimeoutNode) then
      begin
        if ProxyTimeoutNode.JSONType = jtNumber then
          LLMproxyServiceTimeout.Value := ProxyTimeoutNode.AsInteger
        else
          LLMproxyServiceTimeout.Value := StrToIntDef(trim(ProxyTimeoutNode.AsString), 1);
      end
      else
        LLMproxyServiceTimeout.Value := 60;
      ProxyMaxConnectionsNode := RootObj.Find('max_proxy_connections');
      if Assigned(ProxyMaxConnectionsNode) then
      begin
        if ProxyMaxConnectionsNode.JSONType = jtNumber then
          LLMproxyServiceMaxConnections.Value := ProxyMaxConnectionsNode.AsInteger
        else
          LLMproxyServiceMaxConnections.Value := StrToIntDef(trim(ProxyMaxConnectionsNode.AsString), 1);
      end
      else
        LLMproxyServiceMaxConnections.Value := 200;
      ProxyMaxPackageSizeNode := RootObj.Find('max_package_size');
      if Assigned(ProxyMaxPackageSizeNode) then
      begin
        if ProxyMaxPackageSizeNode.JSONType = jtNumber then
          LLMproxyServiceMaxPackageSize.Value := ProxyMaxPackageSizeNode.AsInteger
        else
          LLMproxyServiceMaxPackageSize.Value := StrToIntDef(trim(ProxyMaxPackageSizeNode.AsString), 1);
      end
      else
        LLMproxyServiceMaxPackageSize.Value := 2097152;
      ParamsObj := RootObj.Get('parameters', TJSONObject(nil));
      if Assigned(ParamsObj) then
      begin
        paramFound := false;
        ParameterListEditor.Strings.Clear;
        for i := 0 to ParamsObj.Count - 1 do
        begin
          paramName := trim(ParamsObj.Names[i]);
          paramValue := trim(ParamsObj.Items[i].AsString);
          ParameterListEditor.InsertRow(paramName, paramValue, true);
          if Assigned(TitleList) and (TitleList.Values[paramName] = '') then
            TitleList.Values[paramName] := paramName;
          if SameText(paramName, 'port') then
            llmConversationalPort := StrToIntDef(paramValue, 8080);
          paramFound := true;
        end;
        if paramFound then ParameterListEditor.Row := 1;
      end;
      ParamsObj := RootObj.Get('embedding_parameters', TJSONObject(nil));
      if Assigned(ParamsObj) then
      begin
        paramFound := false;
        EmbeddingParameterListEditor.Strings.Clear;
        for i := 0 to ParamsObj.Count - 1 do
        begin
          paramName := trim(ParamsObj.Names[i]);
          paramValue := trim(ParamsObj.Items[i].AsString);
          EmbeddingParameterListEditor.InsertRow(paramName, paramValue, true);
          if Assigned(EmbeddingTitleList) and (EmbeddingTitleList.Values[paramName] = '') then
            EmbeddingTitleList.Values[paramName] := paramName;
          if SameText(paramName, 'port') then
            llmEmbeddingPort := StrToIntDef(paramValue, 8081);
          paramFound := true;
        end;
        if paramFound then EmbeddingParameterListEditor.Row := 1;
      end;
      WebServerData := RootObj.Find('webserver');
      if Assigned(WebServerData) then
      begin
        if WebServerData.JSONType = jtObject then
        begin
          WebServerObj := TJSONObject(WebServerData);
          httpPortNode := WebServerObj.Find('nginx_http_port');
          if Assigned(httpPortNode) then
          begin
            if httpPortNode.JSONType = jtNumber then
              NginxHTTPport.Value := httpPortNode.AsInteger
            else
              NginxHTTPport.Value := StrToIntDef(trim(httpPortNode.AsString), 80);
          end;
          httpsPortNode := WebServerObj.Find('nginx_https_port');
          if Assigned(httpsPortNode) then
          begin
            if httpsPortNode.JSONType = jtNumber then
              NginxHTTPSport.Value := httpsPortNode.AsInteger
            else
              NginxHTTPSport.Value := StrToIntDef(trim(httpsPortNode.AsString), 443);
          end;
          sslCertNode := WebServerObj.Find('nginx_ssl_certificate');
          if Assigned(sslCertNode) then
            SSLcertificate.Text := StringReplace(trim(sslCertNode.AsString), '/', PathDelim, [rfReplaceAll]);
          sslKeyNode := WebServerObj.Find('nginx_ssl_key');
          if Assigned(sslKeyNode) then
            SSLkey.Text := StringReplace(trim(sslKeyNode.AsString), '/', PathDelim, [rfReplaceAll]);
          phpPortNode := WebServerObj.Find('php_http_port');
          if Assigned(phpPortNode) then
          begin
            if phpPortNode.JSONType = jtNumber then
              PHPhttpPort.Value := phpPortNode.AsInteger
            else
              PHPhttpPort.Value := StrToIntDef(trim(phpPortNode.AsString), 9000);
          end;
          loadedTimezone := trim(WebServerObj.Get('php_timezone', ''));
          if not(loadedTimezone = '') then
          begin
            i := PHPtimezoneCombobox.Items.IndexOf(loadedTimezone);
            if i = -1 then
              PHPtimezoneComboBox.Text := loadedTimezone
            else
              PHPtimezoneCombobox.ItemIndex := i;
          end;
        end;
      end;
    except
      on x: Exception do
        MessageDlg('Error', 'Could not parse ' + wrapperConfigFile + ': ' + x.Message, mtError, [mbOK], 0);
    end;
  finally
    JSONData.Free;
    JSONList.Free;
  end;
end;

//Call Config Data Save (Apply button)
procedure TSettingsForm.ApplyButtonClick(Sender: TObject);
begin
  SaveConfigData;
end;

//Save Config Data
procedure TSettingsForm.SaveConfigData;
var
  RootObj, ParamsObj, PersonaObj, AvatarObj, BackgroundObj: TJSONObject;
  engineItem: TEngineComboBoxItem;
  deviceItem: TDeviceComboBoxItem;
  i: Integer;
  JSONList: TStringList;
  KeyName: String;
  NewValue: AnsiString;
  EngineID: Integer;
  DeviceID: string;
  ProxyPort: String;
  ProxyPortNumber: Integer;
  systemPrompt: AnsiString;
  summaryPrompt: AnsiString;
  cssOverride: AnsiString;
  phpConfigLines: TStringList;
  webserverConfigLines: TStringList;
  sslFullPath: AnsiString;
  sslRelPath: AnsiString;
  regexp: TRegExpr;
  PortsReserved: TStringList;
  redirectFileContent: TStringList;
begin
  RootObj := nil;
  JSONList := nil;
  ParamsObj := nil;
  PersonaObj := nil;
  AvatarObj := nil;
  BackgroundObj := nil;
  phpConfigLines := nil;
  webserverConfigLines := nil;
  PortsReserved := nil;
  redirectFileContent := nil;
  configDataSaved := false;
  saveSettingsError := false;
  RootObj := TJSONObject.Create;
  JSONList := TStringList.Create;
  PortsReserved := TStringList.Create;
  PortsReserved.Sorted := true;
  regexp := TRegExpr.Create;
  regexp.ModifierI := true;
  try
    try
      chdir(appdir);
      if not(EnableLLMcheckBox.Checked) and not(EnableEmbeddingCheckBox.Checked) then
        raise SaveSettingsFatal.Create('Error: no LLM/embedding server enabled! Unable to run server!');
      if EnableLLMcheckBox.Checked then
        RootObj.Add('llm_enabled', 1)
      else
        RootObj.Add('llm_enabled', 0);
      if not(LlamaEngineComboBox.ItemIndex = -1) then
      begin
        if Assigned(LlamaEngineComboBox.Items.Objects[LlamaEngineComboBox.ItemIndex]) then
        begin
          engineItem := TEngineComboBoxItem(LlamaEngineComboBox.Items.Objects[LlamaEngineComboBox.ItemIndex]);
          EngineID := StrToIntDef(trim(engineItem.ID), 0);
          if EngineID >= 1 then RootObj.Add('llama_engine', EngineID);
        end;
      end;
      if DeviceComboBox.Enabled and not(DeviceComboBox.ItemIndex = -1) then
      begin
        if Assigned(DeviceComboBox.Items.Objects[DeviceComboBox.ItemIndex]) then
        begin
          deviceItem := TDeviceComboBoxItem(DeviceComboBox.Items.Objects[DeviceComboBox.ItemIndex]);
          DeviceID := trim(deviceItem.ID);
          if length(DeviceID) >= 1 then RootObj.Add('llama_device', DeviceID);
        end;
      end;
      if LLMloggingCheckBox.Checked then
        RootObj.Add('logging', 1)
      else
        RootObj.Add('logging', 0);
      ProxyPort := trim(LLMproxyServicePort.Text);
      if length(ProxyPort) >= 1 then
      begin
        ProxyPortNumber := StrToIntDef(ProxyPort, 0);
        if ProxyPortNumber >= 1 then
        begin
          RootObj.Add('proxy_port', ProxyPortNumber);
          PortsReserved.Add(IntToStr(ProxyPortNumber));
        end;
      end;
      RootObj.Add('proxy_timeout', LLMproxyServiceTimeout.Value);
      RootObj.Add('max_proxy_connections', LLMproxyServiceMaxConnections.Value);
      RootObj.Add('max_package_size', LLMproxyServiceMaxPackageSize.Value);
      if length(trim(ModelComboBox.Text)) >= 1 then
        RootObj.Add('model', trim(ModelComboBox.Text));
      if ParameterListEditor.RowCount >= 2 then
      begin
        ParamsObj := TJSONObject.Create;
        for i := 1 to ParameterListEditor.RowCount - 1 do
        begin
          KeyName := trim(ParameterListEditor.Keys[i]);
          if KeyName = '' then continue;
          NewValue := trim(ParameterListEditor.Values[ParameterListEditor.Keys[i]]);
          if lowercase(KeyName) = 'port' then
          begin
            llmConversationalPort := StrToIntDef(NewValue, llmConversationalPort);
            ParamsObj.Add(KeyName, IntToStr(llmConversationalPort));
          end
          else
            ParamsObj.Add(KeyName, NewValue);
        end;
        RootObj.Add('parameters', ParamsObj);
        ParamsObj := nil;
      end;
      if not(PortsReserved.IndexOf(IntToStr(llmConversationalPort)) = -1) then
        raise SaveSettingsFatal.Create('Error: LLM port already reserved: ' + IntToStr(llmConversationalPort));
      PortsReserved.Add(IntToStr(llmConversationalPort));
      if EnableEmbeddingCheckBox.Checked then
        RootObj.Add('embedding', 1)
      else
        RootObj.Add('embedding', 0);
      if length(trim(EmbeddingModelCombobox.Text)) >= 1 then
        RootObj.Add('embedding_model', trim(EmbeddingModelCombobox.Text));
      if EmbeddingParameterListEditor.RowCount >= 2 then
      begin
        ParamsObj := TJSONObject.Create;
        for i := 1 to EmbeddingParameterListEditor.RowCount - 1 do
        begin
          KeyName := trim(EmbeddingParameterListEditor.Keys[i]);
          if KeyName = '' then continue;
          NewValue := trim(EmbeddingParameterListEditor.Values[EmbeddingParameterListEditor.Keys[i]]);
          if lowercase(KeyName) = 'port' then
          begin
            llmEmbeddingPort := StrToIntDef(NewValue, llmEmbeddingPort);
            ParamsObj.Add(KeyName, IntToStr(llmEmbeddingPort));
          end
          else
            ParamsObj.Add(KeyName, NewValue);
        end;
        RootObj.Add('embedding_parameters', ParamsObj);
        ParamsObj := nil;
      end;
      if not(PortsReserved.IndexOf(IntToStr(llmEmbeddingPort)) = -1) then
        raise SaveSettingsFatal.Create('Error: embedding port already reserved: ' + IntToStr(llmEmbeddingPort));
      PortsReserved.Add(IntToStr(llmEmbeddingPort));
      ParamsObj := TJSONObject.Create;
      if not(PortsReserved.IndexOf(IntToStr(NginxHTTPport.Value)) = -1) then
        raise SaveSettingsFatal.Create('Error: HTTP port already reserved: ' + IntToStr(NginxHTTPport.Value));
      PortsReserved.Add(IntToStr(NginxHTTPport.Value));
      ParamsObj.Add('nginx_http_port', NginxHTTPport.Value);
      if not(PortsReserved.IndexOf(IntToStr(NginxHTTPSport.Value)) = -1) then
        raise SaveSettingsFatal.Create('Error: HTTPS port already reserved: ' + IntToStr(NginxHTTPSport.Value));
      PortsReserved.Add(IntToStr(NginxHTTPSport.Value));
      ParamsObj.Add('nginx_https_port', NginxHTTPSport.Value);
      if length(trim(SSLcertificate.Text)) > 0 then
        ParamsObj.Add('nginx_ssl_certificate', StringReplace(trim(SSLcertificate.Text), PathDelim, '/', [rfReplaceAll]));
      if length(trim(SSLkey.Text)) > 0 then
        ParamsObj.Add('nginx_ssl_key', StringReplace(trim(SSLkey.Text), PathDelim, '/', [rfReplaceAll]));
      if not(PortsReserved.IndexOf(IntToStr(PHPhttpPort.Value)) = -1) then
        raise SaveSettingsFatal.Create('Error: PHP port already reserved: ' + IntToStr(PHPhttpPort.Value));
      PortsReserved.Add(IntToStr(PHPhttpPort.Value));
      ParamsObj.Add('php_http_port', PHPhttpPort.Value);
      ParamsObj.Add('php_timezone', trim(PHPtimezoneCombobox.Text));
      RootObj.Add('webserver', ParamsObj);
      ParamsObj := nil;
      JSONList.Text := RootObj.FormatJSON();
      JSONList.SaveToFile(wrapperConfigFile);
      FreeAndNil(JSONList);
      if length(trim(PHPTimezoneCombobox.Text)) >= 1 then
      begin
        phpConfigLines := TStringList.Create;
        try
          phpConfigLines.LoadFromFile(phpConfigFile);
          regexp.Expression := '(^\s*date\.timezone\s*=\s*)([^;#\r\n]*)(.*$)';
          for i := 0 to phpConfigLines.Count - 1 do
          begin
            if not(regexp.Exec(phpConfigLines[i])) then continue;
            phpConfigLines[i] := regexp.Replace(phpConfigLines[i], '${1}' + trim(PHPTimezoneCombobox.Text) + '${3}', true);
            break;
          end;
          phpConfigLines.SaveToFile(phpConfigFile);
        except
          on x: Exception do
            MessageDlg('Error', 'Failed to update PHP configuration: ' + x.Message, mtError, [mbOK], 0);
        end;
      end;
      webserverConfigLines := TStringList.Create;
      try
        webserverConfigLines.LoadFromFile(webserverConfigFile);
        for i := 0 to webserverConfigLines.Count - 1 do
        begin
          if LLMloggingCheckBox.Checked then
          begin
            regexp.Expression := '(^\s*error_log\s+)([^;]+)(;\s*$)';
            webserverConfigLines[i] := regexp.Replace(webserverConfigLines[i], '${1}../log/error.log warn${3}', true);
            regexp.Expression := '(^\s*access_log\s+)([^;]+)(;\s*$)';
            webserverConfigLines[i] := regexp.Replace(webserverConfigLines[i], '${1}../log/access.log main${3}', true);
          end
          else
          begin
            regexp.Expression := '(^\s*error_log\s+)([^;]+)(;\s*$)';
            {$IFDEF MSWINDOWS}
            webserverConfigLines[i] := regexp.Replace(webserverConfigLines[i], '${1}nul crit${3}', true);
            {$ENDIF}
            {$IFDEF UNIX}
            webserverConfigLines[i] := regexp.Replace(webserverConfigLines[i], '${1}/dev/null crit${3}', true);
            {$ENDIF}
            regexp.Expression := '(^\s*access_log\s+)([^;]+)(;\s*$)';
            webserverConfigLines[i] := regexp.Replace(webserverConfigLines[i], '${1}off${3}', true);
          end;
        end;
        for i := 0 to webserverConfigLines.Count - 1 do
        begin
          regexp.Expression := '(^\s*listen\s+)(\d+)(\s*;\s*$)';
          webserverConfigLines[i] := regexp.Replace(webserverConfigLines[i], '${1}' + IntToStr(NginxHTTPport.Value) + '${3}', true);
          regexp.Expression := '(^\s*listen\s+)(\d+)(\s+ssl\s*;\s*$)';
          webserverConfigLines[i] := regexp.Replace(webserverConfigLines[i], '${1}' + IntToStr(NginxHTTPSport.Value) + '${3}', true);
          regexp.Expression := '(^\s*fastcgi_pass\s+127\.0\.0\.1:)(\d+)(\s*;\s*$)';
          webserverConfigLines[i] := regexp.Replace(webserverConfigLines[i], '${1}' + IntToStr(PHPhttpPort.Value) + '${3}', true);
        end;
        for i := 0 to webserverConfigLines.Count - 1 do
        begin
          regexp.Expression := '(^\s*location\s+)([^\{]+)(\{\s*\#\s*Proxy)';
          webserverConfigLines[i] := regexp.Replace(webserverConfigLines[i], '${1}' + llmProxyLocation + ' ${3}', true);
          regexp.Expression := '(^\s*proxy_pass\s+http://127\.0\.0\.1:)(\d+)(/v1/embeddings\s*;)';
          webserverConfigLines[i] := regexp.Replace(webserverConfigLines[i], '${1}' + IntToStr(llmEmbeddingPort) + '${3}', true);
          regexp.Expression := '(^\s*proxy_pass\s+http://127\.0\.0\.1:)(\d+)(/v1/chat/completions\s*;)';
          webserverConfigLines[i] := regexp.Replace(webserverConfigLines[i], '${1}' + IntToStr(llmConversationalPort) + '${3}', true);
          regexp.Expression := '(^\s*proxy_pass\s+http://127\.0\.0\.1:)(\d+)(/\s*;)';
          webserverConfigLines[i] := regexp.Replace(webserverConfigLines[i], '${1}' + IntToStr(llmConversationalPort) + '${3}', true);
          regexp.Expression := '(^\s*proxy_read_timeout\s+)([^;]+)(;[ \t]*$)';
          webserverConfigLines[i] := regexp.Replace(webserverConfigLines[i], '${1}' + IntToStr(LLMproxyServiceTimeout.Value) + 's${3}', true);
          regexp.Expression := '(^\s*proxy_send_timeout\s+)([^;]+)(;[ \t]*$)';
          webserverConfigLines[i] := regexp.Replace(webserverConfigLines[i], '${1}' + IntToStr(LLMproxyServiceTimeout.Value) + 's${3}', true);
        end;
        if length(trim(SSLcertificate.Text)) > 0 then
        begin
          sslFullPath := appdir + trim(SSLcertificate.Text);
          sslRelPath := trim(ExtractRelativePath(webserverConfigFile, sslFullPath));
          sslRelPath := StringReplace(sslRelPath, PathDelim, '/', [rfReplaceAll]);
          for i := 0 to webserverConfigLines.Count - 1 do
          begin
            regexp.Expression := '(^\s*ssl_certificate\s+)([^;]+)(;[ \t]*$)';
            webserverConfigLines[i] := regexp.Replace(webserverConfigLines[i], '${1}' + sslRelPath + '${3}', true);
          end;
        end;
        if length(trim(SSLkey.Text)) > 0 then
        begin
          sslFullPath := appdir + trim(SSLkey.Text);
          sslRelPath := trim(ExtractRelativePath(webserverConfigFile, sslFullPath));
          sslRelPath := StringReplace(sslRelPath, PathDelim, '/', [rfReplaceAll]);
          for i := 0 to webserverConfigLines.Count - 1 do
          begin
            regexp.Expression := '(^\s*ssl_certificate_key\s+)([^;]+)(;[ \t]*$)';
            webserverConfigLines[i] := regexp.Replace(webserverConfigLines[i], '${1}' + sslRelPath + '${3}', true);
          end;
        end;
        webserverConfigLines.SaveToFile(webserverConfigFile);
      except
        on x: Exception do
          MessageDlg('Error', 'Failed to update web server configuration: ' + x.Message, mtError, [mbOK], 0);
      end;
      if not(length(configdir) >= 1) then
      begin
        MessageDlg('Error', 'Config directory not specified!', mtError, [mbOK], 0);
        configDataSaved := false;
        Exit;
      end;
      if not(DirectoryExists(configdir)) then
      begin
        if not(ForceDirectories(configdir)) then
        begin
          MessageDlg('Error', 'Failed to create config directory: ' + configdir, mtError, [mbOK], 0);
          configDataSaved := false;
          Exit;
        end;
      end;
      if not(length(personaConfigFile) >= 1) then
      begin
        MessageDlg('Error', 'Persona config file not specified!', mtError, [mbOK], 0);
        configDataSaved := false;
        Exit;
      end;
      PersonaObj := TJSONObject.Create;
      JSONList := TStringList.Create;
      try
        chdir(appdir);
        if DefaultPersonaComboBox.ItemIndex >= 0 then
        begin
          if Assigned(DefaultPersonaComboBox.Items.Objects[DefaultPersonaComboBox.ItemIndex]) then
            PersonaObj.Add('personality', TPersonaComboBoxItem(DefaultPersonaComboBox.Items.Objects[DefaultPersonaComboBox.ItemIndex]).Name);
        end;
        PersonaObj.Add('full_name', trim(PersonaFullName.Text));
        PersonaObj.Add('description', trim(PersonaDescription.Text));
        systemPrompt := trim(PersonaSystemPrompt.Lines.Text);
        if length(systemPrompt) >= 1 then PersonaObj.Add('system_prompt', systemPrompt);
        summaryPrompt := trim(PersonaSummaryPrompt.Lines.Text);
        if length(summaryPrompt) >= 1 then PersonaObj.Add('summary_prompt', summaryPrompt);
        PersonaObj.Add('initial_message', trim(PersonaInitialMessage.Text));
        PersonaObj.Add('behavior_similarity_threshold', PersonaBehaviorSimilarityThreshold.Value);
        if PersonaMemoryMode.ItemIndex >= 0 then
        begin
          if Assigned(PersonaMemoryMode.Items.Objects[PersonaMemoryMode.ItemIndex]) then
            PersonaObj.Add('memory_mode', TMemoryModeComboBoxItem(PersonaMemoryMode.Items.Objects[PersonaMemoryMode.ItemIndex]).ID)
          else
            PersonaObj.Add('memory_mode', 1);
        end
        else
          PersonaObj.Add('memory_mode', 1);
        if PersonaResponseMode.ItemIndex >= 0 then
        begin
          if Assigned(PersonaResponseMode.Items.Objects[PersonaResponseMode.ItemIndex]) then
            PersonaObj.Add('response_mode', TResponseModeComboBoxItem(PersonaResponseMode.Items.Objects[PersonaResponseMode.ItemIndex]).ID)
          else
            PersonaObj.Add('response_mode', 1);
        end
        else
          PersonaObj.Add('response_mode', 1);
        cssOverride := trim(PersonaCSSoverride.Lines.Text);
        if length(cssOverride) >= 1 then PersonaObj.Add('css_override', cssOverride);
        if not(PersonaAvatarImage.Picture.Graphic = nil) then
        begin
          AvatarObj := TJSONObject.Create;
          try
            if length(AvatarStoredFileName) >= 1 then
              AvatarObj.Add('filename', AvatarStoredFileName)
            else
              AvatarObj.Add('filename', GetImageFileName(PersonaAvatarImage));
            AvatarObj.Add('content', GetImageBase64(PersonaAvatarImage));
            PersonaObj.Add('avatar', AvatarObj);
            AvatarObj := nil;
          except
            MessageDlg('Error', 'Error loading avatar!', mtError, [mbOK], 0);
          end;
        end;
        if not(PersonaBackgroundImage.Picture.Graphic = nil) then
        begin
          BackgroundObj := TJSONObject.Create;
          try
            if length(BackgroundStoredFileName) >= 1 then
              BackgroundObj.Add('filename', BackgroundStoredFileName)
            else
              BackgroundObj.Add('filename', GetImageFileName(PersonaBackgroundImage));
            BackgroundObj.Add('content', GetImageBase64(PersonaBackgroundImage));
            PersonaObj.Add('background_image', BackgroundObj);
            BackgroundObj := nil;
          except
            MessageDlg('Error', 'Error loading background!', mtError, [mbOK], 0);
          end;
        end;
        JSONList.Text := PersonaObj.FormatJSON();
        JSONList.SaveToFile(personaConfigFile);
        if FileExists(redirectFile) then
        begin
          redirectFileContent := TStringList.Create;
          redirectFileContent.LoadFromFile(redirectFile);
          regexp.Expression := '(127\.0\.0\.1\s*:\s*)\d+';
          if regexp.Exec(redirectFileContent.Text) then
          begin
            redirectFileContent.Text := regexp.Replace(redirectFileContent.Text, '${1}' + IntToStr(NginxHTTPport.Value), true);
            redirectFileContent.SaveToFile(redirectFile);
          end;
        end;
      except
        on x: Exception do
        begin
          MessageDlg('Error', 'Failed to save persona config: ' + x.Message, mtError, [mbOK], 0);
          configDataSaved := false;
          Exit;
        end;
      end;
      configDataSaved := true;
    except
      on x: SaveSettingsFatal do
      begin
        saveSettingsError := true;
        MessageDlg('Error', x.Message, mtError, [mbOK], 0);
      end;
      on x: Exception do MessageDlg('Error', 'Failed to save config: ' + x.Message, mtError, [mbOK], 0);
    end;
  finally
    if Assigned(RootObj) then FreeAndNil(RootObj);
    if Assigned(JSONList) then FreeAndNil(JSONList);
    if Assigned(ParamsObj) then FreeAndNil(ParamsObj);
    if Assigned(regexp) then FreeAndNil(regexp);
    if Assigned(phpConfigLines) then FreeAndNil(phpConfigLines);
    if Assigned(webserverConfigLines) then FreeAndNil(webserverConfigLines);
    if Assigned(PortsReserved) then FreeAndNil(PortsReserved);
    if Assigned(redirectFileContent) then FreeAndNil(redirectFileContent);
    if Assigned(PersonaObj) then FreeAndNil(PersonaObj);
    if Assigned(AvatarObj) then FreeAndNil(AvatarObj);
    if Assigned(BackgroundObj) then FreeAndNil(BackgroundObj);
  end;
end;

//Initialize Settings Form
procedure TSettingsForm.FormCreate(Sender: TObject);
var
  ServerFileName: String;
  ServerFilePath: AnsiString;
  ServerCLIfileName: String;
  ServerCLIfilePath: AnsiString;
  PHPtimezone: String;
  TimezoneIndex: integer;
  item: TEngineComboBoxItem;
begin
  try
    llmConversationalPort := 8080;
    llmEmbeddingPort := 8081;
    llmProxyLocation := '/llamacpp/';
    AvatarImageData := nil;
    BackgroundImageData := nil;
    AvatarImageFormat := '';
    BackgroundImageFormat := '';
    AvatarStoredFileName := '';
    BackgroundStoredFileName := '';
    TitleList := TStringList.Create;
    TitleList.Sorted := true;
    TitleList.Duplicates := dupIgnore;
    EmbeddingTitleList := TStringList.Create;
    EmbeddingTitleList.Sorted := true;
    EmbeddingTitleList.Duplicates := dupIgnore;
    canHandleEngineChange := false;
    configDataSaved := false;
    saveSettingsError := false;
    MainLLMserverProcessRunning := false;
    DefaultPHPtimezone := -1;
    {$IFDEF MSWINDOWS}
    appdir := IncludeTrailingPathDelimiter(ExtractFilePath(application.ExeName));
    {$ELSE}
    appdir := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));
    {$ENDIF}
    chdir(appdir);
    dbdir := appdir + 'database' + PathDelim;
    if not(DirectoryExists(dbdir)) then raise Exception.Create('Database directory not found: ' + dbdir);
    wrapperDbFile := dbdir + 'wrapper.db';
    if not(FileExists(wrapperDbFile)) then raise Exception.Create('Database file not found: ' + wrapperDbFile);
    wrapperDbFileWAL := ChangeFileExt(wrapperDbFile, '.db-wal');
    wrapperDbFileSHM := ChangeFileExt(wrapperDbFile, '.db-shm');
    webserverdir := appdir + 'webserver' + PathDelim;
    if not(DirectoryExists(webserverdir)) then raise Exception.Create('Web server directory not found: ' + webserverdir);
    phpConfigFile := webserverdir + 'php' + PathDelim + 'php.ini';
    if not(FileExists(phpConfigFile)) then raise Exception.Create('PHP config file not found: ' + phpConfigFile);
    webserverConfigFile := webserverdir + 'conf' + PathDelim + 'nginx.conf';
    if not(FileExists(webserverConfigFile)) then raise Exception.Create('Web server config file not found: ' + webserverConfigFile);
    redirectFile := webserverdir + 'www' + PathDelim + 'index.php';
    if not(FileExists(redirectFile)) then raise Exception.Create('Web UI main index file not found: ' + redirectFile);
    sslCertificateDir := webserverdir + 'conf' + PathDelim + 'ssl' + PathDelim;
    if not(DirectoryExists(sslCertificateDir)) then raise Exception.Create('SSL certificate directory not found: ' + sslCertificateDir);
    personaDbFile := dbdir + 'personality.db';
    if not(FileExists(personaDbFile)) then raise Exception.Create('Database file not found: ' + personaDbFile);
    personaDbFileWAL := ChangeFileExt(personaDbFile, '.db-wal');
    personaDbFileSHM := ChangeFileExt(personaDbFile, '.db-shm');
    modeldir := appdir + 'model' + PathDelim;
    if not(DirectoryExists(modeldir)) then raise Exception.Create('LLM directory not found: ' + modeldir);
    embeddingModeldir := modeldir + 'embedding' + PathDelim;
    if not(DirectoryExists(embeddingModeldir)) then raise Exception.Create('Embedding directory not found: ' + embeddingModeldir);
    configdir := appdir + 'config' + PathDelim;
    if not(DirectoryExists(configdir)) then ForceDirectories(configdir);
    wrapperConfigFile := configdir + 'wrapper.json';
    personaConfigFile := configdir + 'personality.json';
    logDirectory := appdir + 'log' + PathDelim;
    logFile := logDirectory + 'wrapper.log';
    TempDirectory := appdir + 'temp' + PathDelim;
    CacheDirectory := webserverdir + 'www' + PathDelim + 'frontend' + PathDelim + 'var' + PathDelim + 'cache' + PathDelim;
    try
      // DO NOT delete WAL/SHM files before opening - let SQLite handle them
      {if FileExists(wrapperDbFileWAL) then DeleteFile(wrapperDbFileWAL);
      if FileExists(wrapperDbFileSHM) then DeleteFile(wrapperDbFileSHM);}
      LlamaDBconnection.DatabaseName := wrapperDbFile;
      LlamaDBconnection.Open;
      LlamaTransaction.Active := true;
      // Set busy timeout to wait for transient locks instead of failing immediately
      LlamaDBconnection.ExecuteDirect('PRAGMA busy_timeout = 5000');
      LlamaQuery.Open;
      ClearEngineComboBox;
      while not(LlamaQuery.EOF) do
      begin
        ServerFileName := trim(LlamaQuery.FieldByName('server').AsString);
        ServerFileName := StringReplace(ServerFileName, '/', PathDelim, [rfReplaceAll]);
        ServerFilePath := appdir + 'llama' + PathDelim + ServerFileName;
        ServerCLIfileName := trim(LlamaQuery.FieldByName('cli').AsString);
        ServerCLIfileName := StringReplace(ServerCLIfileName, '/', PathDelim, [rfReplaceAll]);
        ServerCLIfilePath := appdir + 'llama' + PathDelim + ServerCLIfileName;
        if FileExists(ServerFilePath) and FileExists(ServerCLIfilePath) then
        begin
          item := TEngineComboBoxItem.Create;
          item.ID := trim(LlamaQuery.FieldByName('id').AsString);
          item.ServerBinary := ServerFilePath;
          item.ProxyPort := trim(LlamaQuery.FieldByName('proxy_port').AsString);
          item.ProxyTimeout := StrToIntDef(trim(LlamaQuery.FieldByName('proxy_timeout').AsString), 1);
          item.ProxyMaxConnections := StrToIntDef(trim(LlamaQuery.FieldByName('max_proxy_connections').AsString), 1);
          item.ProxyMaxPackageSize := StrToIntDef(trim(LlamaQuery.FieldByName('max_package_size').AsString), 1);
          LlamaEngineComboBox.Items.AddObject(trim(LlamaQuery.FieldByName('name').AsString), item);
        end;
        LlamaQuery.Next;
      end;
      //Get PHP time zones
      TimezoneQuery.Open;
      TimezoneIndex := -1;
      PHPtimezoneCombobox.Items.Clear;
      while not(TimezoneQuery.EOF) do
      begin
        PHPtimezone := trim(TimezoneQuery.FieldByName('name').AsString);
        if length(PHPtimezone) >= 1 then
        begin
          Inc(TimezoneIndex);
          PHPtimezoneCombobox.Items.Append(PHPtimezone);
          if not(TimezoneQuery.FieldByName('default').AsInteger = 0) then
            DefaultPHPtimezone := TimezoneIndex;
        end;
        TimezoneQuery.Next;
      end;
      if DefaultPHPtimezone = -1 then
      begin
        if PHPtimezoneCombobox.Items.Count > 0 then DefaultPHPtimezone := 0;
      end;
      PHPtimezoneCombobox.ItemIndex := DefaultPHPtimezone;
    finally
      LlamaQuery.Close;
      TimezoneQuery.Close;
      LlamaTransaction.Active := false;
      LlamaDBconnection.Close;
      // Note: WAL/SHM files are managed by SQLite automatically. Do not delete them.
      {if FileExists(wrapperDbFileWAL) then DeleteFile(wrapperDbFileWAL);
      if FileExists(wrapperDbFileSHM) then DeleteFile(wrapperDbFileSHM);}
    end;
    if LlamaEngineComboBox.Items.Count >= 1 then
    begin
      LlamaEngineComboBox.ItemIndex := 0;
      if LlamaEngineComboBox.Items.Count > 1 then
      begin
        EngineLabel.Enabled := true;
        LlamaEngineComboBox.Enabled := true;
      end;
    end
    else
      MessageDlg('Error', 'No LLM engine not found! Unable to run LLM server!', mtError, [mbOK], 0);
    LoadLLMfiles('CONVERSATIONAL');
    LoadLLMfiles('EMBEDDING');
    PersonaMemoryMode.Items.AddObject('Delete old (default)', TMemoryModeComboBoxItem.Create);
    TMemoryModeComboBoxItem(PersonaMemoryMode.Items.Objects[0]).ID := 1;
    TMemoryModeComboBoxItem(PersonaMemoryMode.Items.Objects[0]).Title := 'Delete old (default)';
    PersonaMemoryMode.Items.AddObject('Summarize', TMemoryModeComboBoxItem.Create);
    TMemoryModeComboBoxItem(PersonaMemoryMode.Items.Objects[1]).ID := 2;
    TMemoryModeComboBoxItem(PersonaMemoryMode.Items.Objects[1]).Title := 'Summarize';
    PersonaMemoryMode.ItemIndex := 0;
    PersonaResponseMode.Items.AddObject('Legacy (default)', TResponseModeComboBoxItem.Create);
    TResponseModeComboBoxItem(PersonaResponseMode.Items.Objects[0]).ID := 1;
    TResponseModeComboBoxItem(PersonaResponseMode.Items.Objects[0]).Title := 'Legacy (default)';
    PersonaResponseMode.Items.AddObject('Modern (stream)', TResponseModeComboBoxItem.Create);
    TResponseModeComboBoxItem(PersonaResponseMode.Items.Objects[1]).ID := 2;
    TResponseModeComboBoxItem(PersonaResponseMode.Items.Objects[1]).Title := 'Modern (stream)';
    PersonaResponseMode.ItemIndex := 0;
    if (ModelComboBox.Items.Count < 1) and (EmbeddingModelComboBox.Items.Count < 1) then
      MessageDlg('Error', 'No language or embedding model not found! Unable to run LLM server!', mtError, [mbOK], 0);
  except
    on x: Exception do
    begin
      if not(x.ClassType = EAbort) then MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);
      if Assigned(TitleList) then FreeAndNil(TitleList);
      if Assigned(EmbeddingTitleList) then FreeAndNil(EmbeddingTitleList);
      Abort;
    end;
  end;
end;

//Add new LLM parameter
procedure TSettingsForm.AddButtonClick(Sender: TObject);
var
  ParameterName: String;
  RowIndex: Integer;
begin
  try
    ParameterName := '';
    if not(InputQuery('New Parameter', 'Enter parameter name:', ParameterName)) then Exit;
    ParameterName := trim(ParameterName);
    if ParameterName = '' then
    begin
      MessageDlg('Error', 'Parameter name cannot be empty!', mtError, [mbOK], 0);
      Exit;
    end;
    if ParameterListEditor.FindRow(ParameterName, RowIndex) then
    begin
      MessageDlg('Error', 'Parameter already exists!', mtError, [mbOK], 0);
      Exit;
    end;
    ParameterListEditor.InsertRow(ParameterName, '', true);
  except
    on x: Exception do
      MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);
  end;
end;

//Remove LLM parameter
procedure TSettingsForm.RemoveButtonClick(Sender: TObject);
var
  RowIndex: Integer;
  ParameterName: String;
  TitleIdx: Integer;
begin
  try
    RowIndex := ParameterListEditor.Row;
    if (RowIndex <= 0) or (RowIndex >= ParameterListEditor.RowCount) then Exit;
    ParameterName := trim(ParameterListEditor.Keys[RowIndex]);
    if ParameterName = '' then Exit;
    if MessageDlg(
      'Remove parameter',
      'Do you really want to delete "' + ParameterName + '"?',
      mtConfirmation,
      [mbYes, mbNo],
      0) = mrYes then
    begin
      ParameterListEditor.DeleteRow(RowIndex);
      if Assigned(TitleList) then
      begin
        TitleIdx := TitleList.IndexOfName(ParameterName);
        if not(TitleIdx = -1) then TitleList.Delete(TitleIdx);
      end;
      ParameterListEditor.Hint := '';
    end;
  except
    on x: Exception do
      MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);
  end;
end;

//Remove Embedding Parameter
procedure TSettingsForm.RemoveEmbeddingParameterButtonClick(Sender: TObject);
var
  RowIndex: Integer;
  ParameterName: String;
  TitleIdx: Integer;
begin
  try
    RowIndex := EmbeddingParameterListEditor.Row;
    if (RowIndex <= 0) or (RowIndex >= EmbeddingParameterListEditor.RowCount) then Exit;
    ParameterName := trim(EmbeddingParameterListEditor.Keys[RowIndex]);
    if ParameterName = '' then Exit;
    if MessageDlg(
      'Remove parameter',
      'Do you really want to delete "' + ParameterName + '"?',
      mtConfirmation,
      [mbYes, mbNo],
      0) = mrYes then
    begin
      EmbeddingParameterListEditor.DeleteRow(RowIndex);
      if Assigned(EmbeddingTitleList) then
      begin
        TitleIdx := EmbeddingTitleList.IndexOfName(ParameterName);
        if not(TitleIdx = -1) then EmbeddingTitleList.Delete(TitleIdx);
      end;
      EmbeddingParameterListEditor.Hint := '';
    end;
  except
    on x: Exception do
      MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);
  end;
end;

//Free up memory
procedure TSettingsForm.FormDestroy(Sender: TObject);
var i: integer;
begin
  try
    try
      if Assigned(AvatarImageData) then FreeAndNil(AvatarImageData);
    except
      on x: Exception do
        MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);
    end;
    try
      if Assigned(BackgroundImageData) then FreeAndNil(BackgroundImageData);
    except
      on x: Exception do
        MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);
    end;
    if Assigned(TitleList) then FreeAndNil(TitleList);
    if Assigned(EmbeddingTitleList) then FreeAndNil(EmbeddingTitleList);
    ClearEngineComboBox;
    ClearDeviceComboBox;
    ClearPersonaComboBox;
    if PersonaMemoryMode.Items.Count >= 1 then
    begin
      for i := 0 to PersonaMemoryMode.Items.Count - 1 do
      begin
        try
          if not(Assigned(PersonaMemoryMode.Items.Objects[i])) then continue;
          PersonaMemoryMode.Items.Objects[i].Free;
        except
          on x: Exception do
            MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);
        end;
      end;
      PersonaMemoryMode.Items.Clear;
    end;
    if PersonaResponseMode.Items.Count >= 1 then
    begin
      for i := 0 to PersonaResponseMode.Items.Count - 1 do
      begin
        try
          if not(Assigned(PersonaResponseMode.Items.Objects[i])) then continue;
          PersonaResponseMode.Items.Objects[i].Free;
        except
          on x: Exception do
            MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);
        end;
      end;
      PersonaResponseMode.Items.Clear;
    end;
    LlamaQuery.Close;
    TimezoneQuery.Close;
    LlamaTransaction.Active := false;
    LlamaDBconnection.Close;
    PersonaQuery.Close;
    PersonaTransaction.Active := false;
    PersonaDBconnection.Close;
    // Checkpoint and remove WAL files now that all connections are closed
    CleanupWALFiles(wrapperDbFile, wrapperDbFileWAL, wrapperDbFileSHM);
    CleanupWALFiles(personaDbFile, personaDbFileWAL, personaDbFileSHM);
  except
    on x: Exception do
      MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);
  end;
end;

//Checkpoint and remove WAL files after database is closed
procedure TSettingsForm.CleanupWALFiles(const DBFile, WALFile, SHMFile: AnsiString);
var
  CheckpointConn: TSQLite3Connection;
  CheckpointTrans: TSQLTransaction;
begin
  // Only try if WAL file exists
  if not FileExists(WALFile) then Exit;
  CheckpointConn := nil;
  CheckpointTrans := nil;
  try
    CheckpointConn := TSQLite3Connection.Create(nil);
    CheckpointTrans := TSQLTransaction.Create(CheckpointConn);
    CheckpointConn.Transaction := CheckpointTrans;
    CheckpointConn.DatabaseName := DBFile;
    CheckpointConn.Open;
    CheckpointConn.ExecuteDirect('PRAGMA busy_timeout = 500');
    CheckpointConn.ExecuteDirect('PRAGMA wal_checkpoint(TRUNCATE)');
  except
    // Silently ignore if DB is locked or any error
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
  // Delete WAL/SHM files after successful checkpoint
  try
    if FileExists(WALFile) then DeleteFile(WALFile);
    if FileExists(SHMFile) then DeleteFile(SHMFile);
  except
    // Ignore deletion errors
  end;
end;

//Load factory defaults
procedure TSettingsForm.LoadDefaultsButtonClick(Sender: TObject);
begin
  try
    if MessageDlg(
      'Load Default Configuration',
      'Do you really want to discard changes and load the default configuration?',
      mtConfirmation,
      [mbYes, mbNo],
      0) = mrYes then
      LoadDefaultConfig;
  except
    on x: Exception do
      MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);
  end;
end;

//Load persona from database
procedure TSettingsForm.LoadPersonaButtonClick(Sender: TObject);
begin
  LoadSelectedPersonaQuery;
end;

//Open Log Folder
procedure TSettingsForm.OpenLogFolderButtonClick(Sender: TObject);
begin
  try
    if not(OpenFolder(LogDirectory)) then OpenLogFolderButton.Enabled := false;
  except
    on x: Exception do
      MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);
  end;
end;

//Show title for each parameter
procedure TSettingsForm.ParameterListEditorMouseMove(Sender: TObject;
  Shift: TShiftState; X, Y: Integer);
var
  gc: TGridCoord;
  KeyName, NewHint: string;
begin
  try
    gc := ParameterListEditor.MouseToCell(Point(X, Y));
    if (gc.Y <= 0) or (gc.Y >= ParameterListEditor.RowCount) or (gc.X < 0) then Exit;
    KeyName := trim(ParameterListEditor.Keys[gc.Y]);
    if KeyName = '' then
    begin
      ParameterListEditor.Hint := '';
      Exit;
    end;
    NewHint := '';
    if Assigned(TitleList) then NewHint := TitleList.Values[KeyName];
    if NewHint = '' then NewHint := KeyName;
    if not(ParameterListEditor.Hint = NewHint) then
    begin
      ParameterListEditor.Hint := NewHint;
      Application.ActivateHint(Mouse.CursorPos);
    end;
  except
    {on x: Exception do
      MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);}
  end;
end;

end.
