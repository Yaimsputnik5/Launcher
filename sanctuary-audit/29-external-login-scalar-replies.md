# Exact external-login scalar replies

This note records two byte-opcode login replies that were previously rejected by
the Swift decoder. Evidence comes from the authoritative Sanctuary source at
commit `f5240b7554f2a80d6b815cb7ead7ffee12499565`; no account credential was
provided, requested, captured, or stored.

## Source evidence

| C# source | Wire layout | Notes |
|---|---|---|
| `src/Sanctuary.Packet/ExternalLogin/ForceDisconnect.cs` | `byte OpCode = 4`, `int Reason` | `Serialize()` writes the opcode with `writer.Write(OpCode)`, then `writer.Write(Reason)`. |
| `src/Sanctuary.Packet/ExternalLogin/CharacterCreateReply.cs` | `byte OpCode = 6`, `int Result`, `ulong Guid` | `Serialize()` writes `Result` before `Guid`. Source comments identify result 1 as success and 2–7 as named failures; unknown values remain integers. |
| `src/Sanctuary.Login/LoginConnection.cs:174` | `ForceDisconnect(reason)` sends the reply then calls `Disconnect()` | This is a server-initiated terminal login event, not a client request. |

`Sanctuary.Packet.Common/Extensions/PacketReaderExtensions.cs` maps numeric
opcode 4 to `ForceDisconnect`, confirming the byte-opcode family.

## Swift changes

- `LoginOpcode.forceDisconnect = 4` and `LoginOpcode.characterCreateReply = 6`
  now decode to `LoginProtocol.ForceDisconnect` and
  `LoginProtocol.CharacterCreateReply` instead of throwing
  `unsupportedOpcode`.
- `LoginPacket.decodeAny` exposes both as `LoginDecodedMessage` cases.
- `LoginUDPSession.handleApplication` converts `ForceDisconnect` into
  `LoginUDPError.forceDisconnected(reason)`, which finishes the flow, cancels
  retries/timeouts, and surfaces the server reason. `CharacterCreateReply` is
  decoded but ignored because the iOS launcher does not expose character
  creation.
- `LoginProtocolTests.testForceDisconnectAndCharacterCreateReplyUseExactFieldOrder`
  checks independently written byte buffers, generic and `decodeAny` round
  trips, and trailing-byte rejection.

## Limits

- This does not implement character creation, account deletion, server update,
  or tunneled login opcodes.
- `LoginUDPSession` imports `Network` and remains excluded from the Linux
  Foundation-only test target; the exact byte codecs and `decodeAny` routing are
  covered by Linux tests, while the live failure path still requires macOS/iOS
  verification.
- No IPA was rebuilt by this note. The published release remains stale relative
  to this source change, and no full 1:1 port claim is made.
- Running the Foundation-only suite after the change produced 252 tests, 1
  skipped, 0 failures.
- No account credential was provided, requested, captured, or stored.
