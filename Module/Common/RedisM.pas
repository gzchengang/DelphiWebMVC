{*******************************************************}
{                                                       }
{       DelphiWebMVC                                    }
{                                                       }
{       ��Ȩ���� (C) 2019 ����ӭ(PRSoft)                }
{                                                       }
{*******************************************************}
unit RedisM;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, IdBaseComponent, Winapi.ActiveX,
  IdComponent, IdTCPConnection, IdTCPClient, IdGlobal, System.Win.ScktComp,
  superobject;

var
  Redis_IP: string;
  Redis_Port: Integer;
  Redis_PassWord: string;
  Redis_InitSize: integer;
  Redis_TimeOut: integer;
  Redis_ReadTimeOut: integer;

type
  TRedisM = class
  private
    TcpClient: TIdTCPClient;
    isConn: Boolean;
    function HexToStr(S: string): string;
    function StrToHex(S: string): string;
  public
    function setKeyText(key: string; value: string; timerout: Integer = 0): Boolean;
    function setKeyJSON(key: string; value: ISuperObject; timerout: Integer = 0): Boolean;
    function getKeyText(key: string): string;
    function getKeyJSON(key: string): ISuperObject;
    function delKey(key: string): Boolean;
    function tryconn(): Boolean;
    procedure freetcp;
    procedure setExpire(key: string; timerout: Integer);
    constructor Create();
    destructor Destroy; override;
  end;

implementation

uses
  LogUnit;

{ TRedis }

constructor TRedisM.Create();
begin
  TcpClient := nil;
  tryconn();
end;

function TRedisM.HexToStr(S: string): string;
var
  Stream: TMemoryStream;
  Value: TStringStream;
  Pos: Integer;
begin
  Result := '';
  if Length(S) > 0 then
  begin
    Stream := TMemoryStream.Create;
    Value := TStringStream.Create('');
    try
      Pos := Stream.Position;
      Stream.SetSize(Stream.Size + Length(S) div 2);
      HexToBin(PChar(S), PChar(Integer(Stream.Memory) + Stream.Position), Length(S) div 2);
      Stream.Position := Pos;
      Value.CopyFrom(Stream, Length(S) div 2);
      Result := Value.DataString;
    finally
      Stream.Free;
      Value.Free;
    end;
  end;
end;

function TRedisM.StrToHex(S: string): string;
var
  Stream: TMemoryStream;
  Value: TStringStream;
begin
  if Length(S) > 0 then
  begin
    Value := TStringStream.Create(S);
    try
      SetLength(Result, (Value.Size - Value.Position) * 2);
      if Length(Result) > 0 then
      begin
        Stream := TMemoryStream.Create;
        try
          Stream.CopyFrom(Value, Value.Size - Value.Position);
          Stream.Position := 0;
          BinToHex(PChar(Integer(Stream.Memory) + Stream.Position), PChar(Result), Stream.Size - Stream.Position);
        finally
          Stream.Free;
        end;
      end;
    finally
      Value.Free;
    end;
  end;
end;

function TRedisM.delKey(key: string): Boolean;
var
  s: string;
begin
  Result := True;
  if not isConn then
    if not tryconn then
    begin
      Result := false;
      exit;
    end;

  try

    tcpclient.Socket.WriteLn('del ' + key, IndyTextEncoding(IdTextEncodingType.encUTF8));
    s := tcpclient.Socket.ReadLn(IndyTextEncoding(IdTextEncodingType.encUTF8));
  except
    on e: Exception do
    begin
      Result := False;
      log(e.Message);
    end;

  end;

end;

destructor TRedisM.Destroy;
begin
  freetcp;
  inherited;
end;

procedure TRedisM.freetcp;
begin
  try
    TcpClient.Disconnect;
  finally
    TcpClient.Free;
  end;
end;

function TRedisM.setKeyText(key, value: string; timerout: Integer = 0): Boolean;
var
  s: string;
