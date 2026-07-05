# Conforming a Hanzo `.zap` sketch to canonical grammar

71 of 73 Hanzo `.zap` files are written in a **sketch dialect** that no compiler
accepts (no `package`, no field offsets, capnp-cased types, `List(T)`, `->`
methods). `zapgen` is the one compiler; this is the mechanical rewrite that
makes a sketch compile. It is deterministic — one way.

## The six rewrites

| # | Sketch | Canonical | Note |
|---|---|---|---|
| 1 | *(no header)* | `package <service>` on line 1 | required; lowercase service name |
| 2 | `workflowId Text` | `workflowId text @0` | lowercase type; add explicit byte offset |
| 3 | `metadata Bytes` | `metadata bytes @N` | `Bytes`→`bytes`, `Text`→`text`, etc. |
| 4 | `items List(Payload)` | `items list<Payload> @N` | `List(T)`→`list<T>` |
| 5 | `m (req X) -> (resp Y)` | `m(req: X) returns (resp: Y)` | `:`-typed params; `returns` keyword |
| 6 | `enum E { a b c }` | model as `u8 @N` + doc the values | v1 grammar has no enum; append later |

## Assigning offsets (rewrite #2)

Offsets are **author-controlled, append-only, non-overlapping**. Fixed section
slot sizes: bool/u8/i8=1, u16/i16=2, u32/i32/f32=4, u64/i64/f64=8,
text/bytes/list=8 (relOff+len), nested struct=4 (relOff), `bytes_fixed[N]`=N.
Lay fields out in declaration order at natural alignment; never renumber an
existing field when appending (that is the wire-stability guarantee). `zapgen`
validates non-overlap and fails loudly on a mistake.

## Worked example — `tasks.zap`

Sketch (hanzoai/tasks/schema/tasks.zap):

```
struct Payload
  metadata Bytes
  data Bytes

interface Tasks
  startWorkflow (req StartWorkflowRequest) -> (resp StartWorkflowResponse)
  health () -> (service Text, status Text)
```

Conformed (this repo's `schemas/tasks.zap` — compiles with `zapgen`):

```zap
package tasks

struct Payload {
  metadata bytes @0
  data     bytes @8
}

struct HealthResponse {
  service text @0
  status  text @8
}

interface Tasks {
  startWorkflow(req: StartWorkflowRequest) returns (resp: StartWorkflowResponse)
  health() returns (resp: HealthResponse)
}
```

Note rewrite #5 also folds a multi-value return (`-> (service Text, status
Text)`) into a single response struct (`HealthResponse`) — a ZAP method carries
exactly one struct payload per direction.

## After conforming

The conformed `.zap` becomes the committed source of truth in the service repo
(`<service>/schema/<service>.zap`), and `bin/zapsdk <lang> <service>.zap`
regenerates every client. Verify parity: `zapgen --emit=openapi` output must
match what the service's `zip` app serves at `/.well-known/openapi.json`.
