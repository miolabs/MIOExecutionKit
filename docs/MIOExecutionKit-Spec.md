# MIOExecutionKit — Profile-Driven Execution for "Serverless" Swift Apps

**Status:** Draft 0.4
**Author:** Javier / Dual Link
**Targets:** Swift 6, SwiftSyntax macros, SPM build-tool plugins, MIOServerKit / MIOPersistentStore

> **Changes from 0.3:** Multi-server (micro-server) support via **`RemoteHost`** (§3.7): an open-ended logical name declared per function (`host:` in the macro, default `.default`), mapped to base URLs / path prefixes in deployment configuration — never in code. Only meaningful for `.remote`. Consequence for servers: a server is the authority **for its own hosts only** — `ServerRouter` resolves foreign-host operations `.remote` (server-to-server RPC). The build plugin groups generated routes and the manifest by host.
>
> **Changes from 0.2.1:** Execution is **binary** — `.local` or `.remote`. The former `.async` case is gone: delta sync is not an execution decision, it is what the persistence layer does after any local save (Core Data / MIOPersistentStore generate deltas from save notifications). That belongs to a different library and is out of scope here; `SyncMethod` is renamed `ExecutionMethod`, `executeDeferred` is removed from the router, and the venue example loses its fallback rule (no match → local, deltas sync anyway).
>
> **Changes from 0.2:** Project named **MIOExecutionKit**; `AppProfile` renamed `ExecutionProfile`; macro renamed `@ExecutionProfile`; framework packages renamed accordingly.
>
> **Changes from 0.1:** Local-first resolution model (everything is `.local` unless a rule says otherwise), variadic per-profile rule syntax, call-time conditions, JSON config reduced to optional runtime overrides, endpoint generation restricted to remote-capable operations.

---

## 1. Overview

The goal is a set of Swift libraries that let a developer write an application as if it were a **standalone, local app** — business logic written once, against a single domain API — while the framework decides, per function and per execution profile, *where* that logic actually executes:

- **Locally**, against the local persistent store (Core Data / SwiftData / MIOPersistentStore on SQLite).
- **Remotely**, as an RPC to a server target that runs the *same shared code* against PostgreSQL.

That is the entire decision space. **Delta synchronization is orthogonal**: when a function executes locally and saves, the persistence layer (standard Core Data or MIOPersistentStore) generates changelog deltas from the save notification and a background service reconciles them with the server (`changelog_committed` / `sync_index` over WebSocket). That machinery lives in its own library, runs the same way regardless of what this kit decides, and is referenced here only where the two meet (§6.2).

The developer never writes networking code. A Swift macro, `@ExecutionProfile`, annotates the domain functions that deviate from local execution; the framework's runtime router plus a build-tool plugin generate the client transport and server endpoints.

### 1.1 Design philosophy: local-first, polish later

The intended development flow mirrors how these apps are actually built:

1. **Build the app standalone.** Every function runs locally. No annotations, no config, no server. The framework adds zero overhead at this stage — unannotated functions get no routing shim at all.
2. **Add the server target.** The shared module compiles into it unchanged.
3. **Polish function by function.** The developer — who knows which profile needs which behavior — adds `@ExecutionProfile` rules only to the functions that must run remotely for some profile.

The corollary is the single resolution rule of the whole framework:

> **If no rule matches the active profile, the function executes `.local`.**

There are no per-profile defaults, no mandatory config file, and no special-casing for the server: the server profile simply matches no rules, so everything runs locally against PostgreSQL — the server *is* the authority, for free.

### 1.2 Canonical example: a venue

A Dual Link venue runs three application **types** — the **POS** (point of sale), the **manager** (reporting), and the **server** — but may run more *installations* than types: e.g. two POS apps, one for the main area and one for the terrace (4 installations, 3 types).

- `nextDocumentNumber(series:)` on the POS is **local**: each POS owns a `CashDesk` entity with its own document prefix, and every cash desk numbers from 1 independently. The sequence is *partitioned by ownership*, so there is nothing to be authoritative about remotely. (The resulting documents reach the server later as deltas — persistence-layer business, not routing business.) The manager app owns no cash desk, so for it the same function is a **remote** call.
- `chargeToAccount(...)` touches customer accounts, which are **shared across all POSes** in the venue → **remote**. Except in the special single-POS configuration (one installation, possibly a venue without reliable internet), where a settings flag makes the rule not match → the call runs locally, and its saves sync as deltas like everything else.

