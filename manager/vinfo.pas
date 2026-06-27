{ Version info unit for retrieving application version information from executable resources. }
unit vinfo;

{$mode objfpc}

interface

uses
  Classes, SysUtils, resource, versiontypes, versionresource;

type

  { TVersionInfo: class for retrieving application version information from executable resources. }
  TVersionInfo = class
  private
    { Internal version resource handle. }
    FVersResource: TVersionResource;
    { Gets the fixed version info structure. }
    function GetFixedInfo: TVersionFixedInfo;
    { Gets the string file info structure. }
    function GetStringFileInfo: TVersionStringFileInfo;
    { Gets the variable file info structure. }
    function GetVarFileInfo: TVersionVarFileInfo;
    { Searches for a specific string value in the version info. }
    function SearchValue(const aString : string) : string;
  public
    { Creates a new TVersionInfo instance and loads the version resource. }
    constructor Create;
    { Destroys the TVersionInfo instance and frees the version resource. }
    destructor Destroy; override;
    { Returns the company name from version information. }
    function CompanyName  : string;
    { Returns the internal name from version information. }
    function InternalName : string;
    { Returns the file version from version information. }
    function FileVersion  : string;
    { Returns the product name from version information. }
    function ProductName  : string;
    { Loads version information from the specified module instance. }
    procedure Load(Instance: THandle);
    { Fixed version information properties (file version, product version, etc.). }
    property FixedInfo: TVersionFixedInfo read GetFixedInfo;
    { String file information table with localized strings. }
    property StringFileInfo: TVersionStringFileInfo read GetStringFileInfo;
    { Variable file information for translation tables. }
    property VarFileInfo: TVersionVarFileInfo read GetVarFileInfo;
  end;

implementation

{ TVersionInfo }

function TVersionInfo.GetFixedInfo: TVersionFixedInfo;
begin
  Result := FVersResource.FixedInfo;
end;

function TVersionInfo.GetStringFileInfo: TVersionStringFileInfo;
begin
  Result := FVersResource.StringFileInfo;
end;

function TVersionInfo.GetVarFileInfo: TVersionVarFileInfo;
begin
  Result := FVersResource.VarFileInfo;
end;

function TVersionInfo.SearchValue(const aString: string): string;
var
  s : TVersionStringTable;
  i,j : integer;
begin
  result := '';
  for i:=0 to StringFileInfo.Count-1 do
  begin
    s := StringFileInfo.Items[i];
    for j:=0 to s.Count-1 do
    begin
      if s.Keys[j] = aString then
      begin
         result := s.Values[j];
         break;
      end;
    end;
  end;
end;

function TVersionInfo.CompanyName: string;
begin
   Result := SearchValue('CompanyName');
end;

function TVersionInfo.InternalName: string;
begin
   Result := SearchValue('InternalName');
end;

function TVersionInfo.FileVersion: string;
begin
   Result := SearchValue('FileVersion');
end;

function TVersionInfo.ProductName: string;
begin
   Result := SearchValue('ProductName');
end;

constructor TVersionInfo.Create;
begin
  inherited Create;
  FVersResource := TVersionResource.Create;
  Load(HInstance);
end;

destructor TVersionInfo.Destroy;
begin
  FVersResource.Free;
  inherited Destroy;
end;

procedure TVersionInfo.Load(Instance: THandle);
var Stream: TResourceStream;
begin
  Stream := TResourceStream.CreateFromID(Instance, 1, PChar(RT_VERSION));
  try
    FVersResource.SetCustomRawDataStream(Stream);
    // access some property to load from the stream
    FVersResource.FixedInfo;
    // clear the stream
    FVersResource.SetCustomRawDataStream(nil);
  finally
    Stream.Free;
  end;
end;

end.

