{ Settings form unit for configuring LLM engines, models, and persona settings. }
unit settings_form;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, LCLIntf, SysUtils, DB, SQLite3Conn, SQLDB, Forms, Controls, Graphics,
  Dialogs, StdCtrls, ExtCtrls, ValEdit, ComCtrls, DBCtrls, Grids, Spin, fpjson,
  jsonparser, StrUtils, RegExpr, process, FileUtil, SynHighlighterCss, SynEdit,
  math, base64, Types, fgl, progress_form;

type

  { TEngineComboBoxItem: item in the LLM engine combo box containing engine configuration from database. }
  TEngineComboBoxItem = class
    public
      { Unique identifier for the engine configuration. }
      ID: string;
      { Path to the server executable binary. }
      ServerBinary: ansistring;
      { Determines whether the main engine uses CPU or GPU for processing. }
      UsesGPU: integer;
      { Proxy port number configured for this engine. }
      ProxyPort: string;
      { Timeout in seconds for proxy connections. }
      ProxyTimeout: integer;
      { Maximum number of concurrent proxy connections. }
      ProxyMaxConnections: integer;
      { Maximum package size in bytes for proxy transfers. }
      ProxyMaxPackageSize: integer;
      { Path to the TTS server executable binary. }
      TTSbinary: ansistring;
      { Determines whether the TTS engine uses CPU or GPU for processing. }
      TTSusesGPU: integer;
  end;

  { TDeviceComboBoxItem: item in the device combo box containing GPU/device information. }
  TDeviceComboBoxItem = class
    public
      { Device identifier string. }
      ID: string;
      { Display title for the device. }
      Title: string;
  end;

  { TTTSmodel: object to store default TTS model information. }
  TTTSmodel = class
    public
      { Model type name. }
      Name: string;
      { Display title for the model type. }
      Title: string;
      { Description for the model type. }
      Description: string;
      { Model filename. }
      FileName: string;
      { Additional information. }
      Comments: string;
  end;

  { TTTSmodelList: list to store default model information. }
  TTTSmodelList = class(specialize TFPGObjectList<TTTSmodel>)
    public
      { Find TTS model by name. }
      function FindByName(const AName: string): TTTSmodel;
      { Find TTS model by filename. }
      function FindByFileName(const AFileName: string): TTTSmodel;
  end;

  { TPersonaComboBoxItem: item in the persona combo box containing persona configuration from database. }
  TPersonaComboBoxItem = class
    public
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
      { Short default color theme name/key. }
      defaultTheme: string;
      { CSS override string for custom styling. }
      CSSoverride: AnsiString;
  end;

  { TResponseModeComboBoxItem: item in the response mode combo box for selecting chat completion behavior. }
  TResponseModeComboBoxItem = class
    public
      { Numeric identifier for the response mode. }
      ID: integer;
      { Display title for the response mode. }
      Title: string;
  end;

  { TMemoryModeComboBoxItem: item in the memory mode combo box for selecting chat completion behavior. }
  TMemoryModeComboBoxItem = class
    public
      { Numeric identifier for the memory mode. }
      ID: integer;
      { Display title for the memory mode. }
      Title: string;
  end;

  { SaveSettingsFatal: exception raised when invalid settings prevent saving configuration. }
  SaveSettingsFatal = class(Exception);

  { TSettingsForm: settings dialog form for configuring LLM engines, proxy settings, models, and personas. }
  TSettingsForm = class(TForm)
    { Button to add a new main TTS model to the list. }
    AddMainTTSmodelButton: TButton;
    { Button to add a new voice TTS model to the list. }
    AddVoiceTTSmodelButton: TButton;
    { Button to add a new TTS parameter row. }
    AddTTSparameterButton: TButton;
    { SQL query component for loading default TTS models from the database. }
    TTSmodelQuery: TSQLQuery;
    { Process component for running the TTS server. }
    TTSserverProcess: TProcess;
    { Combo box for selecting the GPU/CPU device for TTS server to use. }
    TTSdeviceCombobox: TComboBox;
    { Label for the TTS device selection combo box. }
    TTSdeviceLabel: TLabel;
    { Checkbox to enable or disable the TTS service. }
    EnableTTScheckBox: TCheckBox;
    { Group box containing general TTS controls. }
    GeneralTTSsettingsGroupBox: TGroupBox;
    { Combo box for selecting the main TTS model. }
    MainTTSmodelComboBox: TComboBox;
    { Button to reload the list of available TTS devices. }
    TTSreloadDevicesButton: TButton;
    { Combo box for selecting the voice TTS model. }
    VoiceTTSmodelComboBox: TComboBox;
    { Label for the main TTS model combo box. }
    MainTTSmodelLabel: TLabel;
    { Label for the voice TTS model combo box. }
    VoiceTTSmodelLabel: TLabel;
    { Group box containing TTS model controls. }
    TTSmodelsGroupBox: TGroupBox;
    { Group box containing TTS parameters. }
    TTSparameterGroupBox: TGroupBox;
    { Value list editor grid for TTS parameters. }
    TTSparameterListEditor: TValueListEditor;
    { Button to remove the selected TTS parameter row. }
    RemoveTTSparameterButton: TButton;
    { Scrollable container for the TTS tab sheet. }
    TTStabSheetScrollBox: TScrollBox;
    { Button to reload the list of available LLM/embedding devices. }
    ReloadDevicesButton: TButton;
    { Checkbox to enable or disable the LLM service. }
    EnableLLMcheckBox: TCheckBox;
    { Button to clear the temporary directory contents. }
    ClearTempDirButton: TButton;
    { Group box containing theme controls. }
    DefaultThemeGroupBox: TGroupBox;
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
    { Radio button for choosing light color theme on frontpage. }
    DefaultThemeLightRadioButton: TRadioButton;
    { Radio button for choosing dark color theme on frontpage. }
    DefaultThemeDarkRadioButton: TRadioButton;
    { Tab sheet containing TTS configuration settings. }
    TTStabSheet: TTabSheet;
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
    { Combo box for selecting the GPU/CPU device for LLM/embedding server to use. }
    DeviceCombobox: TComboBox;
    { Checkbox to enable or disable the embedding service. }
    EnableEmbeddingCheckBox: TCheckBox;
    { Combo box for selecting the embedding model. }
    EmbeddingModelComboBox: TComboBox;
    { Group box containing embedding model configuration. }
    EmbeddingModelGroupBox: TGroupBox;
    { Label for the LLM/embedding device selection combo box. }
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
    { Handles add TTS voice model button click. }
    procedure AddVoiceTTSmodelButtonClick(Sender: TObject);
    { Handles add TTS main model button click. }
    procedure AddMainTTSmodelButtonClick(Sender: TObject);
    { Handles add TTS parameter button click. }
    procedure AddTTSparameterButtonClick(Sender: TObject);
    { Handles remove TTS parameter button click. }
    procedure RemoveTTSparameterButtonClick(Sender: TObject);
    { Enables or disables TTS service based on checkbox. }
    procedure EnableTTScheckBoxChange(Sender: TObject);
    { Handles LLM/embedding device reload button click. }
    procedure ReloadDevicesButtonClick(Sender: TObject);
    { Enables or disables LLM parameters based on checkbox. }
    procedure EnableLLMcheckBoxChange(Sender: TObject);
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
    { Handles clear log button click event. }
    procedure ClearLogButtonClick(Sender: TObject);
    { Handles mouse move over embedding parameter grid for tooltip display. }
    procedure EmbeddingParameterListEditorMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    { Enables or disables embedding parameters based on checkbox. }
    procedure EnableEmbeddingCheckBoxChange(Sender: TObject);
    { Initializes the form display and enables buttons. }
    procedure FormShow(Sender: TObject);
    { Handles LLM engine selection change in the combo box. }
    procedure LlamaEngineComboBoxChange(Sender: TObject);
    { Enables or disables proxy service settings based on port input. }
    procedure LLMproxyServicePortChange(Sender: TObject);
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
    procedure ParameterListEditorMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    { Handles remove button click to remove a parameter. }
    procedure RemoveButtonClick(Sender: TObject);
    { Handles remove embedding parameter button click. }
    procedure RemoveEmbeddingParameterButtonClick(Sender: TObject);
    { Handles mouse move over TTS parameter grid for tooltip display. }
    procedure TTSparameterListEditorMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    { Handles TTS device reload button click. }
    procedure TTSreloadDevicesButtonClick(Sender: TObject);
  protected
    { Flag to prevent engine change handling during initialization. }
    canHandleEngineChange: boolean;
    { List of parameter titles for grid hints. }
    TitleList: TStringList;
    { List of embedding parameter titles for grid hints. }
    EmbeddingTitleList: TStringList;
    { List of TTS parameter titles for grid hints. }
    TTStitleList: TStringList;
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
    { TTS service port number. }
    llmTTSport: integer;
    { Proxy location path for nginx. }
    llmProxyLocation: AnsiString;
    { Flag to load TTS fallback parameters on unsupprted hardware. }
    ttsFallbackNeeded: boolean;
    { CPU fallback binary for TTS engine. }
    ttsFallbackBinary: AnsiString;
    { Flag to disable TTS engine when no model is available. }
    ttsModelsAvailable: boolean;
    { Indicates whether LLM/embedding service supports the hardware. }
    llmEmbeddingDeviceFound: boolean;
    { Indicates whether TTS service supports the hardware. }
    ttsDeviceFound: boolean;
    { Default TTS model container. }
    defaultTTSmodelList: TTTSmodelList;
    { Stores the default PHP time zone read from the database. }
    DefaultPHPtimezone: integer;
    { Replaces special characters in the specified filename. }
    function NormalizeFileName(const FilePath: AnsiString): AnsiString;
    { Copies a file progressively while updating the progress bar (helper). }
    function CopyFileWithProgress(const SourceFile, DestFile: AnsiString): Boolean;
    { Opens a folder in the system default file explorer. }
    function OpenFolder(const FolderName: AnsiString): Boolean;
    { Converts an image control's picture to a Base64 encoded string. }
    function GetImageBase64(ImageControl: TImage): AnsiString;
    { Gets the filename for an image control based on stored format. }
    function GetImageFileName(ImageControl: TImage): string;
    { Converts a stream to its string representation. }
    function StreamToString(Stream: TStream): string;
    { Imports a new language model to the repository (helper). }
    procedure ImportModel(const ModelType: String);
    { Loads LLM model files from the model or embedding directory. }
    procedure LoadLLMfiles(const LLMtype: string; const DefaultFile: string = '');
    { Loads the list of available devices for Llama.cpp engine. }
    procedure LoadLLMdevices(EngineItem: TEngineComboBoxItem);
    { Loads the list of available devices for TTS engine. }
    procedure LoadTTSdevices(EngineItem: TEngineComboBoxItem);
    { Loads the list of available devices for the selected engine. }
    procedure LoadDevices(const Engine: string = 'LLAMA_CPP');
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
    { Clears the engine combo box and frees all associated items. }
    procedure ClearEngineComboBox;
    { Clears the LLM/embedding device combo box and frees all associated items. }
    procedure ClearLLMdeviceComboBox;
    { Clears the TTS device combo box and frees all associated items. }
    procedure ClearTTSdeviceComboBox;
    { Clears the persona combo box and frees all associated items. }
    procedure ClearPersonaComboBox;
    { Clears log files or directory based on server running state. }
    procedure ClearLog;
    { Clears all temporary files and directories. }
    procedure ClearTempDir;
    { Adds a new parameter to the selected list control (helper). }
    procedure AddParameter(ValueListEditor: TValueListEditor);
    { Removes a parameter from the selected list control (helper). }
    procedure RemoveParameter(ValueListEditor: TValueListEditor; StringList: TStringList);
    { Show hint for coordinates at valuelist editor control (helper). }
    procedure ShowHintForValueListCoords(ValueListEditor: TValueListEditor; StringList: TStringList; X, Y: Integer);
    { Helper procedure to enable/disable TTS device listing. }
    procedure UpdateTTSdeviceListAvailability(const want_to_enable_list, want_to_enable_reload: boolean);
  public
    { Path to the application directory. }
    appdir: AnsiString;
    { Path to the database directory. }
    dbdir: AnsiString;
    { Path to the conversational LLM models directory. }
    modeldir: AnsiString;
    { Path to the embedding models directory. }
    embeddingModeldir: AnsiString;
    { Path to the TTS models directory. }
    ttsModeldir: AnsiString;
    { Full path to the TTS register file for imported models. }
    ttsRegisterFile: AnsiString;
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
    { Path to the main temporary files directory. }
    TempDirectory: AnsiString;
    { Path to PHP Desktop CGI temporary files directory. }
    CGItempDirectory: AnsiString;
    { Path to the cache directory. }
    CacheDirectory: AnsiString;
    { Indicates whether configuration was saved successfully. }
    configDataSaved: boolean;
    { Indicates whether an error occurred during save. }
    saveSettingsError: boolean;
    { Indicates whether the LLM server process is currently running. }
    MainLLMserverProcessRunning: boolean;
    { Indicates whether the Web UI (PHP Desktop) process is currently running. }
    WebUIprocessRunning: boolean;
    { Saves configuration data to JSON and webserver config files. }
    procedure SaveConfigData;
    { Checkpoints and removes SQLite WAL/SHM files after database close. }
    procedure CleanupWALFiles(const DBFile, WALFile, SHMFile: AnsiString);
  end;

var
  SettingsForm: TSettingsForm;

implementation

{$R *.lfm}

{ TTTSmodelList }

//Find TTS model by name
function TTTSmodelList.FindByName(const AName: string): TTTSmodel;
var
  ANameFixed: string;
  Item: TTTSmodel;
begin
  Result := nil;
  try
    ANameFixed := trim(AName);
    if not(length(ANameFixed) >= 1) then
    begin
      MessageDlg('Error', 'Model type not specified!', mtError, [mbOK], 0);
      Exit;
    end;
    if not(Self.Count >= 1) then Exit;
    for Item in Self do
    begin
      if not(SameText(trim(Item.Name), ANameFixed)) then continue;
      Result := Item;
      Exit;
    end;
  except
    on x: Exception do
      MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);
  end;
