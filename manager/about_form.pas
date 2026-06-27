{ About form unit for displaying application information and version details. }
unit about_form;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  RichMemo, vinfo;

type
  { TAboutForm: dialog form that displays application title, version, copyright, and license information. }
  TAboutForm = class(TForm)
    AppTitle: TLabel;
    AppVersion: TLabel;
    AppCopyright: TLabel;
    OKbutton: TButton;
    LogoImage: TImage;
    LogoBevel: TBevel;
    LicenseMemo: TRichMemo;
    { Initializes the form with version information and loads the license file. }
    procedure FormCreate(Sender: TObject);
  end;

var
  { Global instance of the about dialog form. }
  AboutForm: TAboutForm;

implementation

{$R *.lfm}

{ TAboutForm }

//Load Version Information
procedure TAboutForm.FormCreate(Sender: TObject);
const copyright_symbol = '©';
var
  version_info: TVersionInfo;
  appdir: AnsiString;
  license_file: AnsiString;
  file_stream: TFileStream;
begin
  version_info := nil;
  file_stream := nil;
  try
    try
      version_info := TVersionInfo.Create;
      version_info.Load(HINSTANCE);
      AppTitle.Caption := trim(application.Title);
      AppVersion.Caption := 'Version: '+trim(version_info.FileVersion);
      AppCopyright.Caption := trim(copyright_symbol)+'2026 '+trim(version_info.CompanyName)+'. All rights reserved.';
      {$IFDEF MSWINDOWS}
      appdir := IncludeTrailingPathDelimiter(ExtractFilePath(application.ExeName));
      {$ELSE}
      appdir := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));
      {$ENDIF}
      license_file := appdir + 'doc' + PathDelim + 'license.rtf';
      if not(fileexists(license_file)) then
      begin
        MessageDlg(
          'The license file does not exist: ' + license_file + '!',
          mtError,
          [mbOk],
          0);
        exit;
      end;
      LicenseMemo.Clear;
      file_stream := TFileStream.Create(license_file, fmOpenRead or fmShareDenyNone);
      LicenseMemo.LoadRichText(file_stream);
    except
      on x: Exception do
        MessageDlg('Error', 'Internal error: ' + x.Message, mtError, [mbOK], 0);
    end;
  finally
    if Assigned(version_info) then FreeAndNil(version_info);
    if Assigned(file_stream) then FreeAndNil(file_stream);
  end;
end;

end.
