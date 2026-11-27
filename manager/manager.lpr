program manager;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  {$IFDEF HASAMIGA}
  athreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, main_form, settings_form, about_form, progress_form, 
system_message_editor
  { you can add units after this };

{$R *.res}

begin
  RequireDerivedFormResource:=True;
  Application.Title:='Service Manager';
  {$IF DECLARED(GlobalSkipIfNoLeaks)}
  GlobalSkipIfNoLeaks := True;
  {$ENDIF}
  Application.Scaled:=True;
  {$PUSH}{$WARN 5044 OFF}
  Application.MainFormOnTaskbar:=True;
  {$POP}
  Application.Initialize;
  Application.ShowMainForm := False;
  Application.CreateForm(TMainForm, MainForm);
  Application.CreateForm(TSettingsForm, SettingsForm);
  Application.CreateForm(TAboutForm, AboutForm);
  Application.CreateForm(TProgressForm, ProgressForm);
  Application.CreateForm(TSystemMessageEditor, SystemMessageEditor);
  Application.Run;
end.