end;

//Find TTS model by filename
function TTTSmodelList.FindByFileName(const AFileName: string): TTTSmodel;
var
  AFileNameFixed: string;
  Item: TTTSmodel;
begin
  Result := nil;
  try
    AFileNameFixed := trim(AFileName);
    if not(length(AFileNameFixed) >= 1) then
    begin
      MessageDlg('Error', 'Filename not specified!', mtError, [mbOK], 0);
      Exit;
    end;
    if not(Self.Count >= 1) then Exit;
    for Item in Self do
    begin
      if not(SameText(trim(Item.FileName), AFileNameFixed)) then continue;
      Result := Item;
      Exit;
    end;
  except
    on x: Exception do
      MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);
  end;
end;

{ TSettingsForm }

//Normalize filename
function TSettingsForm.NormalizeFileName(const FilePath: AnsiString): AnsiString;
var FilePathFixed, DirectoryPath, BaseName, FileExtension: AnsiString;
begin
  Result := '';
  try
    //DirectoryPath := '';
    FilePathFixed := trim(FilePath);
    if not(length(FilePathFixed) >= 1) then Exit;
    BaseName := trim(ExtractFileName(FilePathFixed));
    if not(length(BaseName) >= 1) then Exit;
    {if not(BaseName = FilePathFixed) then} DirectoryPath := trim(ExtractFilePath(FilePathFixed));
    FileExtension := trim(ExtractFileExt(BaseName));
    BaseName := trim(ChangeFileExt(BaseName, ''));
    if not(length(BaseName) >= 1) then Exit;
    BaseName := ReplaceRegExpr('[^a-zA-Z0-9_-]', BaseName, '_');
    BaseName := ReplaceRegExpr('_+', BaseName, '_');
    BaseName := ReplaceRegExpr('-+', BaseName, '-');
    BaseName := ReplaceRegExpr('[-_]{2,}', BaseName, '_');
    BaseName := TrimSet(BaseName, ['_', '-']);
    if not(length(BaseName) >= 1) then Exit;
    BaseName := BaseName + FileExtension;
    Result := DirectoryPath + BaseName;
  except
    on x: Exception do
      MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);
  end;
end;

//Add new TTS voice model
procedure TSettingsForm.AddVoiceTTSmodelButtonClick(Sender: TObject);
begin
  ImportModel('TTS_VOICE');
end;

//Add new main TTS model
procedure TSettingsForm.AddMainTTSmodelButtonClick(Sender: TObject);
begin
  ImportModel('TTS_MAIN');
end;

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

//Clear LLM/embedding device Combobox
procedure TSettingsForm.ClearLLMdeviceComboBox;
var i: Integer;
begin
  try
    llmEmbeddingDeviceFound := false;
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

//Clear TTS device Combobox
procedure TSettingsForm.ClearTTSdeviceComboBox;
var i: Integer;
begin
  try
    ttsDeviceFound := false;
    TTSdeviceLabel.Enabled := false;
    TTSdeviceComboBox.Enabled := false;
    if not(TTSdeviceComboBox.Items.Count >= 1) then Exit;
    for i := 0 to TTSdeviceComboBox.Items.Count - 1 do
    begin
      try
        if not(Assigned(TTSdeviceComboBox.Items.Objects[i])) then continue;
        TTSdeviceComboBox.Items.Objects[i].Free;
      except
        on x: Exception do
          MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);
      end;
    end;
    TTSdeviceComboBox.Items.Clear;
  except
    on x: Exception do
      MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);
  end;
end;

//Load LLM files
procedure TSettingsForm.LoadLLMfiles(const LLMtype: string; const DefaultFile: string = '');
var
  LLMtypeFixed, DefaultFileFixed, ModelFile: string;
  ModelDirectory: ansistring;
  ComboBox: TComboBox;
  CheckBox: TCheckBox;
  FoundIndex, i: Integer;
  SR: TSearchRec;
  ttsModelItem: TTTSmodel;
  SL: TStringList;
  JsonData: TJSONData;
  Root: TJSONObject;
  ModelFilesArray: TJSONArray;
begin
  try
    //Validate parameters and variables
    LLMtypeFixed := uppercase(trim(LLMtype));
    if not(length(LLMtypeFixed) >= 1) then
    begin
      MessageDlg('Error', 'LLM type not specified!', mtError, [mbOK], 0);
      Exit;
    end;
    ModelDirectory := '';
    ComboBox := nil;
    CheckBox := nil;
    if LLMtypeFixed = 'EMBEDDING' then
    begin
      ModelDirectory := embeddingModeldir;
      ComboBox := EmbeddingModelComboBox;
      CheckBox := EnableEmbeddingCheckBox;
      if not(Assigned(CheckBox)) then
      begin
        MessageDlg('Error', 'Target checkbox not assigned!', mtError, [mbOK], 0);
        Exit;
      end;
    end
    else if LLMtypeFixed = 'CONVERSATIONAL' then
    begin
      ModelDirectory := modeldir;
      ComboBox := ModelComboBox;
      CheckBox := EnableLLMcheckBox;
      if not(Assigned(CheckBox)) then
      begin
        MessageDlg('Error', 'Target checkbox not assigned!', mtError, [mbOK], 0);
        Exit;
      end;
    end
    else
    begin
      //Only if TTS engine is available
      if not(length(ttsModeldir) >= 1) then Exit;
      ModelDirectory := ttsModeldir;
      if LLMtypeFixed = 'TTS_MAIN' then
        ComboBox := MainTTSmodelComboBox
      else if LLMtypeFixed = 'TTS_VOICE' then
        ComboBox := VoiceTTSmodelComboBox
      else
      begin
        MessageDlg('Error', 'Invalid LLM type!', mtError, [mbOK], 0);
        Exit;
      end;
      if length(ttsRegisterFile) >= 1 then
      begin
        if FileExists(ttsRegisterFile) then
        begin
          JsonData := nil;
          SL := nil;
          SL := TStringList.Create;
          try
            SL.LoadFromFile(ttsRegisterFile);
            JsonData := GetJSON(SL.Text);
            if JsonData is TJSONObject then
            begin
              Root := TJSONObject(JsonData);
              ModelFilesArray := nil;
              if LLMtypeFixed = 'TTS_MAIN' then
                ModelFilesArray := Root.Get('main_models', TJSONArray(nil))
              else if LLMtypeFixed = 'TTS_VOICE' then
                ModelFilesArray := Root.Get('voice_models', TJSONArray(nil));
              if Assigned(ModelFilesArray) then
              begin
                if ModelFilesArray.Count > 0 then
                begin
                  for i := 0 to ModelFilesArray.Count - 1 do
                  begin
                    try
                      ModelFile := trim(ModelFilesArray[i].AsString);
                      if not(length(ModelFile) >= 1) then continue;
                      ttsModelItem := defaultTTSmodelList.FindByFileName(ModelFile);
                      if Assigned(ttsModelItem) then continue;
                      ttsModelItem := TTTSmodel.Create;
                      try
                        if LLMtypeFixed = 'TTS_MAIN' then
                          ttsModelItem.Name := 'model'
                        else if LLMtypeFixed = 'TTS_VOICE' then
                          ttsModelItem.Name := 'voice';
                        ttsModelItem.FileName := ModelFile;
                        defaultTTSmodelList.Add(ttsModelItem);
                        ttsModelItem := nil;
                      finally
                        if Assigned(ttsModelItem) then FreeAndNil(ttsModelItem);
                      end;
                    except
                      //Silent skip
                    end;
                  end;
                end;
              end;
            end;
          finally
            if Assigned(SL) then FreeAndNil(SL);
            if Assigned(JsonData) then FreeAndNil(JsonData);
          end;
        end;
      end;
    end;
    if not(length(ModelDirectory) >= 1) then
    begin
      MessageDlg('Error', 'LLM directory not specified!', mtError, [mbOK], 0);
      Exit;
    end;
    if not(DirectoryExists(ModelDirectory)) then
    begin
      MessageDlg('Error', 'LLM directory does not exist: ' + ModelDirectory, mtError, [mbOK], 0);
      Exit;
    end;
    if not(Assigned(ComboBox)) then
    begin
      MessageDlg('Error', 'Target combobox not assigned!', mtError, [mbOK], 0);
      Exit;
    end;
    //Load models
    FoundIndex := -1;
    DefaultFileFixed := trim(DefaultFile);
    ComboBox.Items.Clear;
    ComboBox.ItemIndex := -1;
    if FindFirst(ModelDirectory + '*.gguf', faAnyFile, SR) = 0 then
    begin
      try
        repeat
          if not((SR.Attr and faDirectory) = 0) then continue;
          ModelFile := trim(SR.Name);
          if not(length(ModelFile) >= 1) then continue;
          if (Pos(' ', ModelFile) > 0) or (Pos(PathDelim, ModelFile) > 0) then continue;
          if MatchStr(LLMtypeFixed, ['TTS_MAIN', 'TTS_VOICE']) then
          begin
            ttsModelItem := defaultTTSmodelList.FindByFileName(ModelFile);
            if Assigned(ttsModelItem) then
            begin
              if LLMtypeFixed = 'TTS_MAIN' then
              begin
                if not(SameText(ttsModelItem.Name, 'model')) then continue;
              end
              else if LLMtypeFixed = 'TTS_VOICE' then
              begin
                if not(SameText(ttsModelItem.Name, 'voice')) then continue;
              end
            end;
          end;
          ComboBox.Items.Add(ModelFile);
        until not(FindNext(SR) = 0);
      finally
        FindClose(SR);
      end;
    end;
    //Apply results on available services
    if LLMtypeFixed = 'EMBEDDING' then
    begin
      //Checkbox status applies to entire group boxes here not just the model combobox
      if ComboBox.Items.Count >= 1 then
      begin
        CheckBox.Enabled := true;
        if length(DefaultFileFixed) >= 1 then FoundIndex := ComboBox.Items.IndexOf(DefaultFileFixed);
        ComboBox.ItemIndex := max(FoundIndex, 0);
        if ComboBox.Items.Count > 1 then ComboBox.Enabled := true;
      end
      else
        CheckBox.Enabled := false;
      if ComboBox.Items.Count <= 1 then ComboBox.Enabled := false;
      Exit;
    end;
    if LLMtypeFixed = 'CONVERSATIONAL' then
    begin
      //Checkbox here is in the same group box as the model combobox
      if ComboBox.Items.Count >= 1 then
      begin
        if length(DefaultFileFixed) >= 1 then FoundIndex := ComboBox.Items.IndexOf(DefaultFileFixed);
        ComboBox.ItemIndex := max(FoundIndex, 0);
        if (ComboBox.Items.Count > 1) and CheckBox.Checked then ComboBox.Enabled := true;
      end;
      if (ComboBox.Items.Count <= 1) or not(CheckBox.Checked) then ComboBox.Enabled := false;
      Exit;
    end;
    if MatchStr(LLMtypeFixed, ['TTS_MAIN', 'TTS_VOICE']) then
    begin
      //Checkbox status applies to entire group boxes here not just the model combobox (and checkbox is in its own, separate group box)
      if ComboBox.Items.Count >= 1 then
      begin
        ttsModelsAvailable := true;
        if length(DefaultFileFixed) >= 1 then FoundIndex := ComboBox.Items.IndexOf(DefaultFileFixed);
        ComboBox.ItemIndex := max(FoundIndex, 0);
        if ComboBox.Items.Count > 1 then ComboBox.Enabled := true;
      end
      else
        ttsModelsAvailable := false;
      if ComboBox.Items.Count <= 1 then ComboBox.Enabled := false;
      Exit;
    end;
    MessageDlg('Error', 'Internal error!', mtError, [mbOK], 0);
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
    if MainLLMserverProcessRunning or WebUIprocessRunning then
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
      if length(CGItempDirectory) >= 1 then
      begin
        if DirectoryExists(CGItempDirectory) then DeleteDirectory(CGItempDirectory, true);
      end;
    end;
    if length(CacheDirectory) >= 1 then
    begin
      if DirectoryExists(CacheDirectory) then DeleteDirectory(CacheDirectory, false);
    end;
    ClearTempDirButton.Enabled := false;
    if MainLLMserverProcessRunning or WebUIprocessRunning then
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

