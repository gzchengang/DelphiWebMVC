unit WebModule;

interface

uses
  System.SysUtils, System.Classes, Web.HTTPApp, Web.HTTPProd, Web.ReqMulti;

type
  TWM = class(TWebModule)
    WebFile: TWebFileDispatcher;
    procedure WebModuleBeforeDispatch(Sender: TObject; Request: TWebRequest; Response: TWebResponse; var Handled: Boolean);
  end;

var
  WebModuleClass: TComponentClass = TWM;

implementation

uses
  command;

{$R *.dfm}

procedure TWM.WebModuleBeforeDispatch(Sender: TObject; Request: TWebRequest; Response: TWebResponse; var Handled: Boolean);
begin
  try
    OpenRoule(Self, RouleMap, Handled);
  except
    on e: Exception do
    begin
      log(e.ToString);
      Response.Content := e.ToString;
      Response.SendResponse;
    end;

  end;
end;

end.
