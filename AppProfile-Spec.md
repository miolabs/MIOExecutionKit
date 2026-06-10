# MIOExecutionKit — Profile-Driven Execution for "Serverless" Swift Apps

**Status:** Draft 0.2.1
**Author:** Javier / Dual Link
**Targets:** Swift 6, SwiftSyntax macros, SPM build-tool plugins, MIOServerKit / MIOPersistentStore

> **Changes from 0.2:** Project named **MIOExecutionKit**; `AppProfile` renamed `ExecutionProfile` (a server is technically an app, but "application profile" reads wrong for it — "execution profile" covers every binary); macro renamed `@ExecutionProfile`; framework packages renamed accordingly.
>
> **Changes from 0.1:** Local-first resolution model (everything is `.local` unless a rule says otherwise), variadic per-profile rule syntax replacing `default:`/`rules:` dictionary, call-time conditions, `.profileDefault` removed, JSON config reduced to optional runtime overrides, endpoint generation restricted to `.sync`-capable operations, single-writer enforcement moved to the sync engine, venue/POS worked example.

---

## 1. Overview

The goal is a set of Swift libraries that let a developer write an application as if it were a **standalone, local app** — business logic written once, against a single domain API — while the framework decides, per function and per application profile, *where* that logic actually executes:

- **Locally**, against a local persistent store (Core Data / SwiftData / MIOPersistentStore on SQLite).
- **Remotely**, as an RPC to a server target that runs the *same shared code* against PostgreSQL.
- **Deferred (async)**, executed locally first, with a background sync service reconciling deltas with the server (changelog / `syncIndex` based).

The developer never writes networking code. A Swift macro, `@ExecutionProfile`, annotates the domain functions that deviate from local execution; the framework's runtime router plus a build-tool plugin generate the client transport and server endpoints.

### 1.1 Design philosophy: local-first, polish later

The intended development flow mirrors how these apps are actually built:

1. **Build the app standalone.** Every function runs locally. No annotations, no config, no server. The framework adds zero overhead at this stage — unannotated functions get no routing shim at all.
2. **Add the server target.** The shared module compiles into it unchanged.
3. **Polish function by function.** The developer — who knows which profile needs which behavior — adds `@ExecutionProfile` rules only to the functions that deviate: this one must be server-authoritative for the manager app, that one syncs asynchronously on the POS.

The corollary is the single resolution rule of the whole framework:

> **If no rule matches the active profile, the function executes `.local`.**

There are no per-profile defaults, no mandatory config file, and no special-casing for the server: the server profile simply matches no rules, so everything runs locally against PostgreSQL — the server *is* the authority, for free.

### 1.2 Canonical example: a venue

A Dual Link venue runs three application **types** — the **POS** (point of sale), the **manager** (reporting), and the **server** — but may run more *installations* than types: e.g. two POS apps, one for the main area and one for the terrace (4 installations, 3 types).

- `nextDocumentNumber(series:)` on the POS is **local**: each POS owns a `CashDesk` entity with its own document prefix, and every cash desk numbers from 1 independently. The sequence is *partitioned by ownership*, so there is nothing to be authoritative about remotely. The manager app owns no cash desk, so for it the same function is a **sync** RPC.
- `chargeToAccount(...)` touches customer accounts, which are **shared across all POSes** in the venue → **sync**. Except in the special single-POS configuration (one installation, possibly a venue without reliable internet), where a settings flag makes it run locally and sync **asynchronously**.

Both functions live in the same shared module and are called identically everywhere; the per-profile rules and a call-time condition decide the execution plan.

### 1.3 Design principle: partition ownership before forcing `.sync`

The cash-desk prefix is the model to imitate: rather than making document numbering server-authoritative, the ID space is partitioned (one prefix and counter per cash desk) so that local authority is safe. Developers should reach for ownership partitioning first, and reserve `.sync` for state that genuinely cannot be partitioned (cross-installation balances, global sequences, stock reservations).

---

## 2. Goals & Non-Goals

### Goals
1. Single shared domain module compiled into **both** the app target and the server target.
2. **Local by default.** Per-function deviations declared with one macro attribute, co-located with the function. No annotation → no shim, no envelope, no endpoint, no config entry.
3. Profiles are **open-ended**: adding a new profile is a declaration change in the app, not a framework change.
4. Hybrid apps: a mostly-async app can force specific functions to be sync (server-authoritative), including **conditionally**, resolved at call time from installation configuration.
5. Server endpoint code (routes, request/response codecs) is **generated**, never hand-written — and generated **only** for operations that can actually resolve to `.sync`.
6. Offline-first sync built on the existing changelog architecture (`changelog_committed`, `sync_index`, entity-subscription index over WebSocket).

