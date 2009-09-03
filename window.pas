unit Window;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, mufasatypes
  {$IFDEF MSWINDOWS}
  ,windows  // For windows API
  {$ENDIF}
  , graphics,
  LCLType,
  LCLIntf // for ReleaseDC and such

  {$IFDEF LINUX}, xlib, x, xutil, ctypes{$ENDIF};

type

    { TMWindow }

    TMWindow = class(TObject)
            function ReturnData(xs, ys, width, height: Integer): PRGB32;
            procedure FreeReturnData;
            procedure GetDimensions(var W, H: Integer);
            function CopyClientToBitmap(xs, ys, xe, ye: integer): TBitmap;
            procedure ActivateClient;
            {$IFDEF LINUX}
            function SetTarget(XWindow: x.TWindow): integer; overload;
            {$ENDIF}

            {$IFDEF MSWINDOWS}
            function UpdateDrawBitmap:boolean;
            {$ENDIF}
            function SetTarget(Window: THandle; NewType: TTargetWindowMode): integer; overload;
            function SetTarget(ArrPtr: PRGB32): integer; overload;

            constructor Create(Client: TObject);
            destructor Destroy; override;
        public
              // Reference to client.
              Client: TObject;

              // Target Window Mode.
              TargetMode: TTargetWindowMode;


              {$IFDEF MSWINDOWS}
              //Target handle; HWND
              TargetHandle : Hwnd;
              DrawBmpDataPtr : PRGB32;

              //Works on linux as well, test it out
              TargetDC : HDC;
              DrawBitmap : TBitmap;
              {$ENDIF}

              {$IFDEF LINUX}
              // X Display
              XDisplay: PDisplay;

              // Connection Number
              XConnectionNumber: Integer;

              // X Window
              CurWindow: x.TWindow;

              // Desktop Window
              DesktopWindow: x.TWindow;

              // X Screen
              XScreen: PScreen;

              // X Screen Number
              XScreenNum: Integer;

              // The X Image pointer.
              XWindowImage: PXImage;

                 {$IFDEF M_MEMORY_DEBUG}
                  // XImageFreed should be True if there is currently no
                  // XImage loaded. If one is loaded, XImageFreed is true.

                  // If ReturnData is called while XImageFreed is false,
                  // we throw an exception.
                  // Same for FreeReturnData with XImageFreed true.
                  XImageFreed: Boolean;
                  {$ENDIF}

              {$ELSE}

              {$ENDIF}



    end;

implementation

uses
    Client, // For the Client Class
    windowutil, // For utilities such as XImageToRawImage
    GraphType // For TRawImage
    ;

constructor TMWindow.Create(Client: TObject);
begin
  inherited Create;
  Self.Client := Client;
  {$IFDEF MSWINDOWS}
  Self.DrawBitmap := TBitmap.Create;
  Self.TargetMode:= w_Window;
  Self.TargetHandle:= windows.GetDesktopWindow;
  Self.TargetDC:= GetWindowDC(Self.TargetHandle);
  Self.UpdateDrawBitmap;
  {$ENDIF}
  {$IFDEF LINUX}
  Self.TargetMode := w_XWindow;

  Self.XDisplay := XOpenDisplay(nil);
  if Self.XDisplay = nil then
  begin
    // throw Exception
  end;
  Self.XConnectionNumber:= ConnectionNumber(Self.XDisplay);
  Self.XScreen := XDefaultScreenOfDisplay(Self.XDisplay);
  Self.XScreenNum:= DefaultScreen(Self.XDisplay);

  // The Root Window is the Desktop. :-)
  Self.DesktopWindow:= RootWindow(Self.XDisplay, Self.XScreenNum);
  Self.CurWindow:= Self.DesktopWindow;

  {$ENDIF}

end;

destructor TMWindow.Destroy;
begin

  {$IFDEF LINUX}
  XCloseDisplay(Self.XDisplay);
  {$ENDIF}
  {$IFDEF MSWINDOWS}
  if TargetMode = w_Window then
    ReleaseDC(TargetHandle,TargetDC);
  DrawBitmap.Free;
  {$ENDIF}
  inherited;
