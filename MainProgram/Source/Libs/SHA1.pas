{-------------------------------------------------------------------------------

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at http://mozilla.org/MPL/2.0/.

-------------------------------------------------------------------------------}
{===============================================================================

  SHA1 Hash Calculation

  ©František Milt 2017-07-18

  Version 1.1.5

  Dependencies:
    AuxTypes    - github.com/ncs-sniper/Lib.AuxTypes
    StrRect     - github.com/ncs-sniper/Lib.StrRect
    BitOps      - github.com/ncs-sniper/Lib.BitOps
  * SimpleCPUID - github.com/ncs-sniper/Lib.SimpleCPUID

  SimpleCPUID might not be needed, see BitOps library for details.

===============================================================================}
unit SHA1;

{$DEFINE LargeBuffer}

{$IFDEF ENDIAN_BIG}
  {$MESSAGE FATAL 'Big-endian system not supported'}
{$ENDIF}

{$IFOPT Q+}
  {$DEFINE OverflowCheck}
{$ENDIF}

{$IFDEF FPC}
  {$MODE ObjFPC}{$H+}
  {$DEFINE FPC_DisableWarns}
  {$MACRO ON}
{$ENDIF}

interface

uses
  Classes, AuxTypes;

type
  TSHA1Hash = record
    PartA:  UInt32;
    PartB:  UInt32;
    PartC:  UInt32;
    PartD:  UInt32;
    PartE:  UInt32;
  end;
  PSHA1Hash = ^TSHA1Hash;

const
  InitialSHA1: TSHA1Hash = (
    PartA:  $67452301;
    PartB:  $EFCDAB89;
    PartC:  $98BADCFE;
    PartD:  $10325476;
    PartE:  $C3D2E1F0);

  ZeroSHA1: TSHA1Hash = (PartA: 0; PartB: 0; PartC: 0; PartD: 0; PartE: 0);

Function SHA1toStr(Hash: TSHA1Hash): String;
Function StrToSHA1(Str: String): TSHA1Hash;
Function TryStrToSHA1(const Str: String; out Hash: TSHA1Hash): Boolean;
Function StrToSHA1Def(const Str: String; Default: TSHA1Hash): TSHA1Hash;
Function SameSHA1(A,B: TSHA1Hash): Boolean;
Function BinaryCorrectSHA1(Hash: TSHA1Hash): TSHA1Hash;

procedure BufferSHA1(var Hash: TSHA1Hash; const Buffer; Size: TMemSize); overload;
Function LastBufferSHA1(Hash: TSHA1Hash; const Buffer; Size: TMemSize; MessageLength: UInt64): TSHA1Hash; overload;
Function LastBufferSHA1(Hash: TSHA1Hash; const Buffer; Size: TMemSize): TSHA1Hash; overload;

Function BufferSHA1(const Buffer; Size: TMemSize): TSHA1Hash; overload;

Function AnsiStringSHA1(const Str: AnsiString): TSHA1Hash;
Function WideStringSHA1(const Str: WideString): TSHA1Hash;
Function StringSHA1(const Str: String): TSHA1Hash;

Function StreamSHA1(Stream: TStream; Count: Int64 = -1): TSHA1Hash;
Function FileSHA1(const FileName: String): TSHA1Hash;

//------------------------------------------------------------------------------

type
  TSHA1Context = type Pointer;

Function SHA1_Init: TSHA1Context;
procedure SHA1_Update(Context: TSHA1Context; const Buffer; Size: TMemSize);
Function SHA1_Final(var Context: TSHA1Context; const Buffer; Size: TMemSize): TSHA1Hash; overload;
Function SHA1_Final(var Context: TSHA1Context): TSHA1Hash; overload;
Function SHA1_Hash(const Buffer; Size: TMemSize): TSHA1Hash;


implementation

uses
  SysUtils, Math, BitOps, StrRect;

{$IFDEF FPC_DisableWarns}
  {$DEFINE FPCDWM}
  {$DEFINE W4055:={$WARN 4055 OFF}} // Conversion between ordinals and pointers is not portable
  {$DEFINE W4056:={$WARN 4056 OFF}} // Conversion between ordinals and pointers is not portable
  {$PUSH}{$WARN 2005 OFF} // Comment level $1 found
  {$IF Defined(FPC) and (FPC_FULLVERSION >= 30000)}
    {$DEFINE W5092:={$WARN 5092 OFF}} // Variable "$1" of a managed type does not seem to be initialized
  {$ELSE}
    {$DEFINE W5092:=}
  {$IFEND}
  {$POP}
{$ENDIF}

