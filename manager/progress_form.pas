{ Generic progress form unit. }
unit progress_form;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  ComCtrls, math;

type

  { TProgressForm: modal progress dialog shown during long-running processes. }
  TProgressForm = class(TForm)
    { Title label displayed at the top of the progress dialog. }
    ProcessingTitleLabel: TLabel;
    { Bevel border surrounding the progress dialog contents. }
    MainBevel: TBevel;
    { Description label shown below the title. }
    ProcessingDescriptionLabel: TLabel;
    { Main progress bar that advances during the process. }
    MainProgressBar: TProgressBar;
    { Timer driving the indeterminate progress animation. }
    ProgressTimer: TTimer;
    { Handles progress form creation and initialization. }
    procedure FormCreate(Sender: TObject);
    { Handles timer ticks to animate the progress bar. }
    procedure ProgressTimerTimer(Sender: TObject);
  protected

  public
    { Animation direction for the pulsing progress bar. }
    FProgressDirection: Integer;
  end;

var
  { Global instance of the progress dialog form. }
  ProgressForm: TProgressForm;

implementation

{$R *.lfm}

{ TProgressForm }

//Handles timer ticks to animate the progress bar
procedure TProgressForm.ProgressTimerTimer(Sender: TObject);
const Step = 5;
begin
  try
    if FProgressDirection = 0 then FProgressDirection := 1;
    if FProgressDirection > 0 then
    begin
      MainProgressBar.Position := Min(MainProgressBar.Position + Step, MainProgressBar.Max);
      if MainProgressBar.Position >= MainProgressBar.Max then FProgressDirection := -1;
    end
    else
    begin
      MainProgressBar.Position := Max(MainProgressBar.Position - Step, MainProgressBar.Min);
      if MainProgressBar.Position <= MainProgressBar.Min then FProgressDirection := 1;
    end;
  except
    // Slient skip
  end;
end;

// Handles progress form creation and initialization
procedure TProgressForm.FormCreate(Sender: TObject);
begin
  FProgressDirection := 0;
end;

end.