### Non-Goals (v1)
- Cross-language clients (TypeScript/Kotlin). The wire protocol should not preclude it, but codegen targets Swift only.
- Automatic conflict-resolution policies beyond last-writer-wins + server-authoritative functions + designated single-writer entity types (§6.4).
- Arbitrary distributed transactions spanning local and remote stores in a single call.

---

## 3. Core Concepts

### 3.1 SyncMethod

How a function executes relative to the server. With local-as-default there is no `.profileDefault` case — declared and resolved methods are the same closed set, and `resolve()` is total.

```swift
public enum SyncMethod: String, Codable, Sendable {
    /// Execute locally against the local store. Never talks to the server.
    case local

    /// Execute locally, persist locally, enqueue delta; background service
    /// pushes/pulls via the changelog sync engine.
    case async

    /// Always execute on the server. The client call is an RPC; the local
    /// store may be updated from the response (read-through).
    case sync
}
```

### 3.2 ExecutionProfile

A profile names an **application type** — what kind of binary this is. The framework ships none hard-coded; apps declare their own as static members (a `RawRepresentable` struct, not an enum, so it is open for extension without recompiling the framework, yet still pattern-matchable).

```swift
public struct ExecutionProfile: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

// Application-side declaration.
public extension ExecutionProfile {
    static let pos     = ExecutionProfile(rawValue: "pos")
    static let manager = ExecutionProfile(rawValue: "manager")
    static let server  = ExecutionProfile(rawValue: "server")
}
```

Note the profile is the *type*, not the *installation*: the main-area POS and the terrace POS are two installations of the same `pos` profile. What differs between installations is configuration (§3.4), not profile.

### 3.3 ProfileRule

One `(profile, method, condition?)` triple. The macro takes a variadic list of these.

```swift
public struct ProfileRule: Sendable {
    public let profile: ExecutionProfile
    public let method: SyncMethod
    /// Evaluated at call time against the installation configuration.
    /// Type-erased at construction from a typed KeyPath (see §3.4).
    public let condition: (@Sendable (any ProfileConfiguration) -> Bool)?
}
```

Apps add one line of sugar per profile so rules read naturally at the use site:

```swift
public extension ProfileRule {
    static func pos(_ m: SyncMethod) -> ProfileRule { .init(profile: .pos, method: m, condition: nil) }
    static func pos<C: ProfileConfiguration>(_ m: SyncMethod, when kp: KeyPath<C, Bool>) -> ProfileRule {
        .init(profile: .pos, method: m) { ($0 as? C)?[keyPath: kp] ?? false }
    }
    static func manager(_ m: SyncMethod) -> ProfileRule { .init(profile: .manager, method: m, condition: nil) }
    // …
}
```

### 3.4 ProfileConfiguration

Installation-level settings — the things that differ between the main-area POS and the terrace POS, or between a multi-POS venue and a single-POS venue. The framework defines only the protocol; the app owns the concrete type and its storage (settings bundle, server-distributed config, etc.).

```swift
public protocol ProfileConfiguration: Sendable {}

// Application-side:
public struct PosConfiguration: ProfileConfiguration {
    public var installationID: String          // "pos-terrace"
    public var cashDeskID: String              // "TERRACE" — owns the document prefix
    public var clientAccountSyncRemotely: Bool // false only in single-POS venues
}
```

Conditions read this object **at call time**, so flipping a flag in settings changes routing without recompiling — this replaces draft 0.1's JSON `overrides` mechanism for the common case.

### 3.5 Resolution

The entire algorithm:

```
1. Runtime override for (operationID, activeProfile) in overrides config?  → use it.   [optional, §3.6]
2. Walk the macro's rules in declaration order.
   First rule whose profile == activeProfile and whose condition
   (if any) evaluates true                                                 → use its method.
3. No match                                                                → .local
```

Order matters and **first match wins**: a conditional rule acts as the special case, an unconditioned rule for the same profile placed after it acts as the fallback. The macro emits compile errors for unreachable rules (§5.4), so misordering cannot ship.

```swift
public struct ExecutionPlan: Sendable {
    public let method: SyncMethod          // total: resolve() always returns one of the three cases
    public let operationID: String         // "AccountService.chargeToAccount(_:)" (+ schema hash, §7.3)
    public let isServerAuthoritative: Bool // true when method == .sync
}
```

