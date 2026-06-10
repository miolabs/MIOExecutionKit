# example03 — adding the manager app

A second app *type* joins the venue: the **manager** (reporting). It links the
same `POSKit` and calls the same services with the same lines of code — only
the `ExecutionProfile` in its context differs, and that changes where
everything executes.

## The diff vs example02 — all of it

1. **A new profile**: `ExecutionProfile.manager` (one line in `Profiles.swift`).
2. **`nextDocumentNumber` gains a rule** — the manager owns no cash desk, so
   numbering must happen on the server:

   ```swift
   @ExecutionProfile(.manager(.remote))
   ```

   With its first rule comes its shim + envelope (hand-written in phase 1),
   and the server registers the new operation. **POS behavior is untouched**:
   no rule matches the pos profile, so it keeps numbering locally.
3. **`chargeToAccount` adds `.manager(.remote)`** ahead of its pos rule.
4. **`manager-app`** — a copy of pos-app's wiring with `profile: .manager`,
   an in-memory store (managers own no domain data) and no configuration.

## Run

```sh
swift run pos-server     # terminal 1
swift run pos-app        # terminal 2: ticket local, charge remote
swift run manager-app    # terminal 2: EVERYTHING remote — prefixes say SRV
swift test
```

The point to notice: `manager-app` and `pos-app` contain the *same service
calls*. The behavior difference is entirely declared by `(profile, rules)` —
which is the whole idea of the framework.