begin
  Result := true;
  if not isConn then
    if not tryconn then
    begin
      Result := false;
      exit;
    end;

  try

    tcpclient.Socket.WriteLn('set ' + key + ' ' + value, IndyTextEncoding(IdTextEncodingType.encUTF8));
    s := tcpclient.Socket.ReadLn(IndyTextEncoding(IdTextEncodingType.encUTF8));
    if timerout > 0 then
      setExpire(key, timerout * 60)
    else
      setExpire(key, Redis_TimeOut * 60)
  except
    on e: Exception do
    begin
      Result := false;
      log(e.Message);
    end;

  end;

end;

function TRedisM.setKeyJSON(key: string; value: ISuperObject; timerout: Integer): Boolean;
begin
  if value <> nil then
  begin
    Result := setKeyText(key, StrToHex(value.AsString), timerout);
  end;
end;

function TRedisM.getKeyJSON(key: string): ISuperObject;
var
  txt: string;
begin
  Result := nil;
  if key.Trim <> '' then
  begin
    txt := getKeyText(key);
    if txt.Trim <> '' then
    begin
      Result := SO(HexToStr(txt));
    end
    else
      Result := so('{}');
  end;
end;

function TRedisM.getKeyText(key: string): string;
var
  s: string;
begin
  Result := '';
  if not isConn then
    if not tryconn then
    begin
      Result := '';
      exit;
    end;

  try
    with TcpClient do
    begin

      Socket.WriteLn('get ' + key, IndyTextEncoding(IdTextEncodingType.encUTF8));
      s := Socket.ReadLn(IndyTextEncoding(IdTextEncodingType.encUTF8));
      s := s.Replace('$', '');
      if StrToInt(s) > 0 then
      begin
        s := Socket.ReadLn(IndyTextEncoding(IdTextEncodingType.encUTF8));
      end
      else
      begin
        s := '';
      end;

      Result := s;
    end;
  except
    on e: Exception do
    begin
      log(e.Message);
    end;
  end;

end;

function TRedisM.tryconn: Boolean;
var
  s: string;
begin
  if TcpClient = nil then
    tcpclient := TIdTCPClient.Create(nil);
  try

    try
      tcpclient.Host := Redis_IP;
      tcpclient.Port := Redis_Port;
      TcpClient.ReadTimeout := Redis_ReadTimeOut * 1000;
      tcpclient.Connect;
      TcpClient.Socket.RecvBufferSize := 100 * 1024;
      TcpClient.Socket.SendBufferSize := 100 * 1024;

      with tcpclient do
      begin
        if Connected then
        begin
          if Redis_PassWord <> '' then
          begin
            Socket.WriteLn('AUTH ' + Redis_PassWord, IndyTextEncoding(IdTextEncodingType.encUTF8));
            s := Socket.ReadLn(IndyTextEncoding(IdTextEncodingType.encUTF8));
            if s = '+OK' then
            begin
              isConn := true;
            end
            else
            begin
              isConn := true;
              log('Redis�����¼ʧ�������¼����');
            end;
          end
          else
          begin
            isConn := true;
          end;
        end
        else
        begin
          isConn := false;
          log('Redis��������ʧ��');
        end;
      end;

    except
      on e: Exception do
      begin
        isConn := false;
        log(e.Message);
      end;
    end;
  finally
    result := isConn;
  end;
end;

procedure TRedisM.setExpire(key: string; timerout: Integer);
var
  s: string;
begin
  if not isConn then
    if not tryconn then
      exit;
  try
    with tcpclient do
    begin
      Socket.WriteLn('expire ' + key + ' ' + inttostr(timerout), IndyTextEncoding(IdTextEncodingType.encUTF8));
      s := Socket.ReadLn(IndyTextEncoding(IdTextEncodingType.encUTF8));
    end;
  except
    on e: Exception do
    begin
      log(e.Message);
    end;

  end;
end;

end.

