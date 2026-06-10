# MIOExecutionKit

Profile-driven execution for "serverless" Swift apps: write business logic once,
as if it were a standalone local app, and let the framework decide — per function
and per execution profile — whether it runs **locally** or **remotely** (RPC to a
server running the same shared code). Delta sync of local saves is the persistence
layer's job (Core Data / MIOPersistentStore save notifications), not this kit's.

```swift
@ExecutionProfile(
    host: .accounts,   // micro-server designs only; single-server apps omit it
    .manager(.remote),
    .pos(.remote, when: \PosConfiguration.clientAccountSyncRemotely)
)
public func chargeToAccount(_ charge: AccountCharge) async throws -> AccountBalance
```

**The single resolution rule: if no rule matches the active profile, the function
executes `.local`.** No annotation → no shim, no envelope, no endpoint.

Full design: [docs/MIOExecutionKit-Spec.md](docs/MIOExecutionKit-Spec.md)

## Status

Draft / phase 1 of 5 (see spec §9). Currently implemented:

- Core types: `ExecutionProfile`, `ExecutionMethod` (`.local`/`.remote`), `ProfileRule`,
  `ExecutionPlan`, `RemoteHost` (multi-server routing), `ProfileConfiguration`,
  router protocols, first-match-wins resolution.
- `ClientRouter` (resolution + hosts map — transport TODO) and `ServerRouter`
  (local for its own hosts, remote for foreign hosts).
- Resolution test suite covering the venue example.

Not yet: HTTP/WebSocket transport, `@ExecutionProfile` macro (`MIOExecutionMacros`),
build-tool plugin (`MIOExecutionGen`).

## Targets

| Target | Links against | Purpose |
|---|---|---|
| `MIOExecutionKit` | — | Core types + resolution; the module shared code imports |
| `MIOExecutionClient` | core | App-side router: RPC transport |
| `MIOExecutionServer` | core | Server-side router + MIOServerKit endpoint binding |