//Import model file
procedure TSettingsForm.ImportModel(const ModelType: String);
var
  ModelDirectory, FileToImport, TargetFileName, TargetFilePath: AnsiString;
  ModelTypeFixed: String;
  ttsModelItem: TTTSmodel;
  RootObj: TJSONObject;
  MainModelFilesArray: TJSONArray;
  VoiceModelFilesArray: TJSONArray;
  JSONList: TStringList;
  SaveRegisterFile: Boolean;
begin
  try
    //Validate model type
    ModelTypeFixed := UpperCase(Trim(ModelType));
    if not(length(ModelTypeFixed) >= 1) then
    begin
      MessageDlg('Error', 'Model type not specified!', mtError, [mbOK], 0);
      Exit;
    end;
    if ModelTypeFixed = 'EMBEDDING' then
      ModelDirectory := embeddingModeldir
    else if ModelTypeFixed = 'CONVERSATIONAL' then
      ModelDirectory := modeldir
    else if MatchStr(ModelTypeFixed, ['TTS_MAIN', 'TTS_VOICE']) then
    begin
      //Only if TTS engine is available
      if not(length(ttsModeldir) >= 1) then Exit;
      ModelDirectory := ttsModeldir;
    end
    else
    begin
      MessageDlg('Error', 'Invalid model type: ' + ModelTypeFixed, mtError, [mbOK], 0);
      Exit;
    end;
    //Validate model directory
    if not(length(ModelDirectory) >= 1) then
    begin
      MessageDlg('Error', 'Model directory not specified!', mtError, [mbOK], 0);
      Exit;
    end;
    //Get source filepath
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
    // Ask for confirmation
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
    //Generate target filepath
    TargetFileName := NormalizeFileName(ExtractFileName(FileToImport));
    if not(length(TargetFileName) >= 1) then
    begin
      MessageDlg('Error', 'Invalid filename!', mtError, [mbOK], 0);
      chdir(appdir);
      Exit;
    end;
    TargetFilePath := ModelDirectory + TargetFileName;
    //Create intermediate directories if needed
    ForceDirectories(ExtractFilePath(TargetFilePath));
    //Perform model import
    if not(CopyFileWithProgress(FileToImport, TargetFilePath)) then
    begin
      chdir(appdir);
      Exit;
    end;
    chdir(appdir);
    //Register new TTS model file
    if MatchStr(ModelTypeFixed, ['TTS_MAIN', 'TTS_VOICE']) then
    begin
      ttsModelItem := defaultTTSmodelList.FindByFileName(TargetFileName);
      if not(Assigned(ttsModelItem)) then
      begin
        ttsModelItem := TTTSmodel.Create;
        try
          if ModelTypeFixed = 'TTS_MAIN' then
            ttsModelItem.Name := 'model'
          else if ModelTypeFixed = 'TTS_VOICE' then
            ttsModelItem.Name := 'voice';
          ttsModelItem.FileName := TargetFileName;
          defaultTTSmodelList.Add(ttsModelItem);
          ttsModelItem := nil;
        finally
          if Assigned(ttsModelItem) then FreeAndNil(ttsModelItem);
        end;
      end;
      //Reload TTS model file list
      if ModelTypeFixed = 'TTS_MAIN' then
        LoadLLMfiles('TTS_MAIN', String(MainTTSmodelComboBox.Text))
      else if ModelTypeFixed = 'TTS_VOICE' then
        LoadLLMfiles('TTS_VOICE', String(VoiceTTSmodelComboBox.Text));
      //Save TTS model registration file
      SaveRegisterFile := false;
      if length(ttsRegisterFile) >= 1 then
      begin
        RootObj := nil;
        MainModelFilesArray := nil;
        VoiceModelFilesArray := nil;
        JSONList := nil;
        try
          MainModelFilesArray := TJSONArray.Create;
          VoiceModelFilesArray := TJSONArray.Create;
          MainModelFilesArray.Clear;
          VoiceModelFilesArray.Clear;
          RootObj := TJSONObject.Create;
          for ttsModelItem in defaultTTSmodelList do
          begin
            if SameText(trim(ttsModelItem.Name), 'model') then
            begin
              MainModelFilesArray.Add(ttsModelItem.FileName);
              continue;
            end;
            if not(SameText(trim(ttsModelItem.Name), 'voice')) then continue;
            VoiceModelFilesArray.Add(ttsModelItem.FileName);
          end;
          if MainModelFilesArray.Count >= 1 then
          begin
            SaveRegisterFile := true;
            RootObj.Add('main_models', MainModelFilesArray);
            MainModelFilesArray := nil;
          end;
          if VoiceModelFilesArray.Count >= 1 then
          begin
            SaveRegisterFile := true;
            RootObj.Add('voice_models', VoiceModelFilesArray);
            VoiceModelFilesArray := nil;
          end;
          if not(SaveRegisterFile) then Exit;
          JSONList := TStringList.Create;
          JSONList.Text := RootObj.FormatJSON();
          if FileExists(ttsRegisterFile) then DeleteFile(ttsRegisterFile);
          JSONList.SaveToFile(ttsRegisterFile);
        finally
          if Assigned(RootObj) then FreeAndNil(RootObj);
          if Assigned(MainModelFilesArray) then FreeAndNil(MainModelFilesArray);
          if Assigned(VoiceModelFilesArray) then FreeAndNil(VoiceModelFilesArray);
          if Assigned(JSONList) then FreeAndNil(JSONList);
        end;
      end;
      Exit;
    end;
    //Reload LLM/embedding model file list
    LoadLLMfiles(ModelTypeFixed, String(TargetFileName));
  except
    on x: Exception do
    begin
      MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);
      chdir(appdir);
    end;
  end;
end;

//Add parameter to the selected list control
procedure TSettingsForm.AddParameter(ValueListEditor: TValueListEditor);
var
  ParameterName: String;
  RowIndex: Integer;
begin
  try
    if not(Assigned(ValueListEditor)) then Exit;
    ParameterName := '';
    if not(InputQuery('New Parameter', 'Enter parameter name:', ParameterName)) then Exit;
    ParameterName := trim(ParameterName);
    if not(length(ParameterName) >= 1) then
    begin
      MessageDlg('Error', 'Parameter name cannot be empty!', mtError, [mbOK], 0);
      Exit;
    end;
    if ValueListEditor.FindRow(ParameterName, RowIndex) then
    begin
      MessageDlg('Error', 'Parameter already exists!', mtError, [mbOK], 0);
      Exit;
    end;
    ValueListEditor.InsertRow(ParameterName, '', true);
  except
    on x: Exception do
      MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);
  end;
end;

//Remove parameter from the selected list control
procedure TSettingsForm.RemoveParameter(ValueListEditor: TValueListEditor; StringList: TStringList);
var
  RowIndex: Integer;
  ParameterName: String;
  TitleIdx: Integer;
begin
  try
    if not(Assigned(ValueListEditor)) then Exit;
    RowIndex := ValueListEditor.Row;
    if (RowIndex <= 0) or (RowIndex >= ValueListEditor.RowCount) then Exit;
    ParameterName := trim(ValueListEditor.Keys[RowIndex]);
    if not(length(ParameterName) >= 1) then Exit;
    if MessageDlg(
      'Remove parameter',
      'Do you really want to delete "' + ParameterName + '"?',
      mtConfirmation,
      [mbYes, mbNo],
      0) = mrYes then
    begin
      ValueListEditor.DeleteRow(RowIndex);
      if Assigned(StringList) then
      begin
        TitleIdx := StringList.IndexOfName(ParameterName);
        if not(TitleIdx = -1) then StringList.Delete(TitleIdx);
      end;
      ValueListEditor.Hint := '';
    end;
  except
    on x: Exception do
      MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);
  end;
