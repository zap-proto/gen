# zap-proto/gen — Hanzo SDK generation, one way

> Status: **ADR-0001 (accepted).** This README *is* the architecture decision
> record for how every Hanzo client SDK is produced. It is the one and only
> way. If you are about to hand-write or hand-edit a client for a Hanzo
> service in any language, stop — generate it here instead.

## Decision

**Every Hanzo client SDK is generated from a canonical `.zap` schema by
`zapgen`. ZAP-native transport is primary; HTTP/WS/SSE is a generated
fallback view of the same schema. No hand-written service clients.**

- **Source of truth:** the service's `.zap` schema (canonical zapgen grammar).
- **Generator:** `zapgen` (github.com/zap-proto/js `src/zapgen`, canonical Go
  port at github.com/zap-proto/go `cmd/zapgen`). One tool, one grammar.
- **One client, one seam, a swappable transport — in two tiers:**
  - **Tier 1 (universal, ships today, all 7 languages):** a generated
    OpenAPI/HTTP client whose transport is swappable. `zapgen --emit=openapi`
    emits an OpenAPI 3.1 doc from the `.zap` (each method → `POST
    /<service>/<method>`, the exact route `zip`/`@zap-proto/http` serves). The
    **transport** is ZAP-native by default (`zap-proto/http` =
    "HTTP-semantics over ZAP TCP frames on :9999", via `zapd` or direct;
    `zaphttp.NewTransport(host)` drops straight into a stock `http.Client`) and
    falls back to plain HTTPS/WS/SSE. Same typed surface, same code — only the
    transport differs. This is exactly "ZAP-native primary, WS/HTTPS/SSE
    fallback."
  - **Tier 2 (zero-copy fast path, where a runtime + emit backend exist):**
    `zapgen` also emits, per language, a zero-copy `View`/`Builder` per struct
    and a typed `Client`/`Server` over the native-ZAP `service+method` envelope.
    This is the binary fast path layered on the *same* transport. Reference:
    TS (`js/src/zapgen/emit.ts`). Go native-emit exists upstream
    (`zap-proto/go/cmd/zapgen`).
- **Both tiers read one `.zap`.** Tier 1 gives every language a working
  ZAP-primary client now; Tier 2 upgrades hot paths to zero-copy where the
  runtime is ready. Nothing is hand-written; nothing can drift from the schema.

This is orthogonal (types vs operations vs transport are three separable
concerns), composable (any channel plugs into any generated client), complete
(the OpenAPI view and the native client come from one schema and cannot
drift), and DRY (one grammar, one generator, per-language runtimes already
exist in the zap-proto org).

## Why (the drift this kills)

Today the Hanzo gateway SDKs (`hanzoai` py/go/js) are Stainless-generated from
an OpenAPI spec and drifting (go 8wk, js 3mo stale); `tasks/schema/tasks.zap`
and ~11 sibling core-service schemas are **hand-written sketches that nothing
compiles** — so the red-review found the wire "lies": the schema declares
per-field ZAP structs while the Go transport actually ships a single JSON blob
in a generic `{body,status,error}` envelope. Four incompatible `.zap` dialects
exist across the tree. The fix is not "regenerate more often" — it is to make
**one schema mechanically produce every surface** so there is nothing to drift.

## Two things are called "ZAP" — pick the one the live services use

Be precise or you will generate against the wrong wire:

- **Universe A — rebranded Cap'n Proto** (`zap-proto/rust` `zapc`=capnpc-rust,
  `zap-proto/cpp`): full capnp interface-id RPC stubs with promise pipelining.
  Real for Rust and C++. Go's `capnpc-go` output is present but **archived/
  disabled** (`//go:build never`); Ruby is capnp struct-only (no RPC); Python's
  pycapnp client is **stubbed/mock**. This is *not* the wire the live Hanzo
  services speak.
- **Universe B — native ZAP** (16-byte `ZAP\0` header): what the **live** Hanzo
  services actually run. Dispatch is by `service+method` **string** (no numeric
  opcode). Served by `zip` over `zap-proto/http`. Codegen is `zapgen`
  (TS + OpenAPI today; Go upstream). Runtimes: `zap-proto/go` (live),
  `@zap-proto/zap` (TS), `luxfi/zap`, Python `hanzo-zap`.