### 3.6 Runtime overrides (optional)

A small optional config file remains as an operational escape hatch — forcing a method per operation per profile without recompiling, e.g. while diagnosing a sync problem in production. It is no longer required, has no per-profile defaults section, and most apps ship without it:

```json
{
  "overrides": {
    "pos": { "AccountService.chargeToAccount(_:)": "sync" }
  }
}
```

Precedence (highest first): **runtime override > macro rules > `.local`**.

---

## 4. Project Layout

A standard workspace contains three SPM/Xcode targets plus the framework packages:

```
MyApp/
├── Packages/
│   └── MyAppKit/                    ← shared domain module (annotated code lives here)
│       ├── Sources/MyAppKit/
│       │   ├── DocumentService.swift
│       │   └── AccountService.swift
│       └── Package.swift
├── MyApp-POS/                       ← app target: links MyAppKit + MIOExecutionClient
├── MyApp-Manager/                   ← app target: links MyAppKit + MIOExecutionClient
├── MyApp-Server/                    ← server target: links MyAppKit + MIOExecutionServer
│   └── Generated/                   ← emitted by the build-tool plugin
└── Libs/
    └── MIOExecutionKit/             ← one SPM package, five targets:
        ├── MIOExecutionKit          ← core: macro decls, SyncMethod, ExecutionProfile, ProfileRule, router protocols
        ├── MIOExecutionMacros       ← SwiftSyntax macro implementations
        ├── MIOExecutionClient       ← URLSession/WebSocket transport, local store binding, sync engine
        ├── MIOExecutionServer       ← MIOServerKit binding, endpoint registry
        └── MIOExecutionGen          ← build-tool plugin (server route + codec generation)
```

The key property: **`MyAppKit` compiles unmodified into both executables.** Only the runtime it is linked against (and the installation configuration it loads) changes behavior.

---

## 5. The Macro API

### 5.1 Declaration

```swift
/// Attached to a function inside a type conforming to `ProfiledService`.
/// Rules are evaluated in declaration order; first match wins; no match → .local.
@attached(body)
@attached(peer, names: prefixed(__local_), prefixed(__Op_))
public macro ExecutionProfile(
    _ rules: ProfileRule...
) = #externalMacro(module: "MIOExecutionMacros", type: "ExecutionProfileMacro")
```

One attribute, variadic rules. The repeated-attribute form (`@ExecutionProfile(.manager, .sync)` stacked per profile) is **not possible**: the routing shim makes this a body macro, and SE-0415 allows at most one body macro per function. The variadic form preserves the same per-profile readability in a single attribute.

Name specifiers are explicit (`prefixed(__local_)`, `prefixed(__Op_)`) rather than `arbitrary` — `arbitrary` disables lazy macro expansion module-wide and has scope-lookup restrictions.

### 5.2 Usage — the venue example

```swift
import MIOExecutionKit

public struct DocumentService: ProfiledService {
    let context: ExecutionContext   // injected: store, router, configuration, identity

    /// Each POS owns its CashDesk: own prefix, own counter from 1 → the
    /// sequence is partitioned, local execution is safe, deltas sync in
    /// the background. The manager owns no cash desk → server call.
    /// On the server: no rule matches → runs locally against PG.
    @ExecutionProfile(
        .manager(.sync),
        .pos(.async)
    )
    public func nextDocumentNumber(series: String) async throws -> DocumentNumber {
        try await context.store.performExclusive {
            try $0.incrementSequence(named: "doc.\(context.configuration.cashDeskID).\(series)")
        }
    }
}

public struct AccountService: ProfiledService {
    let context: ExecutionContext

    /// Customer accounts are shared across all POSes in the venue → sync.
    /// Single-POS venues flip `clientAccountSyncRemotely` off in settings
    /// and the same call runs locally + async — no recompile.
    /// First match wins: the conditional rule is the normal case, the
    /// unconditioned `.pos(.async)` after it is the fallback.
    @ExecutionProfile(
        .manager(.sync),
        .pos(.sync, when: \PosConfiguration.clientAccountSyncRemotely),
        .pos(.async)
    )
    public func chargeToAccount(_ charge: AccountCharge) async throws -> AccountBalance {
        let number = try await DocumentService(context: context)
            .nextDocumentNumber(series: charge.series)
        // … mutate account, persist receipt …
    }
}
```