end;

//Show hint for coordinates at valuelist editor control
procedure TSettingsForm.ShowHintForValueListCoords(ValueListEditor: TValueListEditor; StringList: TStringList; X, Y: Integer);
var
  gc: TGridCoord;
  KeyName, NewHint: string;
begin
  try
    if not(Assigned(ValueListEditor)) then Exit;
    gc := ValueListEditor.MouseToCell(Point(X, Y));
    if (gc.Y <= 0) or (gc.Y >= ValueListEditor.RowCount) or (gc.X < 0) then Exit;
    KeyName := trim(ValueListEditor.Keys[gc.Y]);
    if not(length(KeyName) >= 1) then
    begin
      ValueListEditor.Hint := '';
      Exit;
    end;
    NewHint := '';
    if Assigned(StringList) then NewHint := StringList.Values[KeyName];
    if NewHint = '' then NewHint := KeyName;
    if not(ValueListEditor.Hint = NewHint) then
    begin
      ValueListEditor.Hint := NewHint;
      Application.ActivateHint(Mouse.CursorPos);
    end;
  except
    {on x: Exception do
      MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);}
  end;
end;

//Enable or disable TTS device list
procedure TSettingsForm.UpdateTTSdeviceListAvailability(const want_to_enable_list, want_to_enable_reload: boolean);
var EngineItem: TEngineComboBoxItem;
begin
  try
    TTSdeviceLabel.Enabled := false;
    TTSdeviceCombobox.Enabled := false;
    TTSreloadDevicesButton.Enabled := false;
    if not(EnableTTScheckBox.Checked) then Exit;
    if LlamaEngineComboBox.ItemIndex < 0 then
    begin
      MessageDlg('Error', 'No engine selected!', mtError, [mbOK], 0);
      Exit;
    end;
    EngineItem := TEngineComboBoxItem(LlamaEngineComboBox.Items.Objects[LlamaEngineComboBox.ItemIndex]);
    if not(Assigned(EngineItem)) then
    begin
      MessageDlg('Error', 'Invalid engine!', mtError, [mbOK], 0);
      Exit;
    end;
    if EngineItem.TTSusesGPU = 0 then Exit;
    if want_to_enable_list then
    begin
      if TTSdeviceComboBox.Items.Count >= 1 then
      begin
        TTSdeviceLabel.Enabled := true;
        TTSdeviceCombobox.Enabled := true;
      end;
    end;
    if want_to_enable_reload then TTSreloadDevicesButton.Enabled := true;
  except
    on x: Exception do
      MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);
  end;
end;

//Add TTS parameter
procedure TSettingsForm.AddTTSparameterButtonClick(Sender: TObject);
begin
  AddParameter(TTSparameterListEditor);
end;

//Enable or disable TTS service
procedure TSettingsForm.EnableTTScheckBoxChange(Sender: TObject);
var enable_tts: boolean;
begin
  try
    enable_tts := EnableTTScheckBox.Checked;
    UpdateTTSdeviceListAvailability(enable_tts, enable_tts);
    TTSmodelsGroupBox.Enabled := enable_tts;
    TTSparameterGroupBox.Enabled := enable_tts;
  except
    on x: Exception do
      MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);
  end;
end;

//Load LLM/embedding device list
procedure TSettingsForm.ReloadDevicesButtonClick(Sender: TObject);
begin
  LoadDevices('LLAMA_CPP');
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

//Call log clearing
procedure TSettingsForm.ClearLogButtonClick(Sender: TObject);
begin
  ClearLog;
end;

//Show title for each embedding parameter
procedure TSettingsForm.EmbeddingParameterListEditorMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
begin
  ShowHintForValueListCoords(EmbeddingParameterListEditor, EmbeddingTitleList, X, Y);
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
begin
  AddParameter(EmbeddingParameterListEditor);
end;

//Import embedding model file
procedure TSettingsForm.AddEmbeddingModelButtonClick(Sender: TObject);
begin
  ImportModel('EMBEDDING');
end;

//Import model file
procedure TSettingsForm.AddModelButtonClick(Sender: TObject);
begin
  ImportModel('CONVERSATIONAL');
end;

//Load LLM/embedding device list
procedure TSettingsForm.LoadLLMdevices(EngineItem: TEngineComboBoxItem);
var
  SL: TStringList;
  i, j: Integer;
  output_line: String;
  foundDeviceHeader: Boolean;
  deviceItem: TDeviceComboBoxItem;
begin
  try
    //Check selected engine
    if not(Assigned(EngineItem)) then
    begin
      MessageDlg('Error', 'Invalid engine!', mtError, [mbOK], 0);
      Exit;
    end;
    try
      ClearLLMdeviceComboBox;
      if EngineItem.UsesGPU = 0 then Exit;
      if not(length(EngineItem.ServerBinary) >= 1) then
      begin
        MessageDlg('Error', 'Engine path not defined!', mtError, [mbOK], 0);
        Exit;
      end;
      chdir(appdir);
      if not(FileExists(EngineItem.ServerBinary)) then
      begin
        MessageDlg('Error', 'Server binary does not exist: ' + EngineItem.ServerBinary, mtError, [mbOK], 0);
        Exit;
      end;
      //Load devices
      foundDeviceHeader := false;
      SL := TStringList.Create;
      try
        LLMserverProcess.Executable := EngineItem.ServerBinary;
        LLMserverProcess.CurrentDirectory := ExtractFilePath(EngineItem.ServerBinary);
        LLMserverProcess.Execute;
        SL.LoadFromStream(LLMserverProcess.Output);
        if LLMserverProcess.Running then
        begin
          LLMserverProcess.Terminate(0);
          LLMserverProcess.WaitOnExit;
        end;
        LLMserverProcess.Active := false;
        if not(SL.Count >= 1) then Exit;
        try
          for i := 0 to SL.Count - 1 do
          begin
            output_line := trim(SL[i]);
            // Look for header
            if not(foundDeviceHeader) then
            begin
              if Pos('available devices:', lowercase(output_line)) > 0 then
              begin
                DeviceComboBox.Items.BeginUpdate;
                foundDeviceHeader := true;
              end;
              continue;
            end;
            // Parse device lines
            j := Pos(':', output_line);
            if not(j > 0) then continue;
            deviceItem := TDeviceComboBoxItem.Create;
            try
              deviceItem.ID := trim(Copy(output_line, 1, j - 1));
              deviceItem.Title := deviceItem.ID + ': ' + trim(Copy(output_line, j + 1, length(output_line)));
              if (length(deviceItem.ID) >= 1) and (length(deviceItem.Title) >= 1) then
              begin
                DeviceComboBox.Items.AddObject(deviceItem.Title, deviceItem);
                deviceItem := nil;
              end;
            finally
              if Assigned(deviceItem) then FreeAndNil(deviceItem);
            end;
          end;
        finally
          if foundDeviceHeader then DeviceComboBox.Items.EndUpdate;
        end;
      finally
        FreeAndNil(SL);
      end;
    finally
      if DeviceComboBox.Items.Count >= 1 then
      begin
        llmEmbeddingDeviceFound := true;
        DeviceComboBox.ItemIndex := 0;
        DeviceLabel.Enabled := true;
        DeviceComboBox.Enabled := true;
        Exit;
      end;
      DeviceComboBox.Items.Add('N/A');
      DeviceComboBox.ItemIndex := 0;
    end;
  except
    on x: Exception do
    begin
      MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);
      chdir(appdir);
    end;
  end;
end;

//Load TTS device list (only if TTS engine is available)
procedure TSettingsForm.LoadTTSdevices(EngineItem: TEngineComboBoxItem);
var
  SL: TStringList;
  i, j, k, m: Integer;
  output_line: String;
  foundDeviceHeader: Boolean;
  deviceItem: TDeviceComboBoxItem;
  deviceIndex, deviceType, deviceName, deviceDesc, deviceMem, deviceID: String;
  Buffer: array[0..4095] of Byte;
  BytesRead: LongInt;
  OutputStream: TMemoryStream;
  ttsBinaryFinal: AnsiString;