const
  BlockSize       = 64;                           // 512 bits
{$IFDEF LargeBuffers}
  BlocksPerBuffer = 16384;                        // 1MiB BufferSize
{$ELSE}
  BlocksPerBuffer = 64;                           // 4KiB BufferSize
{$ENDIF}
  BufferSize      = BlocksPerBuffer * BlockSize;  // size of read buffer

  RoundConsts: array[0..3] of UInt32 = ($5A827999, $6ED9EBA1, $8F1BBCDC, $CA62C1D6);

type
  TBlockBuffer = array[0..BlockSize - 1] of UInt8;
  PBlockBuffer = ^TBlockBuffer;

  TSHA1Context_Internal = record
    MessageHash:    TSHA1Hash;
    MessageLength:  UInt64;
    TransferSize:   UInt32;
    TransferBuffer: TBlockBuffer;
  end;
  PSHA1Context_Internal = ^TSHA1Context_Internal;

//==============================================================================

Function BlockHash(Hash: TSHA1Hash; const Block): TSHA1Hash;
var
  i:              Integer;
  Temp:           UInt32;
  FuncResult:     UInt32;
  RoundConstant:  UInt32;
  State:          array[0..79] of UInt32;
  BlockWords:     array[0..15] of UInt32 absolute Block;
begin
Result := Hash;
For i := 0 to 15 do State[i] := EndianSwap(BlockWords[i]);
For i := 16 to 79 do State[i] := ROL(State[i - 3] xor State[i - 8] xor State[i - 14] xor State[i - 16],1);
For i := 0 to 79 do
  begin
    case i of
       0..19: begin
                FuncResult := (Hash.PartB and Hash.PartC) or ((not Hash.PartB) and Hash.PartD);
                RoundConstant := RoundConsts[0];
              end;
      20..39: begin
                FuncResult := Hash.PartB xor Hash.PartC xor Hash.PartD;
                RoundConstant := RoundConsts[1];
              end;
      40..59: begin
                FuncResult := (Hash.PartB and Hash.PartC) or (Hash.PartB and Hash.PartD) or (Hash.PartC and Hash.PartD);
                RoundConstant := RoundConsts[2];
              end;
    else
     {60..79:}  FuncResult := Hash.PartB xor Hash.PartC xor Hash.PartD;
                RoundConstant := RoundConsts[3];
    end;
    {$IFDEF OverflowCheck}{$Q-}{$ENDIF}
    Temp := UInt32(ROL(Hash.PartA,5) + FuncResult + Hash.PartE + RoundConstant + State[i]);
    {$IFDEF OverflowCheck}{$Q+}{$ENDIF}
    Hash.PartE := Hash.PartD;
    Hash.PartD := Hash.PartC;
    Hash.PartC := ROL(Hash.PartB,30);
    Hash.PartB := Hash.PartA;
    Hash.PartA := Temp;
  end;
{$IFDEF OverflowCheck}{$Q-}{$ENDIF}
Result.PartA := UInt32(Result.PartA + Hash.PartA);
Result.PartB := UInt32(Result.PartB + Hash.PartB);
Result.PartC := UInt32(Result.PartC + Hash.PartC);
Result.PartD := UInt32(Result.PartD + Hash.PartD);
Result.PartE := UInt32(Result.PartE + Hash.PartE);
{$IFDEF OverflowCheck}{$Q+}{$ENDIF}
end;

//==============================================================================

Function SHA1toStr(Hash: TSHA1Hash): String;
begin
Result := IntToHex(Hash.PartA,8) + IntToHex(Hash.PartB,8) +
          IntToHex(Hash.PartC,8) + IntToHex(Hash.PartD,8) +
          IntToHex(Hash.PartE,8);
end;

//------------------------------------------------------------------------------

{$IFDEF FPCDWM}{$PUSH}W5092{$ENDIF}
Function StrToSHA1(Str: String): TSHA1Hash;
begin
If Length(Str) < 40 then
  Str := StringOfChar('0',40 - Length(Str)) + Str
else
  If Length(Str) > 40 then
    Str := Copy(Str,Length(Str) - 39,40);
Result.PartA := StrToInt('$' + Copy(Str,1,8));
Result.PartB := StrToInt('$' + Copy(Str,9,8));
Result.PartC := StrToInt('$' + Copy(Str,17,8));
Result.PartD := StrToInt('$' + Copy(Str,25,8));
Result.PartE := StrToInt('$' + Copy(Str,33,8));
end;
{$IFDEF FPCDWM}{$POP}{$ENDIF}

//------------------------------------------------------------------------------

