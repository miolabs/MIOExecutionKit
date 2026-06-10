# example02 — adding the server layer

Same POS as example01, plus a server. The shared module (`POSKit`) compiles
into **both** executables; MIOServerKit serves it, MIOExecutionKit routes it.

## The diff vs example01 — all of it

1. **`AppContext` → `ExecutionContext`** (store + configuration, now also a
   router). The store gains one line: `extension POSStore: PersistentStoreAdapter {}`.
2. **One routing rule.** `chargeToAccount` is remote while the venue runs
   multiple POSes — customer accounts are shared. Conceptually:

   ```swift
   @ExecutionProfile(
       .pos(.remote, when: \POSConfiguration.clientAccountSyncRemotely)
   )
   ```

   (Phase 1: the expansion is hand-written in `Services.swift` — shim,
   `__local_` body, `__Op_` envelope. The macro will generate it.)

   `nextDocumentNumber` has **no rule**: each POS owns its cash desk prefix,
   so it stays local everywhere — unchanged from example01.
3. **The server**, [`pos-server/Main.swift`](Sources/pos-server/Main.swift) —
   ~20 lines: an `OperationRegistry` with the one remote-capable operation,
   the server's `ExecutionContext` (same code, its own store), and a single
   MIOServerKit route `/op/:operationID` that dispatches into the registry.

## Run

```sh
swift run pos-server            # terminal 1 (PORT=… to change)
swift run pos-app               # terminal 2 → charge executes on the server
SINGLE_POS=1 swift run pos-app  # single-POS venue → same call runs locally
swift test                      # e2e against an in-process MIOServerKit server
```

Watch the document prefix in the output: `SRV-…` means the charge was numbered
by the server (remote); your cash desk prefix means it ran locally.