Note the composition: `chargeToAccount` may resolve `.async` on a single-POS installation while a future inner call that is `.sync` for that profile would independently resolve and RPC — each annotated function routes itself, so hybrid behavior falls out naturally. Functions with **no** annotation (the majority) are plain Swift: no shim, no envelope, no endpoint.

### 5.3 What the macro expands to

An important constraint drives the design: **Swift macros are pure syntactic transforms.** They cannot read configuration, cannot see `-D` compilation conditions, and cannot know which target they are being compiled into. Therefore the macro does **not** generate different code per profile. It generates *routing* code, identical in all targets; the linked runtime + installation configuration decide the path. Rule expressions — including `when:` conditions — are copied verbatim into the generated `resolve()` call, never evaluated at expansion time.

Expansion of `chargeToAccount` (conceptually):

```swift
public func chargeToAccount(_ charge: AccountCharge) async throws -> AccountBalance {
    let plan = context.router.resolve(
        operationID: __Op_chargeToAccount.operationID,
        rules: [
            .manager(.sync),
            .pos(.sync, when: \PosConfiguration.clientAccountSyncRemotely),
            .pos(.async)
        ],
        configuration: context.configuration
    )
    switch plan.method {
    case .local:
        return try await __local_chargeToAccount(charge)
    case .async:
        return try await context.router.executeDeferred(plan) {
            try await self.__local_chargeToAccount(charge)
        }
    case .sync:
        return try await context.router.executeRemote(
            plan,
            request: __Op_chargeToAccount(charge: charge),
            as: AccountBalance.self
        )
    }
}

// peer: the original body, renamed
private func __local_chargeToAccount(_ charge: AccountCharge) async throws -> AccountBalance { … original body … }

// peer: Codable envelope — simultaneously the wire format and the server-side executor.
// PUBLIC: the generated Routes.swift lives in the server target, a different module.
public struct __Op_chargeToAccount: ProfiledOperation {
    public static let operationID = "AccountService.chargeToAccount(_:)"
    public let charge: AccountCharge
    public func execute(in ctx: ExecutionContext) async throws -> AccountBalance {
        try await AccountService(context: ctx).__local_chargeToAccount(charge)
    }
}
```

Three artifacts per annotated function:

1. **Router shim** (the rewritten body).
2. **`__local_*` peer** carrying the original implementation.
3. **`ProfiledOperation` envelope** — emitted **only if the rule list contains a `.sync` rule** (conditional or not). Async- and local-only functions need no wire format. Envelopes and their members are `public` because the generated server routes decode them from another module.

### 5.4 Macro diagnostics (compile errors)

- Function must be `async throws` (remote execution implies both).
- All parameters and the return type must be `Codable & Sendable` — required only when a `.sync` rule is present; async/local-only functions are exempt.
- Function must be a member of a `ProfiledService` type with an `ExecutionContext`.
- **Unreachable rule**: an unconditioned rule for profile X followed by any later rule for X.
- **Duplicate rule**: two rules with the same `(profile, condition)` shape.
- Empty rule list (`@ExecutionProfile()`): warning — annotation has no effect; remove it.

---

## 6. Runtime Architecture

### 6.1 ExecutionContext & Router

```swift
public protocol ExecutionRouter: Sendable {
    func resolve(operationID: String,
                 rules: [ProfileRule],
                 configuration: any ProfileConfiguration) -> ExecutionPlan

    func executeRemote<Op: ProfiledOperation>(
        _ plan: ExecutionPlan, request: Op, as: Op.Output.Type
    ) async throws -> Op.Output

    func executeDeferred<T: Sendable>(
        _ plan: ExecutionPlan, _ body: @Sendable () async throws -> T
    ) async throws -> T
}

public struct ExecutionContext: Sendable {
    public let profile: ExecutionProfile
    public let configuration: any ProfileConfiguration
    public let router: any ExecutionRouter
    public let store: any PersistentStoreAdapter   // v1: MIOPersistentStore (client) / PG (server)
}
```

Resolution state lives **only** in the router — there is no global registry or singleton. This is what makes the test matrix (§8.5) trivial: a `TestRouter` forcing any plan slots into a test `ExecutionContext` without touching shared state.