Function TryStrToSHA1(const Str: String; out Hash: TSHA1Hash): Boolean;
begin
try
  Hash := StrToSHA1(Str);
  Result := True;
except
  Result := False;
end;
end;

//------------------------------------------------------------------------------

Function StrToSHA1Def(const Str: String; Default: TSHA1Hash): TSHA1Hash;
begin
If not TryStrToSHA1(Str,Result) then
  Result := Default;
end;

//------------------------------------------------------------------------------

Function SameSHA1(A,B: TSHA1Hash): Boolean;
begin
Result := (A.PartA = B.PartA) and (A.PartB = B.PartB) and
          (A.PartC = B.PartC) and (A.PartD = B.PartD) and
          (A.PartE = B.PartE);
end;

//------------------------------------------------------------------------------

Function BinaryCorrectSHA1(Hash: TSHA1Hash): TSHA1Hash;
begin
Result.PartA := EndianSwap(Hash.PartA);
Result.PartB := EndianSwap(Hash.PartB);
Result.PartC := EndianSwap(Hash.PartC);
Result.PartD := EndianSwap(Hash.PartD);
Result.PartE := EndianSwap(Hash.PartE);
end;

//==============================================================================

procedure BufferSHA1(var Hash: TSHA1Hash; const Buffer; Size: TMemSize);
var
  i:    TMemSize;
  Buff: PBlockBuffer;
begin
If Size > 0 then
  begin
    If (Size mod BlockSize) = 0 then
      begin
        Buff := @Buffer;
        For i := 0 to Pred(Size div BlockSize) do
          begin
            Hash := BlockHash(Hash,Buff^);
            Inc(Buff);
          end;
      end
    else raise Exception.CreateFmt('BufferSHA1: Buffer size is not divisible by %d.',[BlockSize]);
  end;
end;

//------------------------------------------------------------------------------

Function LastBufferSHA1(Hash: TSHA1Hash; const Buffer; Size: TMemSize; MessageLength: UInt64): TSHA1Hash;
var
  FullBlocks:     TMemSize;
  LastBlockSize:  TMemSize;
  HelpBlocks:     TMemSize;
  HelpBlocksBuff: Pointer;
begin
Result := Hash;
FullBlocks := Size div BlockSize;
If FullBlocks > 0 then BufferSHA1(Result,Buffer,FullBlocks * BlockSize);
LastBlockSize := Size - (UInt64(FullBlocks) * BlockSize);
HelpBlocks := Ceil((LastBlockSize + SizeOf(UInt64) + 1) / BlockSize);
HelpBlocksBuff := AllocMem(HelpBlocks * BlockSize);
try
{$IFDEF FPCDWM}{$PUSH}W4055 W4056{$ENDIF}
  Move(Pointer(PtrUInt(@Buffer) + (FullBlocks * BlockSize))^,HelpBlocksBuff^,LastBlockSize);
  PUInt8(PtrUInt(HelpBlocksBuff) + LastBlockSize)^ := $80;
  PUInt64(PtrUInt(HelpBlocksBuff) + (UInt64(HelpBlocks) * BlockSize) - SizeOf(UInt64))^ := EndianSwap(MessageLength);
{$IFDEF FPCDWM}{$POP}{$ENDIF}
  BufferSHA1(Result,HelpBlocksBuff^,HelpBlocks * BlockSize);
finally
  FreeMem(HelpBlocksBuff,HelpBlocks * BlockSize);
end;
end;

//------------------------------------------------------------------------------

Function LastBufferSHA1(Hash: TSHA1Hash; const Buffer; Size: TMemSize): TSHA1Hash;
begin
Result := LastBufferSHA1(Hash,Buffer,Size,UInt64(Size) shl 3);
end;

//==============================================================================

Function BufferSHA1(const Buffer; Size: TMemSize): TSHA1Hash;
begin
Result := LastBufferSHA1(InitialSHA1,Buffer,Size);
end;

//==============================================================================

Function AnsiStringSHA1(const Str: AnsiString): TSHA1Hash;
begin
Result := BufferSHA1(PAnsiChar(Str)^,Length(Str) * SizeOf(AnsiChar));
end;

//------------------------------------------------------------------------------

Function WideStringSHA1(const Str: WideString): TSHA1Hash;
begin
Result := BufferSHA1(PWideChar(Str)^,Length(Str) * SizeOf(WideChar));
end;

//------------------------------------------------------------------------------

Function StringSHA1(const Str: String): TSHA1Hash;
begin
Result := BufferSHA1(PChar(Str)^,Length(Str) * SizeOf(Char));
end;