begin
  try
    //Check selected engine
    if not(Assigned(EngineItem)) then
    begin
      MessageDlg('Error', 'Invalid engine!', mtError, [mbOK], 0);
      Exit;
    end;
    try
      ClearTTSdeviceComboBox;
      if EngineItem.TTSusesGPU = 0 then Exit;
      ttsBinaryFinal := EngineItem.TTSbinary;
      if not(length(ttsBinaryFinal) >= 1) then
      begin
        ttsFallbackNeeded := true;
        ttsBinaryFinal := ttsFallbackBinary;
      end;
      if not(length(ttsBinaryFinal) >= 1) then Exit;
      chdir(appdir);
      if not(FileExists(ttsBinaryFinal)) then
      begin
        MessageDlg('Error', 'Server binary does not exist: ' + ttsBinaryFinal, mtError, [mbOK], 0);
        Exit;
      end;
      //Load devices
      foundDeviceHeader := false;
      SL := TStringList.Create;
      OutputStream := TMemoryStream.Create;
      try
        TTSserverProcess.Executable := ttsBinaryFinal;
        TTSserverProcess.CurrentDirectory := ExtractFilePath(ttsBinaryFinal);
        TTSserverProcess.Execute;
        SL.Clear;
        OutputStream.Clear;
        repeat
          while TTSserverProcess.Output.NumBytesAvailable > 0 do
          begin
            BytesRead := TTSserverProcess.Output.Read(Buffer, SizeOf(Buffer));
            if BytesRead > 0 then OutputStream.WriteBuffer(Buffer, BytesRead);
          end;
          if TTSserverProcess.Running then Sleep(10);
          Application.ProcessMessages;
        until not(TTSserverProcess.Running) and (TTSserverProcess.Output.NumBytesAvailable = 0);
        OutputStream.Position := 0;
        SL.LoadFromStream(OutputStream);
        if TTSserverProcess.Running then
        begin
          TTSserverProcess.Terminate(0);
          TTSserverProcess.WaitOnExit;
        end;
        TTSserverProcess.Active := false;
        if not(SL.Count >= 1) then Exit;
        try
          for i := 0 to SL.Count - 1 do
          begin
            output_line := trim(SL[i]);
            if not(foundDeviceHeader) then
            begin
              // Look for "registered devices" header
              if Pos('registered devices', lowercase(output_line)) > 0 then
              begin
                TTSdeviceComboBox.Items.BeginUpdate;
                foundDeviceHeader := true;
              end;
              continue;
            end;
            // Parse device lines like: [0] igpu   name=Vulkan0 desc=Intel(R) UHD Graphics 630 mem=... id=?
            if not(length(output_line) >= 1) then continue;
            if not(output_line[1] = '[') then continue;
            j := Pos(']', output_line);
            if not(j >= 1) then continue;
            deviceIndex := trim(Copy(output_line, 2, j - 2));
            if not(length(deviceIndex) >= 1) then continue;
            // Extract the rest: "igpu   name=Vulkan0 desc=Intel(R) UHD Graphics 630 mem=... id=?"
            output_line := trim(Copy(output_line, j + 1, length(output_line)));
            // Extract type (first word: cpu/gpu/igpu/accel)
            k := Pos(' ', output_line);
            if not(k >= 1) then continue;
            deviceType := trim(Copy(output_line, 1, k - 1));
            output_line := trim(Copy(output_line, k + 1, length(output_line)));
            // Parse key=value pairs: extract desc=, mem=, id=
            deviceDesc := '';
            deviceMem := '';
            deviceID := '';
            // Find desc= and extract until next key ( mem= or  id=) or end
            k := Pos('desc=', output_line);
            if k >= 1 then
            begin
              k := k + 5; // skip 'desc=' (5 chars)
              j := Pos(' mem=', output_line);
              if j = 0 then j := Pos(' id=', output_line);
              if j = 0 then j := length(output_line) + 1;
              deviceDesc := trim(Copy(output_line, k, j - k));
            end
            else
            begin
              // Fallback to name= if no desc=
              k := Pos('name=', output_line);
              if k >= 1 then
              begin
                k := k + 5; // skip 'name=' (5 chars)
                j := Pos(' ', Copy(output_line, k, Length(output_line)));
                if j = 0 then
                  deviceDesc := trim(Copy(output_line, k, Length(output_line)))
                else
                  deviceDesc := trim(Copy(output_line, k, j - 1));
              end;
            end;
            // Find mem=
            k := Pos('mem=', output_line);
            if k >= 1 then
            begin
              k := k + 4; // skip 'mem=' (4 chars)
              j := length(output_line) + 1;
              for m := k to length(output_line) do
              begin
                if not(output_line[m] = ' ') then continue;
                j := m;
                break;
              end;
              deviceMem := trim(Copy(output_line, k, j - k));
            end;
            // Find id=
            k := Pos('id=', output_line);
            if k >= 1 then
            begin
              k := k + 3; // skip 'id=' (3 chars)
              j := length(output_line) + 1;
              for m := k to length(output_line) do
              begin
                if not(output_line[m] = ' ') then continue;
                j := m;
                break;
              end;
              deviceID := trim(Copy(output_line, k, j - k));
            end;
            // Build display title: name: desc mem=... id=...
            deviceItem := TDeviceComboBoxItem.Create;
            try
              // ID = index from [0], [1], [2] - what --device expects
              deviceItem.ID := deviceIndex;
              // Extract name= for title prefix
              deviceName := '';
              k := Pos('name=', output_line);
              if k >= 1 then
              begin
                k := k + 5; // skip 'name=' (5 chars)
                j := Pos(' ', Copy(output_line, k, length(output_line)));
                if j = 0 then
                  deviceName := trim(Copy(output_line, k, Length(output_line)))
                else
                  deviceName := trim(Copy(output_line, k, j - 1));
              end;
              // Title = full description like: Vulkan0: Intel(R) UHD Graphics 630 mem=14661/16290 MiB id=?
              if length(deviceName) >= 1 then
                deviceItem.Title := deviceName
              else
                deviceItem.Title := deviceType;
              if length(deviceDesc) >= 1 then deviceItem.Title := deviceItem.Title + ': ' + deviceDesc;
              if (length(deviceMem) >= 1) or (length(deviceID) >= 1) then
              begin
                deviceItem.Title := deviceItem.Title + ' (';
                if length(deviceMem) >= 1 then
                begin
                  deviceItem.Title := deviceItem.Title + 'mem: ' + deviceMem;
                  if Pos('MIB', UpperCase(deviceMem)) = 0 then deviceItem.Title := deviceItem.Title + ' MiB';
                end;
                if length(deviceID) >= 1 then
                begin
                  if length(deviceMem) >= 1 then deviceItem.Title := deviceItem.Title + ', ';
                  deviceItem.Title := deviceItem.Title + 'id: ' + deviceID;
                end;
                deviceItem.Title := deviceItem.Title + ')';
              end;
              if (length(deviceItem.ID) >= 1) and (length(deviceItem.Title) >= 1) then
              begin
                TTSdeviceComboBox.Items.AddObject(deviceItem.Title, deviceItem);
                deviceItem := nil;
              end;
            finally
              if Assigned(deviceItem) then FreeAndNil(deviceItem);
            end;
          end;
        finally
          if foundDeviceHeader then TTSdeviceComboBox.Items.EndUpdate;
        end;
      finally
        FreeAndNil(SL);
        FreeAndNil(OutputStream);
        if not(TTSdeviceComboBox.Items.Count >= 1) then ttsFallbackNeeded := true;
      end;
    finally
      if TTSdeviceComboBox.Items.Count >= 1 then
      begin
        ttsDeviceFound := true;
        TTSdeviceComboBox.ItemIndex := 0;
        UpdateTTSdeviceListAvailability(true, true);
        Exit;
      end;
      TTSdeviceComboBox.Items.Add('N/A');
      TTSdeviceComboBox.ItemIndex := 0;
    end;
  except
    on x: Exception do
    begin
      MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);
      chdir(appdir);
    end;
  end;
end;

//Load device list
procedure TSettingsForm.LoadDevices(const Engine: string = 'LLAMA_CPP');
var
  EngineFixed: string;
  EngineItem: TEngineComboBoxItem;
begin
  try
    //Check selected engine
    if LlamaEngineComboBox.ItemIndex < 0 then
    begin
      MessageDlg('Error', 'No engine selected!', mtError, [mbOK], 0);
      Exit;
    end;
    EngineItem := TEngineComboBoxItem(LlamaEngineComboBox.Items.Objects[LlamaEngineComboBox.ItemIndex]);
    if not(Assigned(EngineItem)) then
    begin
      MessageDlg('Error', 'Invalid engine!', mtError, [mbOK], 0);
      Exit;
    end;
    //Load devices for the selected engine
    EngineFixed := UpperCase(trim(Engine));
    if not(length(EngineFixed) >= 1) then
    begin
      MessageDlg('Error', 'Target engine not specified!', mtError, [mbOK], 0);
      Exit;
    end;
    if EngineFixed = 'LLAMA_CPP' then
    begin
      LoadLLMdevices(EngineItem);
      Exit;
    end;
    if EngineFixed = 'TTS' then
    begin
      LoadTTSdevices(EngineItem);
      Exit;
    end;
    MessageDlg('Error', 'Invalid engine: ' + EngineFixed, mtError, [mbOK], 0);
  except
    on x: Exception do
      MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);
  end;
end;

//Load default settings
procedure TSettingsForm.LoadDefaultConfig;
var
  engineItem: TEngineComboBoxItem;
  configID, ttsUsesGPU, paramConfigID, RowIndex: Integer;
  modelFromDB, embeddingModelFromDB: String;
  ttsMainModelFromDB, ttsVoiceModelFromDB: String;
  paramFound, embeddingParamFound, ttsParamFound: boolean;
  paramName, paramTitle, paramType, configName, configValue: String;
  //Check if parameter can be processed (helper)
  function CanProcessParameter(const isProcessed: boolean): boolean;
  begin
    Result := false;
    if paramType = 'TTS' then
    begin
      if ttsFallbackNeeded then
      begin
        if not(ttsUsesGPU = 0) then Exit;
        if isProcessed then Exit;
        Result := true;
        Exit;
      end;
    end;
    if not(paramConfigID = configID) then Exit;
    Result := true;
  end;