**This tool targets Universe B** (the live services) and the OpenAPI view of it.
Universe A (capnp zero-copy RPC in Rust/C++) is a valid future Tier-2 upgrade
for those two languages, but it rides a *different wire* and must not be mixed
into the same client. Today the one contract that spans **every** Hanzo service
is the OpenAPI 3.1 doc `zip` publishes at `/.well-known/openapi.json` (mirrored
as MCP `tools/list`) — Tier 1 consumes exactly that.

## Canonical `.zap` grammar (the only dialect)

`zapgen` accepts exactly this (brace **or** offside/indented body — both are
desugared to the same AST):

```zap
package tasks

# @openapi:version 1.0.0
# @openapi:server  https://api.hanzo.ai/v1

type id32 = bytes_fixed[32]

struct StartWorkflowRequest {
  namespace     text  @0
  workflowId    text  @8
  input         bytes @16
}

struct StartWorkflowResponse {
  runId text @0
}

interface Tasks {
  startWorkflow(req: StartWorkflowRequest) returns (resp: StartWorkflowResponse)
  health() returns (resp: HealthResponse)
}
```

Rules that make the existing Hanzo sketches non-conformant (and how to conform
them — this is mechanical, see `schemas/CONFORMANCE.md`):

| Sketch dialect (`tasks.zap`) | Canonical zapgen | Conform by |
|---|---|---|
| no `package` line | `package <name>` required first | add it |
| `field Text` (no offset) | `field text @<byteoffset>` | assign explicit offsets |
| `Text`/`Bytes` (capnp case) | `text`/`bytes` (lowercase) | lowercase primitives |
| `List(Payload)` | `list<Payload>` | angle brackets, lowercase `list` |
| `m (a) -> (b)` | `m(a: A) returns (b: B)` | `returns` + `:`-typed params |
| `enum` / union | not in v1 grammar | model as `u8` + doc, or defer |

Offsets are author-controlled and **append-only**: adding a field never
renumbers existing ones (stable wire compat). Method ordinals auto-assign
1,2,3… by declaration order — appending a method never shifts an existing one.

## Per-language plan & status

Runtimes already exist in the zap-proto org for most targets; `zapgen` needs an
emit backend per language (the TS backend is the reference at
`js/src/zapgen/emit.ts`). HTTP-fallback clients are generated from the
`zapgen` OpenAPI via best-in-class per-language generators (or Stainless for
the incumbent gateway SDKs).

Tier 1 (OpenAPI/HTTP client + ZAP-native transport) is available for every
language now. Tier 2 (zapgen zero-copy native client) is gated on a native-ZAP
runtime **and** a zapgen emit backend.

| Lang | Tier-1 HTTP client (gen) | ZAP-native transport (Tier 1) | Tier-2 zero-copy (`zapgen` native) | Status |
|---|---|---|---|---|
| **go** | oapi-codegen / Stainless | `zap-proto/http` `NewTransport` → `http.Client` | Go zapgen (upstream; vendor it) | **priority-1 proof** |
| **rust** | progenitor | `zap-proto/rust` stream transport | capnp RPC (Universe A) — separate wire | **priority-1 proof (Tier 1)** |
| **python** | openapi-python-client / Stainless (`hanzoai`) | `hanzo-zap` `CloudClient` | add `emit-python` (later) | **priority-1 proof (Tier 1)** |
| **typescript** | openapi-typescript | `@zap-proto/zap` TCP + WS | **exists** (`emit.ts`) | **Tier-2 real** |
| **c++** | openapi-generator (cpp) | `zap-proto/http` | capnp RPC (Universe A) | scaffold |
| **ruby** | openapi-generator (ruby) | via `zap-proto/http` bridge | none (capnp struct-only) | scaffold (Tier 1) |
| **php** | openapi-generator (php) | HTTP/WS/SSE only | none (no runtime) | **fallback-only** |