end;

function TMWindow.ReturnData(xs, ys, width, height: Integer): PRGB32;
{$IFDEF LINUX}
var
   Old_Handler: TXErrorHandler;
{$ENDIF}
begin
  case Self.TargetMode of
    w_Window:
    begin
      {$IFDEF MSWINDOWS}
      BitBlt(Self.DrawBitmap.Canvas.Handle,0,0, width, height, Self.TargetDC, xs,ys, SRCCOPY);
      Result := Self.DrawBmpDataPtr;
      {$ENDIF}
    end;
    w_XWindow:
    begin
      {$IFDEF LINUX}
      { Should be this. }
      Old_Handler := XSetErrorHandler(@MufasaXErrorHandler);

      Self.XWindowImage := XGetImage(Self.XDisplay, Self.curWindow, xs, ys, width, height, AllPlanes, ZPixmap);
      if QWord(Self.XWindowImage) = 0 then
      begin
        Writeln('ReturnData: XGetImage Error. Dumping data now:');
        Writeln('xs, ys, width, height: ' + inttostr(xs) + ', '  + inttostr(ys) +
                ', ' + inttostr(width) + ', ' + inttostr(height));
        Result := nil;
        XSetErrorHandler(Old_Handler);
        Exit;
      end;
      WriteLn(IntToStr(Self.XWindowImage^.width) + ', ' + IntToStr(Self.XWindowImage^.height));
      Result := PRGB32(Self.XWindowImage^.data);

      XSetErrorHandler(Old_Handler);
      {$ELSE}
        WriteLn('Windows doesn''t support XImage');
      {$ENDIF}
    end;
  end;
end;

procedure TMWindow.FreeReturnData;
begin
  if Self.TargetMode <> w_XWindow then
  begin
    // throw exception.
    exit;
  end;
  {$IFDEF LINUX}
  if(QWord(Self.XWindowImage) <> 0) then      // 0, nil?
  begin
    XDestroyImage(Self.XWindowImage);
  end;
  {$ENDIF}
end;

function TMWindow.CopyClientToBitmap(xs, ys, xe, ye: integer): TBitmap;
var
   w,h : Integer;
   ww, hh: Integer;
   {$IFDEF LINUX}
   Old_Handler: TXErrorHandler;
   Img: PXImage;
   Raw: TRawImage;
   Bmp: TBitmap;
   {$ENDIF}

begin
  Self.GetDimensions(w, h);
  writeln(inttostr(xs) + ', ' + inttostr(ys) + ' : ' + inttostr(xe) + ', ' +
          inttostr(ye));
  ww := xe-xs;
  hh := ye-ys;

    case Self.TargetMode Of
       w_Window:
       begin
         {$IFDEF MSWINDOWS}
         if(xs < 0) or (ys < 0) or (xe > W) or (ye > H) then
           Writeln('pervet');
         Result := TBitmap.Create;
         Result.SetSize(ww+1,hh+1);
         BitBlt(result.canvas.handle,0,0,ww+1,hh+1,
                self.TargetDC,xs,ys, SRCCOPY);
         {$ENDIF}
       end;
       w_XWindow:
       begin
         {$IFDEF LINUX}
         Old_Handler := XSetErrorHandler(@MufasaXErrorHandler);

         if(xs < 0) or (ys < 0) or (xe > W) or (ye > H) then
         begin
           writeln('Faulty coordinates');
           XSetErrorHandler(Old_Handler);
           exit;
         end;

         Img := XGetImage(Self.XDisplay, Self.curWindow, xs, ys, ww, hh, AllPlanes, ZPixmap);
         XImageToRawImage(Img, Raw);

         Bmp := TBitmap.Create;
         Bmp.LoadFromRawImage(Raw, False);
         Result := Bmp;

         {
           If you want to use some internal Bitmap system, BitBlt to it here.
           Don't forget to free Bmp!
         }
         //lclintf.BitBlt(Bmps[bitmap].Canvas.Handle, 0, 0, ww + 1, hh + 1, Bmp.Canvas.Handle, xs, ys, SRCCOPY);
         //Bmp.Free;

         XDestroyImage(Img);
         XSetErrorHandler(Old_Handler);
         {$ELSE}
         writeln('Windows and tXWindow');
         {$ENDIF}
       end;
    end;
