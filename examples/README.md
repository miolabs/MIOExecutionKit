# MIOExecutionKit — Tutorials

A progressive series. Each example is a self-contained SPM package; the
**diff between consecutive examples is the lesson**. (A workspace gathering
all of them is planned.)

| Example | What it adds | What you learn |
|---|---|---|
| [example01-pos](example01-pos) | Nothing — a plain POS app: Core Data + domain logic | Every app in this architecture starts standalone. No server, no framework, no annotations. |
| [example02-server](example02-server) | A server (MIOServerKit) + MIOExecutionKit | The few lines that turn shared code into a client/server app: `AppContext` → `ExecutionContext`, one routing rule on `chargeToAccount`, a ~20-line server main. |
| [example03-manager](example03-manager) | A second app type: the manager | Same shared code, different profile → different routing. The manager owns no cash desk, so `nextDocumentNumber` gains `.manager(.remote)` and executes on the server. |

Run any example with `swift test`, and the apps with `swift run` (see each
README). If your default `swift` is an older swiftly toolchain, use
`/usr/bin/xcrun swift …` instead.

> Phase-1 note: the `@ExecutionProfile` macro does not exist yet, so its
> expansion (router shim, `__local_*` body, `__Op_*` envelope) is written by
> hand in examples 02–03, clearly marked. When phase 2 lands, those blocks
> collapse to a single attribute on the function.
