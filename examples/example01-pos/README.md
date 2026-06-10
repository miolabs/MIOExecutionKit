# example01 — POS, standalone

The starting point of the series: a complete little POS app with **no server,
no framework, no annotations**. Core Data (programmatic model, SQLite) plus
two domain services:

- `DocumentService.nextDocumentNumber(series:)` — sequential numbering per
  cash desk (`MAIN-T-0001`, `MAIN-T-0002`, …).
- `AccountService.chargeToAccount(_:)` — charges a customer account, numbering
  a document for each charge.

`AppContext` (store + configuration) is all the services need. In example02
it is replaced by MIOExecutionKit's `ExecutionContext` — that is the *only*
structural change the framework asks of you.

## Run

```sh
swift run pos-app    # creates pos.sqlite next to you; run twice — numbers continue
swift test
```