- **MIOExecutionClient** ships `ClientRouter`: `.sync` → HTTP/WebSocket RPC to the server (`POST /op/{operationID}` with the envelope JSON); `.async` → run body locally, then enqueue the resulting changelog deltas; `.local` → run body.
- **MIOExecutionServer** ships `ServerRouter`: `resolve()` ignores rules and always returns `.local` — no rule matches the `server` profile by construction, and even an explicit `.sync` reaching the server executes locally, because the server *is* the authority.
- `PersistentStoreAdapter` is deliberately minimal in v1: `performExclusive`, insert/fetch/delete, `incrementSequence`. MIOPersistentStore is the first-class client adapter; Core Data / SwiftData adapters come later.

### 6.2 The async path & sync engine

`.async` does **not** mean "queue the RPC for later." The local execution is authoritative on-device; what travels are **entity deltas**, using the existing changelog architecture:

- Local mutations are recorded with a monotonically increasing local `syncIndex` cursor.
- A background service (the "sync thread") pushes deltas and pulls remote changes over WebSocket, filtered by the inverted entity-subscription index and `app_ids` scoping.
- Server applies deltas into `changelog_committed` (entities JSONB, `sync_index`, `updatedByAppID`), and fans out to subscribed peers. Every delta carries the originating installation ID — this is what the single-writer enforcement in §6.4 keys on.
- Conflicts: last-writer-wins by default; anything that must not conflict (cross-installation sequences, account balances, stock reservations) belongs in a `.sync` function or a designated single-writer entity type (§6.4) — that is precisely the design pressure the macro encodes.

The framework cleanly separates two channels: **RPC** (for `.sync` operations) and **delta sync** (for `.async` state), rather than conflating them.

### 6.3 Transactionality rules

| method | local store | server store | guarantee |
|---|---|---|---|
| `.local` | tx commit | — | local ACID |
| `.async` | tx commit | eventual | local ACID, eventual server consistency |
| `.sync`  | optional read-through cache update | tx commit | server ACID; client sees committed result |
| `.async` calling `.sync` inside | tx commit *after* inner RPC commits | inner op: tx commit; outer state: eventual | server commits inner op first; if it fails, the outer local tx never commits |

The last row is the main sharp edge developers must understand: when an `.async` function's body calls a `.sync` function, the server-authoritative inner call happens *first*, and a failure there aborts the whole local operation — nothing is persisted locally.

### 6.4 Single-writer enforcement (sync engine, not router)

The single-POS condition (`clientAccountSyncRemotely == false`) assumes that installation is the **only** local writer of customer accounts in its venue. Configuration can lie — a second POS added later, a flag set on both by mistake — and two local writers under last-writer-wins would silently corrupt balances. Enforcement belongs in the sync engine, server-side, where the data already exists:

- The app declares **single-writer entity types** (e.g. `CustomerAccount`) in the server's sync configuration.
- The server tracks, per `(venue, entityType)`, the installation currently acting as local writer (first delta claims it, or it is provisioned explicitly).
- A delta for a single-writer entity type arriving with a different `updatedByAppID` is **rejected or quarantined**, never LWW-merged, and raises an operational alert.

This keeps the macro API exactly as small as §5 shows — the safety net costs one comparison per delta against data the changelog already carries.

### 6.5 Degraded mode (connectivity loss)

- A single-POS venue with the local-account flag keeps working fully offline by construction — nothing it does resolves `.sync`.
- Any installation that loses connectivity: `.async` operations keep working and queue deltas; `.sync` operations **fail fast with a typed error** (`ProfiledOperationError.serverUnreachable`) that the app layer can catch and surface. The framework does not silently downgrade `.sync` to `.local` — if a function should degrade, that is a `when:` condition the developer writes deliberately.

---

## 7. Server Target Code Generation

A SPM **build-tool plugin** (`MIOExecutionGen`) attached to the server target:

1. Parses the shared module's sources with SwiftSyntax, collecting every `@ExecutionProfile` function **whose rule list contains a `.sync` rule** (same visitor logic the macro uses, reused as a library). Conditions are irrelevant to the plugin — a conditional `.sync` means "may be sync," which is enough to require an endpoint. Functions without a `.sync` rule get **no route**: the RPC surface is exactly the set of operations that can legitimately arrive over the wire, nothing more.
2. Emits `Generated/Routes.swift` registering one MIOServerKit endpoint per operation, using the **async dispatcher overload** that `Endpoint.post` already provides (`AsyncEndpointRequestDispatcher`) — no `EventLoopPromise` bridging, no semaphores on NIO workers:

