{ Modal editor form unit for editing system messages and prompts. }
unit system_message_editor;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, Menus, ExtCtrls,
  StdCtrls, SynEdit;

type

  { TSystemMessageEditor: modal dialog form for editing multi-line system messages. }
  TSystemMessageEditor = class(TForm)
    { Divider bevel separating the editor area from the action buttons. }
    BottomBevel: TBevel;
    { Button that closes the dialog and discards changes. }
    CancelButton: TButton;
    { Multi-line text memo containing the system message content. }
    Content: TMemo;
    { Top-level main menu bar of the editor form. }
    MainMenu: TMainMenu;
    { Top-level Edit menu containing clipboard, undo, and selection actions. }
    EditMenu: TMenuItem;
    { Main menu item for cutting selected text to the clipboard. }
    CutMenu: TMenuItem;
    { Main menu item for copying selected text to the clipboard. }
    CopyMenu: TMenuItem;
    { Context menu item for cutting selected text to the clipboard. }
    CutPopupMenu: TMenuItem;
    { Context menu item for copying selected text to the clipboard. }
    CopyPopupMenu: TMenuItem;
    { Context menu item for selecting all text in the editor. }
    SelectAllPopupMenu: TMenuItem;
    { Visual separator in the editor context menu. }
    Separator3: TMenuItem;
    { Context menu item for pasting text from the clipboard. }
    PastePopupMenu: TMenuItem;
    { Right-click context menu for the text editor. }
    EditorPopupMenu: TPopupMenu;
    { Main menu item for selecting all text in the editor. }
    SelectAllMenu: TMenuItem;
    { Visual separator before the Select All item in the Edit menu. }
    Separator2: TMenuItem;
    { Main menu item for pasting text from the clipboard. }
    PasteMenu: TMenuItem;
    { Visual separator between Undo and clipboard items in the Edit menu. }
    Separator1: TMenuItem;
    { Main menu item for undoing the last editing action. }
    UndoMenu: TMenuItem;
    { Button that confirms changes and closes the dialog. }
    OKbutton: TButton;
    { Copies selected text from Content to the clipboard when CopyMenu is clicked. }
    procedure CopyMenuClick(Sender: TObject);
    { Copies selected text from Content to the clipboard when CopyPopupMenu is clicked. }
    procedure CopyPopupMenuClick(Sender: TObject);
    { Cuts selected text from Content to the clipboard when CutMenu is clicked. }
    procedure CutMenuClick(Sender: TObject);
    { Cuts selected text from Content to the clipboard when CutPopupMenu is clicked. }
    procedure CutPopupMenuClick(Sender: TObject);
    { Pastes clipboard content into Content when PasteMenu is clicked. }
    procedure PasteMenuClick(Sender: TObject);
    { Pastes clipboard content into Content when PastePopupMenu is clicked. }
    procedure PastePopupMenuClick(Sender: TObject);
    { Selects all text inside Content when SelectAllMenu is clicked. }
    procedure SelectAllMenuClick(Sender: TObject);
    { Selects all text inside Content when SelectAllPopupMenu is clicked. }
    procedure SelectAllPopupMenuClick(Sender: TObject);
    { Reverts the last change in Content when UndoMenu is clicked. }
    procedure UndoMenuClick(Sender: TObject);
  end;

var
  { Global instance of the system message editor dialog form. }
  SystemMessageEditor: TSystemMessageEditor;

implementation

{$R *.lfm}

{ TSystemMessageEditor }

// Undo last action in Content if available; ignore exceptions safely.
procedure TSystemMessageEditor.UndoMenuClick(Sender: TObject);
begin
  try
    if not(Content.CanUndo) then Exit;
    Content.Undo;
  except
    // Silent skip
  end;
end;

// Cut selected text from Content to the clipboard via main menu.
procedure TSystemMessageEditor.CutMenuClick(Sender: TObject);
begin
  Content.CutToClipboard;
end;

// Cut selected text from Content to the clipboard via context menu.
procedure TSystemMessageEditor.CutPopupMenuClick(Sender: TObject);
begin
  Content.CutToClipboard;
end;

// Paste clipboard text into Content via main menu.
procedure TSystemMessageEditor.PasteMenuClick(Sender: TObject);
begin
  Content.PasteFromClipboard;
end;

// Paste clipboard text into Content via context menu.
procedure TSystemMessageEditor.PastePopupMenuClick(Sender: TObject);
begin
  Content.PasteFromClipboard;
end;

// Select all text in Content via main menu.
procedure TSystemMessageEditor.SelectAllMenuClick(Sender: TObject);
begin
  Content.SelectAll;
end;

// Select all text in Content via context menu.
procedure TSystemMessageEditor.SelectAllPopupMenuClick(Sender: TObject);
begin
  Content.SelectAll;
end;

// Copy selected text from Content to the clipboard via main menu.
procedure TSystemMessageEditor.CopyMenuClick(Sender: TObject);
begin
  Content.CopyToClipboard;
end;

// Copy selected text from Content to the clipboard via context menu.
procedure TSystemMessageEditor.CopyPopupMenuClick(Sender: TObject);
begin
  Content.CopyToClipboard;
end;

end.