Both functions live in the same shared module and are called identically everywhere; the per-profile rules and a call-time condition decide the execution plan.

### 1.3 Design principle: partition ownership before forcing `.remote`

The cash-desk prefix is the model to imitate: rather than making document numbering server-authoritative, the ID space is partitioned (one prefix and counter per cash desk) so that local execution is safe. Developers should reach for ownership partitioning first, and reserve `.remote` for state that genuinely cannot be partitioned (cross-installation balances, global sequences, stock reservations).

---

## 2. Goals & Non-Goals

### Goals
1. Single shared domain module compiled into **both** the app target and the server target.
2. **Local by default.** Per-function deviations declared with one macro attribute, co-located with the function. No annotation → no shim, no envelope, no endpoint, no config entry.
3. Profiles are **open-ended**: adding a new profile is a declaration change in the app, not a framework change.
4. Per-profile remote execution, including **conditionally**, resolved at call time from installation configuration.
5. Server endpoint code (routes, request/response codecs) is **generated**, never hand-written — and generated **only** for operations that can actually resolve to `.remote`.

### Non-Goals (v1)
- **Delta sync.** Changelog generation and reconciliation (`changelog_committed`, `sync_index`, entity-subscription index over WebSocket) is the persistence layer's responsibility (Core Data save notifications / MIOPersistentStore) — a separate library. This kit neither generates nor transports deltas.
- Cross-language clients (TypeScript/Kotlin). The wire protocol should not preclude it, but codegen targets Swift only.
- Conflict-resolution policies. Last-writer-wins and single-writer enforcement live in the sync layer (§6.2 notes the contract).
- Distributed transactions spanning local and remote stores in a single call.

---

## 3. Core Concepts

### 3.1 ExecutionMethod

Where a function executes. Binary by design — there is nothing else to decide.

```swift
public enum ExecutionMethod: String, Codable, Sendable {
    /// Execute locally against the local store. Never talks to the server.
    /// Saves are picked up by the persistence layer's delta sync as usual.
    case local

    /// Always execute on the server. The client call is an RPC; the local
    /// store may be updated from the response (read-through).
    case remote
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
    public let method: ExecutionMethod
    /// Evaluated at call time against the installation configuration.
    /// Type-erased at construction from a typed KeyPath.
    public let condition: (@Sendable (any ProfileConfiguration) -> Bool)?
}
```

Since `.local` is the global default, rules almost always declare `.remote`. An explicit `.local` rule is still meaningful as a **conditional exception** placed before a broader rule for the same profile, e.g. `.pos(.local, when: \.isTrainingMode), .pos(.remote)`.

Apps add one line of sugar per profile so rules read naturally at the use site:

```swift
public extension ProfileRule {
    static func pos(_ m: ExecutionMethod) -> ProfileRule { .init(profile: .pos, method: m) }
    static func pos<C: ProfileConfiguration>(_ m: ExecutionMethod, when kp: KeyPath<C, Bool> & Sendable) -> ProfileRule {
        .init(profile: .pos, method: m, when: kp)
    }
    static func manager(_ m: ExecutionMethod) -> ProfileRule { .init(profile: .manager, method: m) }
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

Conditions read this object **at call time**, so flipping a flag in settings changes routing without recompiling.

### 3.5 Resolution

The entire algorithm:

```
1. Runtime override for (operationID, activeProfile) in overrides config?  → use it.   [optional, §3.6]
2. Walk the macro's rules in declaration order.
   First rule whose profile == activeProfile and whose condition
   (if any) evaluates true                                                 → use its method.
