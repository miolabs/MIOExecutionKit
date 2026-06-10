# MIOExecutionKit

Profile-driven execution for "serverless" Swift apps: write business logic once,
as if it were a standalone local app, and let the framework decide — per function
and per execution profile — whether it runs **locally**, **on the server** (RPC),
or **locally with deferred delta sync**.

```swift
@ExecutionProfile(
    .manager(.sync),
    .pos(.sync, when: \PosConfiguration.clientAccountSyncRemotely),
    .pos(.async)
)
public func chargeToAccount(_ charge: AccountCharge) async throws -> AccountBalance
```

**The single resolution rule: if no rule matches the active profile, the function
executes `.local`.** No annotation → no shim, no envelope, no endpoint.

Full design: [docs/MIOExecutionKit-Spec.md](docs/MIOExecutionKit-Spec.md)

## Status

Draft / phase 1 of 5 (see spec §9). Currently implemented:

- Core types: `ExecutionProfile`, `SyncMethod`, `ProfileRule`, `ExecutionPlan`,
  `ProfileConfiguration`, router protocols, first-match-wins resolution.
- `ClientRouter` (resolution only — transport TODO) and `ServerRouter` (always `.local`).
- Resolution test suite covering the venue example.

Not yet: HTTP/WebSocket transport, `@ExecutionProfile` macro (`MIOExecutionMacros`),
build-tool plugin (`MIOExecutionGen`), changelog sync engine wiring.

## Targets

| Target | Links against | Purpose |
|---|---|---|
| `MIOExecutionKit` | — | Core types + resolution; the module shared code imports |
| `MIOExecutionClient` | core | App-side router: RPC transport + delta sync engine |
| `MIOExecutionServer` | core | Server-side router + MIOServerKit endpoint binding |