```swift
// GENERATED — do not edit
import MIOServerKit
import MyAppKit

public func registerProfiledOperations(_ router: MIOServerKit.Router,
                                       context: @escaping () -> ExecutionContext) {
    router.post("/op/\(__Op_chargeToAccount.operationID)") { req in
        let op = try req.decode(__Op_chargeToAccount.self)
        return try await op.execute(in: context())
    }
    router.post("/op/\(__Op_nextDocumentNumber.operationID)") { req in
        let op = try req.decode(__Op_nextDocumentNumber.self)
        return try await op.execute(in: context())
    }
}
```

3. Emits an `operations-manifest.json` (operationID → request/response schema) usable later for non-Swift clients or API docs.

Because the envelope structs generated by the macro already know how to decode and execute themselves, the generated route bodies are uniform one-liners — the plugin never needs to understand business logic or evaluate conditions.

### 7.1 Auth & tenancy

Auth, tenancy (`app_id` / venue), and idempotency keys ride in envelope headers added by `ClientRouter`, validated by a single MIOServerKit middleware — not per-route. Treat every envelope as untrusted input: it executes with full server context. Per-operation *authorization* (which caller may invoke which operation) is middleware policy keyed on `operationID`, declared alongside the single-writer entity config.

### 7.2 Idempotency

`.sync` retries after a timeout are the dangerous case: the server may have committed (a sequence incremented, an account charged) and the retry would do it twice. v1 requirement, not an option:

- `ClientRouter` attaches an idempotency key per logical call (UUID, reused across retries of the same call).
- The server keeps a dedup table keyed `(app_id, idempotency_key)` storing the serialized response, with a retention window (e.g. 24h), checked by the same middleware. A hit replays the stored response without re-executing.
- The dedup table lives next to `changelog_committed`.

### 7.3 Operation identity & versioning

`operationID` is the type name plus the **full function signature with argument labels** — `AccountService.chargeToAccount(_:)` — so overloads cannot collide, suffixed with a short schema hash of the parameter and return types: `AccountService.chargeToAccount(_:)@a1b2c3`. An old client calling a changed signature gets an immediate 404-class failure instead of decoding garbage. The manifest records the hash inputs for diffing across releases.

---

## 8. Open Questions

1. **Condition expression form** — `when:` as a typed `KeyPath` (shown throughout) type-checks cleanly in attribute position; an `@autoclosure () -> Bool` referencing instance members (e.g. `configuration.flag`) may not, since attribute arguments are type-checked in the enclosing context. Needs a toolchain spike in phase 2; the KeyPath form is the safe default, closures remain attractive for composite conditions.
2. **Body macros toolchain floor** — `@attached(body)` (SE-0415) sets the minimum toolchain. Swift 6 is already the target, so the floor is accepted; verify the exact minimum during phase 2. Constraint to remember: only one body macro per function, so `@ExecutionProfile` cannot compose with another body-rewriting macro.
3. **Per-profile compile-time pruning** — since macros can't see the target, `__local_*` bodies of server-only functions still compile into thin clients (code size / secrecy). Option: a second `MIOExecutionGen` pass for the client target that strips them.
4. **Streaming / non-Codable returns** — out of scope v1; consider `AsyncThrowingStream` support over WebSocket later.
5. **Testing profile matrix** — provide a `TestRouter` that forces any plan and a `TestConfiguration`, so the same XCTest suite runs each annotated function under all three methods and both condition branches.
6. **Plugin sandbox** — `MIOExecutionGen` must read the shared package's sources from the server target's plugin. SPM allows cross-package reads in the sandbox for local packages; pin this assumption in the first phase-3 spike, it is the part most likely to fight SPM.

---

## 9. Roadmap

| Phase | Deliverable |
|---|---|
| 1 | `MIOExecutionKit` types (`SyncMethod`, `ExecutionProfile`, `ProfileRule`, resolution) + `ClientRouter`/`ServerRouter`/`TestRouter` with **hand-written** envelopes; prove the venue flow end-to-end without macros, including a call-time condition flip |
| 2 | `ExecutionProfileMacro` (body + peer expansion, diagnostics incl. unreachable-rule, `when:` spike) replacing the hand-written envelopes |
| 3 | `MIOExecutionGen` build-tool plugin → generated MIOServerKit routes (`.sync`-capable ops only) + manifest + schema-hash operation IDs |
| 4 | `.async` channel wired to the changelog sync engine (`sync_index` cursor, WebSocket delta service); idempotency dedup table; single-writer entity enforcement |
| 5 | Runtime overrides config, degraded-mode errors, client-side pruning pass, docs |