3. No match                                                                → .local
```

Order matters and **first match wins**. The macro emits compile errors for unreachable rules (§5.4), so misordering cannot ship.

```swift
public struct ExecutionPlan: Sendable {
    public let method: ExecutionMethod     // total: resolve() always returns .local or .remote
    public let operationID: String         // "AccountService.chargeToAccount(_:)" (+ schema hash, §7.3)
    public let host: RemoteHost            // which server executes it when method == .remote (§3.7)
}
```

### 3.6 Runtime overrides (optional)

A small optional config file remains as an operational escape hatch — forcing a method per operation per profile without recompiling, e.g. while diagnosing a problem in production. It is not required and most apps ship without it:

```json
{
  "overrides": {
    "pos": { "AccountService.chargeToAccount(_:)": "remote" }
  }
}
```

Precedence (highest first): **runtime override > macro rules > `.local`**.

### 3.7 RemoteHost (multi-server routing)

Apps cannot be assumed to talk to a single server: in a micro-server design, different operations belong to different services. `RemoteHost` is the logical name of the server that **owns** an operation — open-ended like `ExecutionProfile`, with one built-in value:

```swift
public struct RemoteHost: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String
    public static let `default` = RemoteHost(rawValue: "default")
}

// Application-side, only in multi-server designs:
public extension RemoteHost {
    static let accounts = RemoteHost(rawValue: "accounts")
    static let billing  = RemoteHost(rawValue: "billing")
}
```

Three rules keep it simple:

- **Declared in code, resolved in config.** The function declares the *logical* host (`host:` in the macro, §5.1); what URL that means is deployment configuration handed to the router at startup (`[RemoteHost: URL]` — the URL may include a path prefix, e.g. `https://api.example.com/billing`). Code never contains addresses.
- **Only meaningful for `.remote`.** A `.local` resolution ignores the host entirely. Single-server apps never mention hosts: everything is `.default`, the router gets one URL, done.
- **A server is the authority for its own hosts only.** `ServerRouter` declares which host(s) it serves (`localHosts`); operations belonging to those resolve `.local` as before, but an operation owned by a *different* host resolves `.remote` even on a server — a server-to-server RPC through the same hosts map a client would use. The single-server case (`localHosts = [.default]`, everything local) falls out unchanged.

An unknown host at execution time (no URL in the deployment config) fails fast with `ProfiledOperationError.unknownHost` — a configuration error, not a network error.

---

## 4. Project Layout

A standard workspace contains three SPM/Xcode targets plus the framework package:

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
        ├── MIOExecutionKit          ← core: macro decls, ExecutionMethod, ExecutionProfile, ProfileRule, router protocols
        ├── MIOExecutionMacros       ← SwiftSyntax macro implementations
        ├── MIOExecutionClient       ← URLSession/WebSocket RPC transport, local store binding
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
/// `host:` names the server that owns the operation (micro-server designs);
/// single-server apps omit it.
@attached(body)
@attached(peer, names: prefixed(__local_), prefixed(__Op_))
public macro ExecutionProfile(
    host: RemoteHost = .default,
    _ rules: ProfileRule...
) = #externalMacro(module: "MIOExecutionMacros", type: "ExecutionProfileMacro")
```

One attribute, variadic rules. The repeated-attribute form (one attribute per profile) is **not possible**: the routing shim makes this a body macro, and SE-0415 allows at most one body macro per function. The variadic form preserves the same per-profile readability in a single attribute.

Name specifiers are explicit (`prefixed(__local_)`, `prefixed(__Op_)`) rather than `arbitrary` — `arbitrary` disables lazy macro expansion module-wide and has scope-lookup restrictions.

### 5.2 Usage — the venue example

```swift
import MIOExecutionKit

public struct DocumentService: ProfiledService {
    let context: ExecutionContext   // injected: store, router, configuration, identity

    /// Each POS owns its CashDesk: own prefix, own counter from 1 → the
    /// sequence is partitioned, local execution is safe. The manager owns
    /// no cash desk → remote call. On the server: no rule matches → local
    /// against PG. The POS needs no rule at all.
    @ExecutionProfile(
        .manager(.remote)
    )
    public func nextDocumentNumber(series: String) async throws -> DocumentNumber {
        try await context.store.performExclusive {
            try $0.incrementSequence(named: "doc.\(context.configuration.cashDeskID).\(series)")
        }
    }
}

public struct AccountService: ProfiledService {
    let context: ExecutionContext

