{ Generic progress form unit. }
unit progress_form;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  ComCtrls;

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
  private

  public

  end;

var
  { Global instance of the progress dialog form. }
  ProgressForm: TProgressForm;

implementation

{$R *.lfm}

end.