begin
  try
    //Defaults
    saveSettingsError := false;
    EnableLLMcheckBox.Checked := true;
    EnableEmbeddingCheckBox.Checked := true;
    EnableTTScheckBox.Checked := false;
    TTSdeviceLabel.Enabled := false;
    TTSdeviceCombobox.Enabled := false;
    TTSreloadDevicesButton.Enabled := false;
    LLMloggingCheckBox.Checked := true;
    LLMproxyServicePort.Text := '';
    LLMproxyServiceTimeout.Value := 60;
    LLMproxyServiceMaxConnections.Value := 200;
    LLMproxyServiceMaxPackageSize.Value := 2097152;
    llmConversationalPort := 8080;
    llmEmbeddingPort := 8081;
    llmTTSport := 8082;
    llmProxyLocation := '/llamacpp/';
    ttsFallbackNeeded := false;
    llmEmbeddingDeviceFound := false;
    ttsDeviceFound := false;
    //Validate selected engine
    if LlamaEngineComboBox.ItemIndex < 0 then Exit;
    engineItem := TEngineComboBoxItem(LlamaEngineComboBox.Items.Objects[LlamaEngineComboBox.ItemIndex]);
    if not(Assigned(engineItem)) then Exit;
    configID := StrToIntDef(engineItem.ID, 0);
    if configID = 0 then Exit;
    //Load engine defaults
    if length(engineItem.ProxyPort) >= 1 then LLMproxyServicePort.Text := engineItem.ProxyPort;
    if engineItem.ProxyTimeout >= 1 then LLMproxyServiceTimeout.Value := engineItem.ProxyTimeout;
    if engineItem.ProxyMaxConnections >= 1 then LLMproxyServiceMaxConnections.Value := engineItem.ProxyMaxConnections;
    if engineItem.ProxyMaxPackageSize >= 1 then LLMproxyServiceMaxPackageSize.Value := engineItem.ProxyMaxPackageSize;
    if not(length(engineItem.TTSbinary) >= 1) then ttsFallbackNeeded := true;
    GeneralTTSsettingsGroupBox.Enabled := (((length(engineItem.TTSbinary) >= 1) or (length(ttsFallbackBinary) >= 1)) and ttsModelsAvailable);
    ReloadDevicesButton.Enabled := not(engineItem.UsesGPU = 0);
    //Load devices
    LoadDevices('LLAMA_CPP');
    LoadDevices('TTS');
    //Clear parameters
    ParameterListEditor.Strings.Clear;
    EmbeddingParameterListEditor.Strings.Clear;
    TTSparameterListEditor.Strings.Clear;
    TitleList.Clear;
    EmbeddingTitleList.Clear;
    TTStitleList.Clear;
    modelFromDB := '';
    embeddingModelFromDB := '';
    ttsMainModelFromDB := '';
    ttsVoiceModelFromDB := '';
    //Connect to database
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
    //Load default LLM config data from database
    ConfigDataQuery.Close;
    ConfigDataQuery.ParamByName('cid').AsInteger := configID;
    ConfigDataQuery.Open;
    paramFound := false;
    embeddingParamFound := false;
    ttsParamFound := false;
    while not(ConfigDataQuery.EOF) do
    begin
      //Load default parameters from database
      paramConfigID := StrToIntDef(trim(ConfigDataQuery.FieldByName('config_id').AsString), -1);
      ttsUsesGPU := StrToIntDef(trim(ConfigDataQuery.FieldByName('tts_uses_gpu').AsString), -1);
      paramName := trim(ConfigDataQuery.FieldByName('name').AsString);
      paramTitle := trim(ConfigDataQuery.FieldByName('title').AsString) + ': ' + trim(ConfigDataQuery.FieldByName('description').AsString);
      paramType := uppercase(trim(ConfigDataQuery.FieldByName('type_name').AsString));
      //Load default model from database
      if SameText(paramName, 'model') then
      begin
        if CanProcessParameter(length(ttsMainModelFromDB) >= 1) then
        begin
          if paramType = 'TTS' then
            ttsMainModelFromDB := trim(ConfigDataQuery.FieldByName('value').AsString)
          else if paramType = 'EMBEDDING' then
            embeddingModelFromDB := trim(ConfigDataQuery.FieldByName('value').AsString)
          else if paramType = 'CONVERSATIONAL' then
            modelFromDB := trim(ConfigDataQuery.FieldByName('value').AsString);
        end;
      end
      else if not(MatchStr(paramName, ['device', 'user_home_dir', 'cache-dir', 'voice-dir', 'punctuation_restoration_model'])) then
      begin
        //Load default port from database
        if SameText(paramName, 'port') then
        begin
          if CanProcessParameter(llmTTSport = 8082) then
          begin
            if paramType = 'TTS' then
              llmTTSport := StrToIntDef(trim(ConfigDataQuery.FieldByName('value').AsString), 8082)
            else if paramType = 'EMBEDDING' then
              llmEmbeddingPort := StrToIntDef(trim(ConfigDataQuery.FieldByName('value').AsString), 8081)
            else if paramType = 'CONVERSATIONAL' then
              llmConversationalPort := StrToIntDef(trim(ConfigDataQuery.FieldByName('value').AsString), 8080);
          end;
        end;
        //Load remaining default TTS parameters from database with fallback
        if paramType = 'TTS' then
        begin
          //TTS voice model
          if SameText(paramName, 'voice') then
          begin
            if CanProcessParameter(length(ttsVoiceModelFromDB) >= 1) then ttsVoiceModelFromDB := trim(ConfigDataQuery.FieldByName('value').AsString);
          end
          else if CanProcessParameter(TTSparameterListEditor.FindRow(paramName, RowIndex)) then
          begin
            //Generic TTS parameters
            TTSparameterListEditor.InsertRow(
              paramName,
              trim(ConfigDataQuery.FieldByName('value').AsString),
              true);
            TTStitleList.Values[paramName] := paramTitle;
            ttsParamFound := true;
          end;
        end
        else if paramConfigID = configID then
        begin
          //Load remaining embedding parameters from database (no fallback)
          if paramType = 'EMBEDDING' then
          begin
            EmbeddingParameterListEditor.InsertRow(
              paramName,
              trim(ConfigDataQuery.FieldByName('value').AsString),
              true);
            EmbeddingTitleList.Values[paramName] := paramTitle;
            embeddingParamFound := true;
          end
          else if paramType = 'CONVERSATIONAL' then
          begin
            //Load remaining conversational parameters from database (no fallback)
            ParameterListEditor.InsertRow(
              paramName,
              trim(ConfigDataQuery.FieldByName('value').AsString),
              true);
            TitleList.Values[ParamName] := paramTitle;
            paramFound := true;
          end;
        end;
      end;
      ConfigDataQuery.Next;
    end;
    ConfigDataQuery.Close;
    //Load default web server config data from database
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
    //Set default PHP time zone
    PHPtimezoneCombobox.ItemIndex := DefaultPHPtimezone;
    try
      //Apply default parameters
      if paramFound then ParameterListEditor.Row := 1;
      if embeddingParamFound then EmbeddingParameterListEditor.Row := 1;
      if ttsParamFound then TTSparameterListEditor.Row := 1;
      //Apply default LLM model
      if length(modelFromDB) >= 1 then
      begin
        ModelComboBox.ItemIndex := ModelComboBox.Items.IndexOf(modelFromDB);
        if ModelComboBox.ItemIndex = -1 then
        begin
          if ModelComboBox.Items.Count >= 1 then ModelComboBox.ItemIndex := 0;
          MessageDlg('Error', 'The selected language model not found in model directory!', mtError, [mbOK], 0);
        end;
      end;
      //Apply default embedding model
      if length(embeddingModelFromDB) >= 1 then
      begin
        EmbeddingModelComboBox.ItemIndex := EmbeddingModelComboBox.Items.IndexOf(embeddingModelFromDB);
        if EmbeddingModelComboBox.ItemIndex = -1 then
        begin
          if EmbeddingModelComboBox.Items.Count >= 1 then EmbeddingModelComboBox.ItemIndex := 0;
          MessageDlg('Error', 'The selected embedding model not found in model directory!', mtError, [mbOK], 0);
        end;
      end;
      //Apply default main TTS model
      if length(ttsMainModelFromDB) >= 1 then
      begin
        MainTTSmodelComboBox.ItemIndex := MainTTSmodelComboBox.Items.IndexOf(ttsMainModelFromDB);
        if MainTTSmodelComboBox.ItemIndex = -1 then
        begin
          if MainTTSmodelComboBox.Items.Count >= 1 then MainTTSmodelComboBox.ItemIndex := 0;
        end;
      end;
      //Apply default TTS voice model
      if length(ttsVoiceModelFromDB) >= 1 then
      begin
        VoiceTTSmodelComboBox.ItemIndex := VoiceTTSmodelComboBox.Items.IndexOf(ttsVoiceModelFromDB);
        if VoiceTTSmodelComboBox.ItemIndex = -1 then
        begin
          if VoiceTTSmodelComboBox.Items.Count >= 1 then VoiceTTSmodelComboBox.ItemIndex := 0;
        end;
      end;
    finally
      //Close database connection
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
          personaItem.defaultTheme := uppercase(trim(PersonaQuery.FieldByName('default_theme').AsString));
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
      paramValue := uppercase(trim(RootObj.Get('default_theme', '')));
      if length(paramValue) >= 1 then
      begin
        if paramValue = 'DARK' then
        begin
          DefaultThemeDarkRadioButton.Checked := true;
          DefaultThemeLightRadioButton.Checked := false;
        end
        else
        begin
          DefaultThemeLightRadioButton.Checked := true;
          DefaultThemeDarkRadioButton.Checked := false;
        end;
      end;
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
  if not(length(FormatExt) >= 1) then FormatExt := 'png';
  Result := 'image.' + FormatExt;
end;

//Remove TTS parameter
procedure TSettingsForm.RemoveTTSparameterButtonClick(Sender: TObject);
begin
  RemoveParameter(TTSparameterListEditor, TTStitleList);
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
  procedure ProcessImage(const JSONStr: AnsiString; TargetImage: TImage);
    var ImageFileName: AnsiString;
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
    if length(personaItem.defaultTheme) >= 1 then
    begin
      if personaItem.defaultTheme = 'DARK' then
      begin
        DefaultThemeDarkRadioButton.Checked := true;
        DefaultThemeLightRadioButton.Checked := false;
      end
      else
      begin
        DefaultThemeLightRadioButton.Checked := true;
        DefaultThemeDarkRadioButton.Checked := false;
      end;
    end;
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
var
  engineItem: TEngineComboBoxItem;
  TTSusesGPU: boolean;
begin
  try
    if not(canHandleEngineChange) then Exit;
    if MessageDlg(
         'Load Defaults',
         'Load default configuration for the selected engine?',
         mtConfirmation,
         [mbYes, mbNo],
         0
       ) = mrYes then
    begin
      LoadDefaultConfig;
      Exit;
    end;
    if LlamaEngineComboBox.ItemIndex < 0 then Exit;
    engineItem := TEngineComboBoxItem(LlamaEngineComboBox.Items.Objects[LlamaEngineComboBox.ItemIndex]);
    if not(Assigned(engineItem)) then Exit;
    if not(length(engineItem.TTSbinary) >= 1) then ttsFallbackNeeded := true;
    GeneralTTSsettingsGroupBox.Enabled := (((length(engineItem.TTSbinary) >= 1) or (length(ttsFallbackBinary) >= 1)) and ttsModelsAvailable);
    if not(GeneralTTSsettingsGroupBox.Enabled) then EnableTTScheckBox.Checked := false;
    ReloadDevicesButton.Enabled := not(engineItem.UsesGPU = 0);
    LoadDevices('LLAMA_CPP');
    LoadDevices('TTS');
    TTSusesGPU := not(engineItem.TTSusesGPU = 0);
    UpdateTTSdeviceListAvailability(TTSusesGPU, TTSusesGPU);
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
    if length(CGItempDirectory) >= 1 then
    begin
      if DirectoryExists(CGItempDirectory) then
      begin
        if not(WebUIprocessRunning) then
        begin
          if FindFirst(CGItempDirectory + '*', faAnyFile, SR) = 0 then
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
  JSONData, EngineNode, LLMnode, EmbeddingNode, TTSnode, LogNode: TJSONData;
  WebServerData, ProxyPortNode, ProxyTimeoutNode, ProxyMaxConnectionsNode, ProxyMaxPackageSizeNode: TJSONData;
  httpPortNode, httpsPortNode, sslCertNode, sslKeyNode, phpPortNode: TJSONData;
  RootObj, ParamsObj, WebServerObj: TJSONObject;
  JSONList: TStringList;
  loadedEngineID, loadedModel, loadedEmbeddingModel, loadedTTSmainModel, loadedTTSvoiceModel, loadedTimezone: String;
  engineItem: TEngineComboBoxItem;
  deviceItem: TDeviceComboBoxItem;
  i, foundIndex: Integer;
  paramFound: boolean;
  paramName, paramValue: String;
  UsesGPU, TTSusesGPU: boolean;