end;

procedure TMWindow.ActivateClient;
begin
  {$IFDEF MSWINDOWS}
  SetForegroundWindow(Self.TargetHandle);
  {$ENDIF}
  {$IFDEF LINUX}
  XSetInputFocus(Self.XDisplay,Self.CurWindow,RevertToParent,CurrentTime);
  {$ENDIF}
end;


{$IFDEF MSWINDOWS}  //Probably need one for Linux as well
function TMWindow.UpdateDrawBitmap :boolean;
var
  w,h : integer;
  BmpInfo : Windows.TBitmap;
begin
  GetDimensions(w,h);
  DrawBitmap.SetSize(w,h);
  GetObject(DrawBitmap.Handle, SizeOf(BmpInfo), @BmpInfo);
  DrawBmpDataPtr := BmpInfo.bmBits;
end;
{$ENDIF}

procedure TMWindow.GetDimensions(var W, H: Integer);
{$IFDEF LINUX}
var
   Attrib: TXWindowAttributes;
   newx,newy : integer;
   childwindow : x.TWindow;
   Old_Handler: TXErrorHandler;
{$ENDIF}
{$IFDEF MSWINDOWS}
var
  Rect : TRect;
{$ENDIF}
begin
  case TargetMode of
    w_Window:
    begin
      {$IFDEF MSWINDOWS}
      GetWindowRect(Self.TargetHandle, Rect);
      w:= Rect.Right - Rect.left + 1;
      h:= Rect.Bottom - Rect.Top  + 1;
      {$ENDIF}
    end;
    w_XWindow:
    begin
      {$IFDEF LINUX}
      Old_Handler := XSetErrorHandler(@MufasaXErrorHandler);
      if XGetWindowAttributes(Self.XDisplay, Self.CurWindow, @Attrib) <> 0 Then
      begin
        XTranslateCoordinates(Self.XDisplay, Self.CurWindow, Self.DesktopWindow, 0,0, @newx, @newy, @childwindow);
        W := Attrib.Width;
        H := Attrib.Height;
      end else
      begin
        W := -1;
        H := -1;
      end;
      XSetErrorHandler(Old_Handler);
      {$ELSE}
      WriteLn('You dummy! How are you going to use w_XWindow on non Linux systems?');
      {$ENDIF}
    end;
    w_ArrayPtr:
    begin
    end;
  end;
end;

{$IFDEF LINUX}
function TMWindow.SetTarget(XWindow: x.TWindow): integer; overload;
var
   Old_Handler: TXErrorHandler;
begin
  Old_Handler := XSetErrorHandler(@MufasaXErrorHandler);
  Self.CurWindow := XWindow;
  Self.TargetMode:= w_XWindow;
  XSetErrorHandler(Old_Handler);
end;
{$ENDIF}

function TMWindow.SetTarget(Window: THandle; NewType: TTargetWindowMode): integer; overload;
begin
  if NewType in [ w_XWindow, w_ArrayPtr ] then
  begin
    // throw exception
    Exit;
  end;
  case NewType of
    w_Window :
    begin;

      {$IFDEF MSWINDOWS}
      ReleaseDC(Self.TargetHandle,Self.TargetDC);
      Self.TargetHandle := Window;
      Self.TargetDC := GetWindowDC(Window);
      {$ENDIF}
    end;
  end;
  {$IFDEF MSWINDOWS}
  UpdateDrawBitmap;
  {$ENDIF}
end;

function TMWindow.SetTarget(ArrPtr: PRGB32): integer; overload;
begin

  Self.TargetMode:= w_ArrayPtr;
end;

end.