//==============================================================================

Function StreamSHA1(Stream: TStream; Count: Int64 = -1): TSHA1Hash;
var
  Buffer:         Pointer;
  BytesRead:      Integer;
  MessageLength:  UInt64;
begin
If Assigned(Stream) then
  begin
    If Count = 0 then
      Count := Stream.Size - Stream.Position;
    If Count < 0 then
      begin
        Stream.Position := 0;
        Count := Stream.Size;
      end;
    MessageLength := UInt64(Count shl 3);
    GetMem(Buffer,BufferSize);
    try
      Result := InitialSHA1;
      repeat
        BytesRead := Stream.Read(Buffer^,Min(BufferSize,Count));
        If BytesRead < BufferSize then
          Result := LastBufferSHA1(Result,Buffer^,BytesRead,MessageLength)
        else
          BufferSHA1(Result,Buffer^,BytesRead);
        Dec(Count,BytesRead);
      until BytesRead < BufferSize;
    finally
      FreeMem(Buffer,BufferSize);
    end;
  end
else raise Exception.Create('StreamSHA1: Stream is not assigned.');
end;

//------------------------------------------------------------------------------

Function FileSHA1(const FileName: String): TSHA1Hash;
var
  FileStream: TFileStream;
begin
FileStream := TFileStream.Create(StrToRTL(FileName), fmOpenRead or fmShareDenyWrite);
try
  Result := StreamSHA1(FileStream);
finally
  FileStream.Free;
end;
end;

//==============================================================================

Function SHA1_Init: TSHA1Context;
begin
Result := AllocMem(SizeOf(TSHA1Context_Internal));
with PSHA1Context_Internal(Result)^ do
  begin
    MessageHash := InitialSHA1;
    MessageLength := 0;
    TransferSize := 0;
  end;
end;

//------------------------------------------------------------------------------

procedure SHA1_Update(Context: TSHA1Context; const Buffer; Size: TMemSize);
var
  FullBlocks:     TMemSize;
  RemainingSize:  TMemSize;
begin
with PSHA1Context_Internal(Context)^ do
  begin
    If TransferSize > 0 then
      begin
        If Size >= (BlockSize - TransferSize) then
          begin
            Inc(MessageLength,(BlockSize - TransferSize) shl 3);
            Move(Buffer,TransferBuffer[TransferSize],BlockSize - TransferSize);
            BufferSHA1(MessageHash,TransferBuffer,BlockSize);
            RemainingSize := Size - (BlockSize - TransferSize);
            TransferSize := 0;
          {$IFDEF FPCDWM}{$PUSH}W4055 W4056{$ENDIF}
            SHA1_Update(Context,Pointer(PtrUInt(@Buffer) + (Size - RemainingSize))^,RemainingSize);
          {$IFDEF FPCDWM}{$POP}{$ENDIF}
          end
        else
          begin
            Inc(MessageLength,Size shl 3);
            Move(Buffer,TransferBuffer[TransferSize],Size);
            Inc(TransferSize,Size);
          end;  
      end
    else
      begin
        Inc(MessageLength,Size shl 3);
        FullBlocks := Size div BlockSize;
        BufferSHA1(MessageHash,Buffer,FullBlocks * BlockSize);
        If (FullBlocks * BlockSize) < Size then
          begin
            TransferSize := Size - (UInt64(FullBlocks) * BlockSize);
          {$IFDEF FPCDWM}{$PUSH}W4055 W4056{$ENDIF}
            Move(Pointer(PtrUInt(@Buffer) + (Size - TransferSize))^,TransferBuffer,TransferSize);
          {$IFDEF FPCDWM}{$POP}{$ENDIF}
          end;
      end;
  end;
end;

//------------------------------------------------------------------------------

Function SHA1_Final(var Context: TSHA1Context; const Buffer; Size: TMemSize): TSHA1Hash;
begin
SHA1_Update(Context,Buffer,Size);
Result := SHA1_Final(Context);
end;

//------------------------------------------------------------------------------

Function SHA1_Final(var Context: TSHA1Context): TSHA1Hash;
begin
with PSHA1Context_Internal(Context)^ do
  Result := LastBufferSHA1(MessageHash,TransferBuffer,TransferSize,MessageLength);
FreeMem(Context,SizeOf(TSHA1Context_Internal));
Context := nil;
end;

//------------------------------------------------------------------------------

Function SHA1_Hash(const Buffer; Size: TMemSize): TSHA1Hash;
begin
Result := LastBufferSHA1(InitialSHA1,Buffer,Size);
end;

end.