begin
  //Default values
  saveSettingsError := false;
  JSONList := TStringList.Create;
  JSONData := nil;
  try
    try
      //Reset working directory
      chdir(appdir);
      //Load defaults if config file does not exist
      if not(FileExists(wrapperConfigFile)) then
      begin
        if LlamaEngineComboBox.Items.Count > 0 then
        begin
          LlamaEngineComboBox.ItemIndex := 0;
          LoadDefaultConfig;
        end;
        Exit;
      end;
      //Load config file
      JSONList.LoadFromFile(wrapperConfigFile);
      JSONData := GetJSON(JSONList.Text);
      if not(JSONData is TJSONObject) then Exit;
      RootObj := TJSONObject(JSONData);
      //Set LLM engine
      EngineNode := RootObj.Find('llama_engine');
      if Assigned(EngineNode) then
        loadedEngineID := trim(EngineNode.AsString)
      else
        loadedEngineID := '';
      //Load defaults for selected engine
      UsesGPU := false;
      TTSusesGPU := false;
      if length(loadedEngineID) >= 1 then
      begin
        if LlamaEngineComboBox.Items.Count >= 1 then
        begin
          for i := 0 to LlamaEngineComboBox.Items.Count - 1 do
          begin
            engineItem := TEngineComboBoxItem(LlamaEngineComboBox.Items.Objects[i]);
            if not(Assigned(engineItem)) then continue;
            if not(engineItem.ID = loadedEngineID) then continue;
            UsesGPU := not(engineItem.UsesGPU = 0);
            TTSusesGPU := not(engineItem.TTSusesGPU = 0);
            LlamaEngineComboBox.ItemIndex := i;
            //We must trigger LoadDefaultConfig here because changing the engine
            //usually changes which parameters and models are valid in the DB
            LoadDefaultConfig;
            break;
          end;
        end;
      end;
      //Set LLM device
      if UsesGPU and (DeviceComboBox.Items.Count >= 1) then
      begin
        paramValue := trim(RootObj.Get('llama_device', ''));
        if length(paramValue) >= 1 then
        begin
          foundIndex := -1;
          for i := 0 to DeviceComboBox.Items.Count -1 do
          begin
            deviceItem := TDeviceComboBoxItem(DeviceComboBox.Items.Objects[i]);
            if not(Assigned(deviceItem)) then continue;
            if not(deviceItem.ID = paramValue) then continue;
            foundIndex := i;
            break;
          end;
          if not(foundIndex = -1) then DeviceComboBox.ItemIndex := foundIndex;
        end;
      end;
      //Set TTS device
      if TTSusesGPU and (TTSdeviceCombobox.Items.Count >= 1) then
      begin
        paramValue := trim(RootObj.Get('tts_device', ''));
        if length(paramValue) >= 1 then
        begin
          foundIndex := -1;
          for i := 0 to TTSdeviceCombobox.Items.Count-1 do
          begin
            deviceItem := TDeviceComboBoxItem(TTSdeviceCombobox.Items.Objects[i]);
            if not(Assigned(deviceItem)) then continue;
            if not(deviceItem.ID = paramValue) then continue;
            foundIndex := i;
            break;
          end;
          if not(foundIndex = -1) then TTSdeviceCombobox.ItemIndex := foundIndex;
        end;
      end;
      //Load LLM model
      loadedModel := trim(RootObj.Get('model', ''));
      if length(loadedModel) >= 1 then
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
      //Load embedding model
      loadedEmbeddingModel := trim(RootObj.Get('embedding_model', ''));
      if length(loadedEmbeddingModel) >= 1 then
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
      //Load main TTS model
      loadedTTSmainModel := trim(RootObj.Get('tts_model_main', ''));
      if length(loadedTTSmainModel) >= 1 then
      begin
        foundIndex := MainTTSmodelComboBox.Items.IndexOf(loadedTTSmainModel);
        if foundIndex = -1 then
        begin
          if MainTTSmodelComboBox.Items.Count >= 1 then MainTTSmodelComboBox.ItemIndex := 0;
        end
        else
          MainTTSmodelComboBox.ItemIndex := foundIndex;
      end;
      //Load TTS voice model
      loadedTTSvoiceModel := trim(RootObj.Get('tts_model_voice', ''));
      if length(loadedTTSvoiceModel) >= 1 then
      begin
        foundIndex := VoiceTTSmodelComboBox.Items.IndexOf(loadedTTSvoiceModel);
        if foundIndex = -1 then
        begin
          if VoiceTTSmodelComboBox.Items.Count >= 1 then VoiceTTSmodelComboBox.ItemIndex := 0;
        end
        else
          VoiceTTSmodelComboBox.ItemIndex := foundIndex;
      end;
      //Enable or disable LLM service
      LLMnode := RootObj.Find('llm_enabled');
      if Assigned(LLMnode) then
      begin
        if LLMnode.JSONType = jtNumber then
          EnableLLMcheckBox.Checked := not(LLMnode.AsInteger = 0)
        else
          EnableLLMcheckBox.Checked := (IndexStr(LowerCase(trim(LLMnode.AsString)), ['0', 'false', 'no']) = -1);
      end;
      //Enable or disable embedding service
      EmbeddingNode := RootObj.Find('embedding');
      if Assigned(EmbeddingNode) then
      begin
        if EmbeddingNode.JSONType = jtNumber then
          EnableEmbeddingCheckBox.Checked := not(EmbeddingNode.AsInteger = 0)
        else
          EnableEmbeddingCheckBox.Checked := (IndexStr(LowerCase(trim(EmbeddingNode.AsString)), ['0', 'false', 'no']) = -1);
      end;
      //Enable or disable TTS service
      TTSnode := RootObj.Find('tts');
      if Assigned(TTSnode) then
      begin
        if TTSnode.JSONType = jtNumber then
          EnableTTScheckBox.Checked := (not(TTSnode.AsInteger = 0) and GeneralTTSsettingsGroupBox.Enabled)
        else
          EnableTTScheckBox.Checked := ((IndexStr(LowerCase(trim(TTSnode.AsString)), ['0', 'false', 'no']) = -1) and GeneralTTSsettingsGroupBox.Enabled);
      end;
      //Enable or disable logging
      LogNode := RootObj.Find('logging');
      if Assigned(LogNode) then
      begin
        if LogNode.JSONType = jtNumber then
          LLMloggingCheckBox.Checked := not(LogNode.AsInteger = 0)
        else
          LLMloggingCheckBox.Checked := (IndexStr(LowerCase(trim(LogNode.AsString)), ['0', 'false', 'no']) = -1);
      end;
      //Set proxy port number
      ProxyPortNode := RootObj.Find('proxy_port');
      if Assigned(ProxyPortNode) then
        LLMproxyServicePort.Text := trim(ProxyPortNode.AsString)
      else
        LLMproxyServicePort.Text := '';
      //Set proxy timeout
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
      //Set max proxy connections
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
      //Set max proxy package size
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
      //Get LLM parameters
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
      //Get embedding parameters
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
      //Get TTS parameters
      ParamsObj := RootObj.Get('tts_parameters', TJSONObject(nil));
      if Assigned(ParamsObj) then
      begin
        paramFound := false;
        TTSparameterListEditor.Strings.Clear;
        for i := 0 to ParamsObj.Count - 1 do
        begin
          paramName := trim(ParamsObj.Names[i]);
          paramValue := trim(ParamsObj.Items[i].AsString);
          TTSparameterListEditor.InsertRow(paramName, paramValue, true);
          if Assigned(TTStitleList) and (TTStitleList.Values[paramName] = '') then
            TTStitleList.Values[paramName] := paramName;
          if SameText(paramName, 'port') then
            llmTTSport := StrToIntDef(paramValue, 8082);
          paramFound := true;
        end;
        if paramFound then TTSparameterListEditor.Row := 1;
      end;
      //Load web server settings
      WebServerData := RootObj.Find('webserver');
      if Assigned(WebServerData) then
      begin
        if WebServerData.JSONType = jtObject then
        begin
          WebServerObj := TJSONObject(WebServerData);
          //Set HTTP port
          httpPortNode := WebServerObj.Find('nginx_http_port');
          if Assigned(httpPortNode) then
          begin
            if httpPortNode.JSONType = jtNumber then
              NginxHTTPport.Value := httpPortNode.AsInteger
            else
              NginxHTTPport.Value := StrToIntDef(trim(httpPortNode.AsString), 80);
          end;
          //Set HTTPS port
          httpsPortNode := WebServerObj.Find('nginx_https_port');
          if Assigned(httpsPortNode) then
          begin
            if httpsPortNode.JSONType = jtNumber then
              NginxHTTPSport.Value := httpsPortNode.AsInteger
            else
              NginxHTTPSport.Value := StrToIntDef(trim(httpsPortNode.AsString), 443);
          end;
          //Load SSL certificate settings
          sslCertNode := WebServerObj.Find('nginx_ssl_certificate');
          if Assigned(sslCertNode) then
            SSLcertificate.Text := StringReplace(trim(sslCertNode.AsString), '/', PathDelim, [rfReplaceAll]);
          sslKeyNode := WebServerObj.Find('nginx_ssl_key');
          if Assigned(sslKeyNode) then
            SSLkey.Text := StringReplace(trim(sslKeyNode.AsString), '/', PathDelim, [rfReplaceAll]);
          //Set PHP port
          phpPortNode := WebServerObj.Find('php_http_port');
          if Assigned(phpPortNode) then
          begin
            if phpPortNode.JSONType = jtNumber then
              PHPhttpPort.Value := phpPortNode.AsInteger
            else
              PHPhttpPort.Value := StrToIntDef(trim(phpPortNode.AsString), 9000);
          end;
          //Set PHP timezone
          loadedTimezone := trim(WebServerObj.Get('php_timezone', ''));
          if length(loadedTimezone) >= 1 then
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
      //Basic validation
      if not(EnableLLMcheckBox.Checked) and not(EnableEmbeddingCheckBox.Checked) then
        MessageDlg('Warning', 'Both LLM and embedding services are disabled. AI chat functionality will not work.', mtWarning, [mbOK], 0);
      //Reset current directory
      chdir(appdir);
      //Validate config directory
      if not(length(configdir) >= 1) then
      begin
        MessageDlg('Error', 'Config directory not specified!', mtError, [mbOK], 0);
        Exit;
      end;
      if not(DirectoryExists(configdir)) then
      begin
        if not(ForceDirectories(configdir)) then
        begin
          MessageDlg('Error', 'Failed to create config directory: ' + configdir, mtError, [mbOK], 0);
          Exit;
        end;
      end;
      //Validate persona config filename
      if not(length(personaConfigFile) >= 1) then
      begin
        MessageDlg('Error', 'Persona config file not specified!', mtError, [mbOK], 0);
        Exit;
      end;
      //Enable or disable LLM engine
      if EnableLLMcheckBox.Checked then
        RootObj.Add('llm_enabled', 1)
      else
        RootObj.Add('llm_enabled', 0);
      //LLM engine
      if not(LlamaEngineComboBox.ItemIndex = -1) then
      begin
        if Assigned(LlamaEngineComboBox.Items.Objects[LlamaEngineComboBox.ItemIndex]) then
        begin
          engineItem := TEngineComboBoxItem(LlamaEngineComboBox.Items.Objects[LlamaEngineComboBox.ItemIndex]);
          EngineID := StrToIntDef(trim(engineItem.ID), 0);
          if EngineID >= 1 then RootObj.Add('llama_engine', EngineID);
        end;
      end;
      //LLM device
      if llmEmbeddingDeviceFound and not(DeviceComboBox.ItemIndex = -1) then
      begin
        if Assigned(DeviceComboBox.Items.Objects[DeviceComboBox.ItemIndex]) then
        begin
          deviceItem := TDeviceComboBoxItem(DeviceComboBox.Items.Objects[DeviceComboBox.ItemIndex]);
          DeviceID := trim(deviceItem.ID);
          if length(DeviceID) >= 1 then RootObj.Add('llama_device', DeviceID);
        end;
      end;
      //Enable or disable logging
      if LLMloggingCheckBox.Checked then
        RootObj.Add('logging', 1)
      else
        RootObj.Add('logging', 0);
      //Proxy settings
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
      //LLM model
      if length(trim(ModelComboBox.Text)) >= 1 then RootObj.Add('model', trim(ModelComboBox.Text));
      //LLM parameters
      if ParameterListEditor.RowCount >= 2 then
      begin
        ParamsObj := TJSONObject.Create;
        for i := 1 to ParameterListEditor.RowCount - 1 do
        begin
          KeyName := trim(ParameterListEditor.Keys[i]);
          if not(length(KeyName) >= 1) then continue;
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
      //Check LLM port availability
      if not(PortsReserved.IndexOf(IntToStr(llmConversationalPort)) = -1) then
        raise SaveSettingsFatal.Create('Error: LLM port already reserved: ' + IntToStr(llmConversationalPort));
      PortsReserved.Add(IntToStr(llmConversationalPort));
      //Enable or disable embedding
      if EnableEmbeddingCheckBox.Checked then
        RootObj.Add('embedding', 1)
      else
        RootObj.Add('embedding', 0);
      //Embedding model
      if length(trim(EmbeddingModelCombobox.Text)) >= 1 then RootObj.Add('embedding_model', trim(EmbeddingModelCombobox.Text));
      //Embedding parameters
      if EmbeddingParameterListEditor.RowCount >= 2 then
      begin
        ParamsObj := TJSONObject.Create;
        for i := 1 to EmbeddingParameterListEditor.RowCount - 1 do
        begin
          KeyName := trim(EmbeddingParameterListEditor.Keys[i]);
          if not(length(KeyName) >= 1) then continue;
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
      //Check embedding port availability
      if not(PortsReserved.IndexOf(IntToStr(llmEmbeddingPort)) = -1) then
        raise SaveSettingsFatal.Create('Error: embedding port already reserved: ' + IntToStr(llmEmbeddingPort));
      PortsReserved.Add(IntToStr(llmEmbeddingPort));
      //Enable or disable TTS
      if EnableTTScheckBox.Checked then
        RootObj.Add('tts', 1)
      else
        RootObj.Add('tts', 0);
      //TTS device
      if ttsDeviceFound and not(TTSdeviceCombobox.ItemIndex = -1) then
      begin
        if Assigned(TTSdeviceCombobox.Items.Objects[TTSdeviceCombobox.ItemIndex]) then
        begin
          deviceItem := TDeviceComboBoxItem(TTSdeviceCombobox.Items.Objects[TTSdeviceCombobox.ItemIndex]);
          DeviceID := trim(deviceItem.ID);
          if length(DeviceID) >= 1 then RootObj.Add('tts_device', DeviceID);
        end;
      end;
      //TTS fallback status
      if ttsFallbackNeeded then RootObj.Add('tts_fallback_needed', 1);
      //TTS models
      if length(trim(MainTTSmodelComboBox.Text)) >= 1 then RootObj.Add('tts_model_main', trim(MainTTSmodelComboBox.Text));
      if length(trim(VoiceTTSmodelComboBox.Text)) >= 1 then RootObj.Add('tts_model_voice', trim(VoiceTTSmodelComboBox.Text));
      //TTS parameters
      if TTSparameterListEditor.RowCount >= 2 then
      begin
        ParamsObj := TJSONObject.Create;
        for i := 1 to TTSparameterListEditor.RowCount - 1 do
        begin
          KeyName := trim(TTSparameterListEditor.Keys[i]);
          if not(length(KeyName) >= 1) then continue;
          NewValue := trim(TTSparameterListEditor.Values[TTSparameterListEditor.Keys[i]]);
          if lowercase(KeyName) = 'port' then
          begin
            llmTTSport := StrToIntDef(NewValue, llmTTSport);
            ParamsObj.Add(KeyName, IntToStr(llmTTSport));
          end
          else
            ParamsObj.Add(KeyName, NewValue);
        end;
        RootObj.Add('tts_parameters', ParamsObj);
        ParamsObj := nil;
      end;
      //Check TTS port availability
      if not(PortsReserved.IndexOf(IntToStr(llmTTSport)) = -1) then
        raise SaveSettingsFatal.Create('Error: TTS port already reserved: ' + IntToStr(llmTTSport));
      PortsReserved.Add(IntToStr(llmTTSport));
      //Nginx settings
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
      //PHP settings
      if not(PortsReserved.IndexOf(IntToStr(PHPhttpPort.Value)) = -1) then
        raise SaveSettingsFatal.Create('Error: PHP port already reserved: ' + IntToStr(PHPhttpPort.Value));
      PortsReserved.Add(IntToStr(PHPhttpPort.Value));
      ParamsObj.Add('php_http_port', PHPhttpPort.Value);
      ParamsObj.Add('php_timezone', trim(PHPtimezoneCombobox.Text));
      //Store web server settings
      RootObj.Add('webserver', ParamsObj);
      //Delete JSON node pointer
      ParamsObj := nil;
      //Save settings to file
      JSONList.Text := RootObj.FormatJSON();
      JSONList.SaveToFile(wrapperConfigFile);
      //Free up memory
      FreeAndNil(JSONList);
      //Apply PHP time zone settings
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
      //Apply Nginx settings
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
      //Personality settings
      PersonaObj := TJSONObject.Create;
      JSONList := TStringList.Create;
      try
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
        if DefaultThemeDarkRadioButton.Checked then
          PersonaObj.Add('default_theme', 'DARK')
        else
          PersonaObj.Add('default_theme', 'LIGHT');
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
        //Update CEF-redirect file
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
          Exit;
        end;
      end;
      configDataSaved := true;
    except
      on x: SaveSettingsFatal do
      begin
        saveSettingsError := true;
        MessageDlg('Error', x.Message, mtError, [mbOK], 0);
        Exit;
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
  TTSserverFileName: String;
  TTSserverFilePath: AnsiString;
  PHPtimezone: String;
  TimezoneIndex: integer;
  item: TEngineComboBoxItem;
  ttsModelItem: TTTSmodel;
