# Outbound UdpLibrary reliability evidence

This note records the send-side reconstruction added after the receive-side UDP
work in `08-udp-library-protocol.md`. It is based on Sanctuary source and the
stock client, not on invented timing behavior.

## Authoritative source

The authority is
`/tmp/opencode/sanctuary/src/Sanctuary.UdpLibrary/Internal/UdpReliableChannel.cs`
(audited commit `f5240b7554f2a80d6b815cb7ead7ffee12499565`), together with
`UdpConnection.cs`, `Configuration/UdpParams.cs`,
`Configuration/UdpReliableConfig.cs`, `Internal/Constants.cs` and
`Enumerations/EncryptMethod.cs`.

Relevant recorded facts:

| Field / rule | Source value |
|---|---|
| `ReliableOutgoingId` / `ReliableOutgoingPendingId` | 64-bit next and lowest-unacked ids, `UdpReliableChannel.cs:26-27` |
| Physical window | 400 packets, 200 KiB by default, `UdpParams.cs:482-496` |
| Fragment payload budget | `MaxRawPacketSize - 4 - CrcBytes - EncryptExpansionBytes`, `UdpReliableChannel.cs:93-104` |
| Initial RTT | 800 ms, `UdpReliableChannel.cs:89-90` |
| Resend delay | `min(8000, avg * 125 / 100 + 300)`, `UdpReliableChannel.cs:396-403` |
| RTT sample | `(avg * 3 + rtt) / 4`, only when `FirstTimeStamp == LastTimeStamp`, `UdpReliableChannel.cs:746-754` |
| Cumulative ACK over already-acked range | `avg += 400`, capped at 8000, `UdpReliableChannel.cs:340-365` |
| Slow start | `cwnd += MaxDataBytes` below ssthresh, `UdpReliableChannel.cs:730-743` |
| Congestion avoidance | `cwnd += max(1, MaxDataBytes² / cwnd)` above ssthresh, same lines |
| Timeout loss | `ssthresh = max(2 * MaxDataBytes, cwnd / 2)`, `cwnd = start`, `avg += 100`, `UdpReliableChannel.cs:611-629` |
| Accelerated loss | `cwnd = max(minimum, cwnd * 3 / 4)`, guarded by reset time and tolerance, `UdpReliableChannel.cs:571-601` |
| Unacknowledged timeout | external client default 120000 ms, checked when a resend is considered, `UdpReliableChannel.cs:561-568` |
| Wire id reconstruction | full id from 16-bit stamp and current high word, `UdpReliableChannel.cs:323-338` |
| ACK channel routing | `Reliable1-4` share channels with `Ack1-4` and `AckAll1-4`, `UdpConnection.cs:1123-1161` |
| Fragment layout | one id per physical frame; first frame reserves four bytes for BE32 total length, `UdpReliableChannel.cs:505-546,868-945` |
| ACK buffering | 50 ms `MaxDataHoldTime`, one-byte lengths in Multi (3), AckAll replaces earliest selective ACK, `UdpParams.cs:443`, `UdpReliableChannel.cs:237-278`, `UdpConnection.cs:1535-1644` |

`FreeRealms.exe` string evidence in `05-compiled-binaries-and-rea.md`
(`reliableOutgoingId=%lld`, `reliableOutgoingPendingId=%lld`, `ReliablePing=%dms`,
`DisconnectReasonReliableOverflow`, `UdpConnection`/`GroupLogicalPacket` RTTI)
confirms the shipped native client tracks the same two ids and group packets.
Those strings do not recover native control flow; the C# implementation remains
the semantic authority.

## Native implementation

`ios/Launcher/Services/UdpLibraryTransport.swift` now carries:

- `UdpLibraryConnectionConfig`: the negotiated encrypt code, CRC width, both
  encrypt methods and `MaxRawPacketSize`. Reliable payload capacity is derived
  with Sanctuary's formula. Unsupported CRC widths or encrypt methods are
  rejected by the sessions rather than silently mis-framed.
- `UdpLibraryOutgoingReliableState`: 64-bit send/pending ids, first/last send
  stamps, per-packet byte counts, RTT average, congestion window, slow-start
  threshold, fast-recovery tolerance and the C# ACK/AckAll state transitions.
- `UdpLibrary.channel(forAckType:)`: ACK routing by channel, so a channel-1 ACK
  cannot clear a channel-0 frame. `GiveTime` now returns the remaining time to
  the next resend rather than a fresh full delay, and marks the window full only
  after the ready queue has been processed.
- `UdpLibraryFragmenter`: applies the C# application zero escape once, keeps
  payloads at or below `MaxDataBytes` whole, and splits larger payloads with the
  first four bytes reserved for the BE32 total length. `encodeReliableBody` and
  `encodeFragment` frame cooked bodies without adding a second escape.
- `UdpLibraryBufferedAcks`: holds cooked ACKs, replaces the earliest selective
  ACK with a later AckAll when deduping, flushes a single ACK standalone, and
  otherwise builds one CRC-protected Multi datagram with one-byte lengths.

`LoginUDPSession.swift` records the negotiated Confirm facts, registers each
encoded reliable frame with the send state, feeds Ack/AckAll into it, and uses
its RTT-derived delay and resend list instead of a fixed one-second timer.
The gateway session does the same, wraps a secure application packet once before
fragmenting it, gives each fragment its own reliable stamp and retransmission
entry, and cancels its retry timer after a successful login. Both sessions
buffer inbound ACKs for 50 ms, flush before sending new reliable data and on
close/failure, and reset every transport state on close/failure.

## Coverage and limits

`ios/Tests/OSFRCoreTests/UdpLibraryOutboundTests.swift` covers payload sizing,
first-send RTT sampling, ACKs of resent packets, cumulative-ACK penalty, channel
routing, AckAll prefix release, wrap-around ids, the unacknowledged timeout,
remaining-delay scheduling, 506-byte fragmentation boundaries, BE32 first-fragment
headers, zero-escape placement, parser reassembly, ACK deduping and Multi wire
layout. The full Foundation suite is 206 tests with one iOS-Compression-only skip.

The earlier "not implemented" list below is historical. The current
`ios/Launcher/Services/UdpLibraryTransport.swift` includes a Group codec and
coalescer, CRC widths 0–4, five encryption methods (`None`, `UserSupplied`,
`UserSupplied2`, `XorBuffer`, `Xor`), 64-bit reliable-ID reconstruction,
per-channel ordering/reassembly, outgoing congestion/RTT state, a fragmenter, a
shared Multi buffer, cooking/crypto and inflate. It is still not a literal
whole-library port:

- Live timing against the real server has not been verified from this host;
  congestion-window and resend timings remain source-derived approximations.
- Many application-level opcode serializers and sub-opcodes remain unknown or
  unimplemented; transport parity does not imply world-view parity.
- `BufferedSend` scheduling details and exact datagram coalescing decisions have
  not been proven against a live capture beyond the covered tests.
