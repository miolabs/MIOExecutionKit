# VenueExample

The canonical venue flow from the spec (§1.2), end-to-end over real HTTP,
with the `@ExecutionProfile` expansion **hand-written** (phase 1 — the macro
in phase 2 will generate exactly this code).

- **VenueKit** — the shared domain module: `DocumentService`, `AccountService`,
  their `__local_*` bodies and `__Op_*` envelopes, profiles (`pos`/`manager`/`server`),
  hosts (`.accounts`), and `PosConfiguration`.
- **MiniHTTP** — a tiny demo-grade HTTP server. Real deployments bind the
  `OperationRegistry` into MIOServerKit instead.
- **venue-demo** — runnable demo: starts an in-process server, then exercises
  every routing case and prints which store the state landed in.

## Run

```sh
swift run venue-demo   # use /usr/bin/xcrun swift run if your default toolchain is swiftly's
swift test
```

Expected routing:

| call | profile / config | resolves | why |
|---|---|---|---|
| `nextDocumentNumber` | pos | `.local` | each POS owns its cash desk prefix |
| `chargeToAccount` | pos, multi-POS venue | `.remote` | accounts shared across POSes |
| `chargeToAccount` | pos, single-POS flag off | `.local` | condition false → no rule matches |
| `nextDocumentNumber` | manager | `.remote` | manager owns no cash desk |
| everything | server | `.local` | the server is the authority for its hosts |