    /// Customer accounts are shared across all POSes in the venue → remote,
    /// owned by the accounts service (in a micro-server deployment; with a
    /// single server, omit `host:`). Single-POS venues flip
    /// `clientAccountSyncRemotely` off in settings: the rule stops matching,
    /// the call runs locally, and its saves reach the server as deltas like
    /// any other local mutation — no recompile, no fallback rule needed.
    @ExecutionProfile(
        host: .accounts,
        .manager(.remote),
        .pos(.remote, when: \PosConfiguration.clientAccountSyncRemotely)
    )
    public func chargeToAccount(_ charge: AccountCharge) async throws -> AccountBalance {
        let number = try await DocumentService(context: context)
            .nextDocumentNumber(series: charge.series)
        // … mutate account, persist receipt …
    }
}
```

Note the composition: on the manager, `chargeToAccount` resolves `.remote` and its inner `nextDocumentNumber` call then executes *on the server*, where it resolves `.local` — each annotated function routes itself, so hybrid behavior falls out naturally. Functions with **no** annotation (the majority) are plain Swift: no shim, no envelope, no endpoint.

### 5.3 What the macro expands to

An important constraint drives the design: **Swift macros are pure syntactic transforms.** They cannot read configuration, cannot see `-D` compilation conditions, and cannot know which target they are being compiled into. Therefore the macro does **not** generate different code per profile. It generates *routing* code, identical in all targets; the linked runtime + installation configuration decide the path. Rule expressions — including `when:` conditions — are copied verbatim into the generated `resolve()` call, never evaluated at expansion time.

Expansion of `chargeToAccount` (conceptually):

```swift
public func chargeToAccount(_ charge: AccountCharge) async throws -> AccountBalance {
    let plan = context.router.resolve(
        operationID: __Op_chargeToAccount.operationID,
        host: __Op_chargeToAccount.host,
        rules: [
            .manager(.remote),
            .pos(.remote, when: \PosConfiguration.clientAccountSyncRemotely)
        ],
        configuration: context.configuration
    )
    switch plan.method {
    case .local:
        return try await __local_chargeToAccount(charge)
    case .remote:
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
    public static let host = RemoteHost.accounts   // omitted when .default
    public let charge: AccountCharge
    public func execute(in ctx: ExecutionContext) async throws -> AccountBalance {
        try await AccountService(context: ctx).__local_chargeToAccount(charge)
    }
}
```

Three artifacts per annotated function:

1. **Router shim** (the rewritten body) — a two-case switch.
2. **`__local_*` peer** carrying the original implementation.
3. **`ProfiledOperation` envelope** — emitted **only if the rule list contains a `.remote` rule** (conditional or not). Local-only annotations (e.g. a conditional `.local` exception) need no wire format. Envelopes and their members are `public` because the generated server routes decode them from another module.

### 5.4 Macro diagnostics (compile errors)

- Function must be `async throws` (remote execution implies both).
- All parameters and the return type must be `Codable & Sendable` — required only when a `.remote` rule is present.
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
                 host: RemoteHost,
                 rules: [ProfileRule],
                 configuration: any ProfileConfiguration) -> ExecutionPlan

    func executeRemote<Op: ProfiledOperation>(
        _ plan: ExecutionPlan, request: Op, as output: Op.Output.Type
    ) async throws -> Op.Output
}

public struct ExecutionContext: Sendable {
    public let profile: ExecutionProfile
    public let configuration: any ProfileConfiguration
    public let router: any ExecutionRouter
    public let store: any PersistentStoreAdapter   // v1: MIOPersistentStore (client) / PG (server)
}
```

Resolution state lives **only** in the router — there is no global registry or singleton. This is what makes the test matrix (§8.4) trivial: a `TestRouter` forcing any plan slots into a test `ExecutionContext` without touching shared state.

- **MIOExecutionClient** ships `ClientRouter`: constructed with the deployment hosts map (`[RemoteHost: URL]`). `.remote` → HTTP/WebSocket RPC to the plan's host (`POST {baseURL}/op/{operationID}` with the envelope JSON); `.local` → run the local body.
- **MIOExecutionServer** ships `ServerRouter`: constructed with the host(s) it serves (`localHosts`, default `[.default]`) plus the URLs of sibling services. Own-host operations resolve `.local` regardless of rules — the server *is* the authority for them. Foreign-host operations resolve `.remote` (server-to-server RPC, §3.7).
- `PersistentStoreAdapter` is deliberately minimal in v1: `performExclusive`, insert/fetch/delete, `incrementSequence`. MIOPersistentStore is the first-class client adapter; Core Data / SwiftData adapters come later.

### 6.2 Relationship to delta sync (out of scope, but adjacent)

Local executions save to the local store; the persistence layer (standard Core Data or MIOPersistentStore) generates changelog deltas from save notifications and a background service reconciles them with the server. None of that involves this kit — a `.local` resolution behaves identically whether or not delta sync is running.

Two contracts at the boundary are worth stating:

- **Single-writer entities.** A conditional rule like the single-POS account case assumes that installation is the only local writer of those entities in its venue. Configuration can lie (a second POS added later, a flag set twice). Enforcement belongs to the sync layer server-side: deltas carry the originating installation (`updatedByAppID`), so the server can reject or quarantine deltas for designated single-writer entity types arriving from more than one installation per venue — never LWW-merge them. This kit's only obligation is encouraging the right declarations; the safety net costs the sync layer one comparison per delta.
- **Read-through.** A `.remote` response may update the local store as a cache; that write must not re-enter the delta pipeline as if it were a local mutation (the persistence layer already distinguishes sync-applied writes — same mechanism).

### 6.3 Transactionality rules

| call shape | local store | server store | guarantee |
|---|---|---|---|
| `.local` | tx commit | — (deltas reconcile later, sync layer) | local ACID |
| `.remote` | optional read-through cache update | tx commit | server ACID; client sees committed result |
| `.local` body calling a `.remote` function | tx commit *after* inner RPC commits | inner op: tx commit | server commits inner op first; if it fails, the outer local tx never commits |

The last row is the main sharp edge developers must understand: when a local function's body calls a remote function, the server-authoritative inner call happens *first*, and a failure there aborts the whole local operation — nothing is persisted locally.

### 6.4 Degraded mode (connectivity loss)

- A single-POS venue with the local-account flag keeps working fully offline by construction — nothing it does resolves `.remote`.
- Any installation that loses connectivity: `.local` operations are unaffected; `.remote` operations **fail fast with a typed error** (`ProfiledOperationError.serverUnreachable`, carrying the unreachable host — in multi-server deployments one service can be down while others work) that the app layer can catch and surface. The framework does not silently downgrade `.remote` to `.local` — if a function should degrade, that is a `when:` condition the developer writes deliberately.

---

## 7. Server Target Code Generation

A SPM **build-tool plugin** (`MIOExecutionGen`) attached to the server target:

1. Parses the shared module's sources with SwiftSyntax, collecting every `@ExecutionProfile` function **whose rule list contains a `.remote` rule** (same visitor logic the macro uses, reused as a library). Conditions are irrelevant to the plugin — a conditional `.remote` means "may be remote," which is enough to require an endpoint. Functions without a `.remote` rule get **no route**: the RPC surface is exactly the set of operations that can legitimately arrive over the wire, nothing more. Operations are **grouped by `host:`**, and each server target declares which host(s) it serves in its plugin configuration — a `billing` server registers only billing-owned operations.
2. Emits `Generated/Routes.swift` registering every operation into an `OperationRegistry`, dispatched by a **single** `/op/:operationID` MIOServerKit route using the **async dispatcher overload** `Endpoint.post` already provides — no `EventLoopPromise` bridging, no semaphores on NIO workers. One route instead of one per operation, deliberately: operationIDs contain `(`, `)`, `:` which routers interpret as pattern syntax, so they travel strictly percent-encoded as a single path *value*, never as route *patterns*:

```swift
// GENERATED — do not edit
import MIOExecutionServer
import MIOServerKit
import MyAppKit

public func registerProfiledOperations(_ router: MIOServerKit.Router,
                                       context: @escaping () -> ExecutionContext) {
    var registry = OperationRegistry()
    registry.register(__Op_chargeToAccount.self)
    registry.register(__Op_nextDocumentNumber.self)
    let operations = registry

    router.endpoint("/op/:operationID").post { (ctx: RouterContext) async throws -> (any Sendable)? in
        let raw: String = try ctx.urlParam("operationID")
        return try await operations.handle(operationID: raw.removingPercentEncoding ?? raw,
                                           body: ctx.bodyAsData() ?? Data(),
                                           context: context())
    }
}
```

3. Emits an `operations-manifest.json` (operationID → host, request/response schema) usable later for non-Swift clients or API docs.

Because the envelope structs generated by the macro already know how to decode and execute themselves, the generated route bodies are uniform one-liners — the plugin never needs to understand business logic or evaluate conditions.

### 7.1 Auth & tenancy

Auth, tenancy (`app_id` / venue), and idempotency keys ride in envelope headers added by `ClientRouter`, validated by a single MIOServerKit middleware — not per-route. Treat every envelope as untrusted input: it executes with full server context. Per-operation *authorization* (which caller may invoke which operation) is middleware policy keyed on `operationID`.

### 7.2 Idempotency

`.remote` retries after a timeout are the dangerous case: the server may have committed (a sequence incremented, an account charged) and the retry would do it twice. v1 requirement, not an option:

- `ClientRouter` attaches an idempotency key per logical call (UUID, reused across retries of the same call).
- The server keeps a dedup table keyed `(app_id, idempotency_key)` storing the serialized response, with a retention window (e.g. 24h), checked by the same middleware. A hit replays the stored response without re-executing.

### 7.3 Operation identity & versioning

`operationID` is the type name plus the **full function signature with argument labels** — `AccountService.chargeToAccount(_:)` — so overloads cannot collide, suffixed with a short schema hash of the parameter and return types: `AccountService.chargeToAccount(_:)@a1b2c3`. An old client calling a changed signature gets an immediate 404-class failure instead of decoding garbage. The manifest records the hash inputs for diffing across releases.

---

## 8. Open Questions

1. **Condition expression form** — `when:` as a typed `KeyPath` (shown throughout) type-checks cleanly in attribute position; an `@autoclosure () -> Bool` referencing instance members (e.g. `configuration.flag`) may not, since attribute arguments are type-checked in the enclosing context. Needs a toolchain spike in phase 2; the KeyPath form is the safe default, closures remain attractive for composite conditions.
2. **Body macros toolchain floor** — `@attached(body)` (SE-0415) sets the minimum toolchain. Swift 6 is already the target, so the floor is accepted; verify the exact minimum during phase 2. Constraint to remember: only one body macro per function, so `@ExecutionProfile` cannot compose with another body-rewriting macro.
3. **Per-profile compile-time pruning** — since macros can't see the target, `__local_*` bodies of server-only functions still compile into thin clients (code size / secrecy). Option: a second `MIOExecutionGen` pass for the client target that strips them.
4. **Testing profile matrix** — provide a `TestRouter` that forces any plan and a `TestConfiguration`, so the same XCTest suite runs each annotated function under both methods and both condition branches.
5. **Plugin sandbox** — `MIOExecutionGen` must read the shared package's sources from the server target's plugin. SPM allows cross-package reads in the sandbox for local packages; pin this assumption in the first phase-3 spike, it is the part most likely to fight SPM.
6. **Streaming / non-Codable returns** — out of scope v1; consider `AsyncThrowingStream` support over WebSocket later.
7. **Service-to-service auth** — cross-host calls from `ServerRouter` (§3.7) need a service identity (not a user/installation identity) in the envelope headers; decide the scheme (shared secret, mTLS, signed tokens) before phase 4's middleware.

---

## 9. Roadmap

| Phase | Deliverable |
|---|---|
| 1 | `MIOExecutionKit` core types (`ExecutionMethod`, `ExecutionProfile`, `ProfileRule`, resolution) + `ClientRouter`/`ServerRouter`/`TestRouter` with **hand-written** envelopes; prove the venue flow end-to-end without macros, including a call-time condition flip |
| 2 | `ExecutionProfileMacro` (body + peer expansion, diagnostics incl. unreachable-rule, `when:` spike) replacing the hand-written envelopes |
| 3 | `MIOExecutionGen` build-tool plugin → generated MIOServerKit routes (`.remote`-capable ops only) + manifest + schema-hash operation IDs |
| 4 | Idempotency dedup table + auth/tenancy middleware; read-through cache updates without re-entering the delta pipeline |
| 5 | Runtime overrides config, degraded-mode errors, client-side pruning pass, docs |