Honest rule: **Tier 1 is the deliverable that makes "all 7 languages" real and
mechanical today** — one OpenAPI, seven idiomatic clients, ZAP-native transport
where a native transport exists (go/rust/ts/cpp via `zap-proto/http`; python via
`hanzo-zap`) and HTTPS/WS/SSE otherwise (php, ruby until the bridge lands).
Tier 2 (zero-copy) is TS today, Go next.

## Python back-compat (non-negotiable)

`hanzoai` (PyPI, real users) keeps its public surface **byte-for-byte**: same
`import hanzoai`, same `Hanzo(...)`/`AsyncHanzo(...)` signature, same resource
namespaces (`client.chat.completions.create`, …), same `__all__`. ZAP-native is
added **under** the client as an optional transport that routes through the
already-shipping `hanzo_zap.CloudClient` (`connect()/call()`), selected by
config, defaulting to the current httpx HTTP path. Nothing in the public API
changes; ZAP becomes an opt-in acceleration. Proof: import + `/v1/models` smoke
+ `__all__` diff == empty. See `docs/python-compat.md`.

## CLI decomplect (four `hanzo` binaries → one)

Today four binaries claim the name `hanzo` (Go `cloud/cmd/hanzo`, Rust
`cli/` via `@hanzoai/cli`, JS `sdk/` via `@hanzo/cli`, Rust `dev/dev-cli` via
`@hanzo/dev`). Decision:

- **`hanzo` = the Rust `hanzo-cli`** (one native binary, canonical). It owns the
  human-facing verbs; the Go `cloud/cmd/hanzo` **control** verbs
  (login/apps/deploy/clusters/gpu/build) move in as subcommands that call the
  cloud API through the generated Go SDK. The Go binary keeps only its
  **server** role and is named for it (`cloud`/`hanzod`), never `hanzo`.
- **`@hanzo/cli`** (npm) bundles the Rust `hanzo` binary per platform
  (download-on-install from the CLI release assets, esbuild/swc-style). The Rust
  CLI's npm identity moves from the orphaned `@hanzoai/cli` to `@hanzo/cli`
  (org convention). The TS SDK currently squatting `@hanzo/cli` becomes
  `@hanzo/sdk`.
- **`@hanzo/dev`** (dev agent, bin `dev`) and **`@hanzo/mcp`** (bin
  `hanzo-mcp`) already exist and are kept; remove their stray `hanzo` bin
  aliases so only `@hanzo/cli` provides `hanzo`. Rust-native equivalents:
  crate `hanzo-cli` (bin `hanzo`), crate `hanzo-dev` (bin `dev`), MCP `rust/`.

## How to run (reproducible)

```bash
# one language from one schema (ZAP-native + OpenAPI fallback)
bin/zapsdk go     schemas/tasks.zap
bin/zapsdk python schemas/tasks.zap
bin/zapsdk ts     schemas/tasks.zap

# every language for every schema
bin/zapsdk all
```

`bin/zapsdk` is the thin driver: it calls `zapgen --emit=ts,openapi` (and the
per-language emit backend), generates the HTTP-fallback client from the emitted
OpenAPI, drops the "generated from ZAP — do not hand-edit" header + the
regenerate command into every file, and assembles the language package on top
of the matching zap-proto runtime. The language matrix + per-schema status live
in `sdks.json`.

## Finish path

1. Land the `emit-python`, `emit-rust`, `emit-cpp`, `emit-ruby` backends in
   `zapgen` (mirror `emit.ts`).
2. Conform the ~12 core-service `.zap` schemas (`schemas/CONFORMANCE.md`) and
   move them to their services as the committed source of truth.
3. Wire the two `XChannel` implementations per language (ZAP-native runtime +
   HTTP/WS/SSE) and commit the generated SDKs into `hanzoai/{go,rust,python}-sdk`
   with the do-not-edit header.
4. Stand up a `zap-proto/php` runtime (or keep php fallback-only).
5. Publish: crates.io (`zap-*`, `hanzo-*`), PyPI (`hanzoai`), npm (`@hanzo/*`),
   packagist (php). Set up, do not auto-publish.