begin
  try
    //Basic settings
    llmConversationalPort := 8080;
    llmEmbeddingPort := 8081;
    llmTTSport := 8082;
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
    TTStitleList := TStringList.Create;
    TTStitleList.Sorted := true;
    TTStitleList.Duplicates := dupIgnore;
    canHandleEngineChange := false;
    configDataSaved := false;
    saveSettingsError := false;
    MainLLMserverProcessRunning := false;
    WebUIprocessRunning := false;
    DefaultPHPtimezone := -1;
    ttsFallbackNeeded := false;
    ttsFallbackBinary := '';
    ttsModelsAvailable := false;
    llmEmbeddingDeviceFound := false;
    ttsDeviceFound := false;
    defaultTTSmodelList :=  TTTSmodelList.Create;
    //Directories and files
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
    ttsModeldir := modeldir + 'tts' + PathDelim;
    if not(DirectoryExists(ttsModeldir)) then ttsModeldir := '';
    if length(ttsModeldir) >= 1 then
      ttsRegisterFile := ttsModeldir + 'register.json'
    else
      ttsRegisterFile := '';
    configdir := appdir + 'config' + PathDelim;
    if not(DirectoryExists(configdir)) then ForceDirectories(configdir);
    wrapperConfigFile := configdir + 'wrapper.json';
    personaConfigFile := configdir + 'personality.json';
    logDirectory := appdir + 'log' + PathDelim;
    logFile := logDirectory + 'wrapper.log';
    TempDirectory := appdir + 'temp' + PathDelim;
    CGItempDirectory := webserverdir + 'temp' + PathDelim;
    CacheDirectory := webserverdir + 'www' + PathDelim + 'frontend' + PathDelim + 'var' + PathDelim + 'cache' + PathDelim;
    try
      // DO NOT delete WAL/SHM files before opening - let SQLite handle them
      {if FileExists(wrapperDbFileWAL) then DeleteFile(wrapperDbFileWAL);
      if FileExists(wrapperDbFileSHM) then DeleteFile(wrapperDbFileSHM);}
      //Load available Llama engines
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
          item.UsesGPU := StrToIntDef(trim(LlamaQuery.FieldByName('uses_gpu').AsString), 0);
          item.ProxyPort := trim(LlamaQuery.FieldByName('proxy_port').AsString);
          item.ProxyTimeout := StrToIntDef(trim(LlamaQuery.FieldByName('proxy_timeout').AsString), 1);
          item.ProxyMaxConnections := StrToIntDef(trim(LlamaQuery.FieldByName('max_proxy_connections').AsString), 1);
          item.ProxyMaxPackageSize := StrToIntDef(trim(LlamaQuery.FieldByName('max_package_size').AsString), 1);
          item.TTSusesGPU := StrToIntDef(trim(LlamaQuery.FieldByName('tts_uses_gpu').AsString), 0);
          TTSserverFileName := trim(LlamaQuery.FieldByName('tts_binary').AsString);
          TTSserverFileName := StringReplace(TTSserverFileName, '/', PathDelim, [rfReplaceAll]);
          TTSserverFilePath := appdir + 'crispasr' + PathDelim + TTSserverFileName;
          if FileExists(TTSserverFilePath) then
          begin
            item.TTSbinary := TTSserverFilePath;
            if item.TTSusesGPU = 0 then ttsFallbackBinary := item.TTSbinary;
          end
          else
            item.TTSbinary := '';
          LlamaEngineComboBox.Items.AddObject(trim(LlamaQuery.FieldByName('name').AsString), item);
        end;
        LlamaQuery.Next;
      end;
      //Load default TTS models
      TTSmodelQuery.Open;
      defaultTTSmodelList.Clear;
      while not(TTSmodelQuery.EOF) do
      begin
        ttsModelItem := TTTSmodel.Create;
        ttsModelItem.Name := trim(TTSmodelQuery.FieldByName('name').AsString);
        ttsModelItem.Title := trim(TTSmodelQuery.FieldByName('title').AsString);
        ttsModelItem.Description := trim(TTSmodelQuery.FieldByName('description').AsString);
        ttsModelItem.FileName := trim(TTSmodelQuery.FieldByName('value').AsString);
        ttsModelItem.Comments := trim(TTSmodelQuery.FieldByName('comments').AsString);
        if (length(ttsModelItem.Name) >= 1) and (length(ttsModelItem.FileName) >= 1) then
          defaultTTSmodelList.Add(ttsModelItem)
        else
          FreeAndNil(ttsModelItem);
        TTSmodelQuery.Next;
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
      TTSmodelQuery.Close;
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
    //Load models
    LoadLLMfiles('CONVERSATIONAL');
    LoadLLMfiles('EMBEDDING');
    if length(ttsModeldir) >= 1 then
    begin
      LoadLLMfiles('TTS_MAIN');
      LoadLLMfiles('TTS_VOICE');
    end;
    //Load personalities
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
    //Final validation
    if (ModelComboBox.Items.Count < 1) and (EmbeddingModelComboBox.Items.Count < 1) then
      MessageDlg('Error', 'No language or embedding model not found! Unable to run LLM server!', mtError, [mbOK], 0);
  except
    on x: Exception do
    begin
      if not(x.ClassType = EAbort) then MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);
      if Assigned(TitleList) then FreeAndNil(TitleList);
      if Assigned(EmbeddingTitleList) then FreeAndNil(EmbeddingTitleList);
      if Assigned(TTStitleList) then FreeAndNil(TTStitleList);
      if Assigned(defaultTTSmodelList) then FreeAndNil(defaultTTSmodelList);
      Abort;
    end;
  end;
end;

//Add new LLM parameter
procedure TSettingsForm.AddButtonClick(Sender: TObject);
begin
  AddParameter(ParameterListEditor);
end;

//Remove LLM parameter
procedure TSettingsForm.RemoveButtonClick(Sender: TObject);
begin
  RemoveParameter(ParameterListEditor, TitleList);
end;

//Remove Embedding Parameter
procedure TSettingsForm.RemoveEmbeddingParameterButtonClick(Sender: TObject);
begin
  RemoveParameter(EmbeddingParameterListEditor, EmbeddingTitleList);
end;

//Show title for each TTS parameter
procedure TSettingsForm.TTSparameterListEditorMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
begin
  ShowHintForValueListCoords(TTSparameterListEditor, ttsTitleList, X, Y);
end;

//Load TTS device list
procedure TSettingsForm.TTSreloadDevicesButtonClick(Sender: TObject);
begin
  LoadDevices('TTS');
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
    if Assigned(TTStitleList) then FreeAndNil(TTStitleList);
    if Assigned(defaultTTSmodelList) then FreeAndNil(defaultTTSmodelList);
    ClearEngineComboBox;
    ClearLLMdeviceComboBox;
    ClearTTSdeviceComboBox;
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
    TTSmodelQuery.Close;
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
procedure TSettingsForm.ParameterListEditorMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
begin
  ShowHintForValueListCoords(ParameterListEditor, TitleList, X, Y);
end;

end.
