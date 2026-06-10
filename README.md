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
- `ClientRouter` with a real HTTP transport (`URLSessionTransport`, pluggable via
  `RemoteTransport`) and `ServerRouter` (local for its own hosts, remote for foreign hosts).
- `OperationRegistry` — server-side dispatch (operationID → decode envelope, execute,
  encode output); what phase 3's generated routes will register into.
- Test suites: resolution, host routing, envelope round-trip.
- [examples/VenueExample](examples/VenueExample) — the venue flow end-to-end over real
  HTTP with hand-written envelopes (`swift run venue-demo`).

Not yet: `@ExecutionProfile` macro (`MIOExecutionMacros`), build-tool plugin
(`MIOExecutionGen`), MIOServerKit binding, idempotency dedup / auth middleware.

## Targets

| Target | Links against | Purpose |
|---|---|---|
| `MIOExecutionKit` | — | Core types + resolution; the module shared code imports |
| `MIOExecutionClient` | core | App-side router: RPC transport |
| `MIOExecutionServer` | core | Server-side router + MIOServerKit endpoint binding |
