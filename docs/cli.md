# CLI packaging contract — one `hanzo`, bundled by `@hanzo/cli`

Decomplect for the four colliding `hanzo` binaries (see README §"CLI
decomplect"). This is the contract; the cross-platform release build + install
script are owned by the release effort — implement against this.

## Canonical

- **`hanzo` = the Rust `hanzo-cli`** (crate at `~/work/hanzo/cli`, `[[bin]]
  name = "hanzo"`). One native binary. It owns human-facing verbs and absorbs
  the Go `cloud/cmd/hanzo` *control* verbs (login/apps/deploy/clusters/gpu/
  build) as subcommands that call the cloud API via the generated Go SDK.
- The Go binary keeps only its **server** role; it is named `cloud`/`hanzod`
  and MUST NOT install as `hanzo`.

## npm delivery — `@hanzo/cli`

Thin package that ships the prebuilt Rust `hanzo` per platform (esbuild/swc
model), NOT a JS reimplementation.

- Package name: **`@hanzo/cli`** (move off the orphaned `@hanzoai/cli`). The TS
  SDK currently at `@hanzo/cli` (`~/work/hanzo/sdk`) renames to `@hanzo/sdk`.
- `"bin": { "hanzo": "bin/hanzo" }` — the ONLY package providing `hanzo`.
- Delivery: `optionalDependencies` per-platform packages
  `@hanzo/cli-{darwin-arm64,darwin-x64,linux-x64,linux-arm64,win32-x64}`, each
  shipping the matching prebuilt binary; `bin/hanzo` resolves the platform pkg.
  Fallback: `postinstall` downloads
  `https://github.com/hanzoai/cli/releases/download/v<version>/hanzo-<platform>`
  (the pattern install.js already uses). Never build from source on user
  machines by default.

## Siblings (keep, de-collide)

- **`@hanzo/dev`** (Rust codex fork, bin `dev`) — remove its stray `hanzo` bin
  alias so only `@hanzo/cli` owns `hanzo`. Rust crate `hanzo-dev`.
- **`@hanzo/mcp`** (bin `hanzo-mcp`) — keep. PyPI `hanzo-mcp` (`uvx hanzo-mcp`)
  and the `~/work/hanzo/mcp` `rust/`+`go/` natives stay.

## Rust-native equivalents

`hanzo` (crate `hanzo-cli`), `dev` (crate `hanzo-dev`), MCP (`~/work/hanzo/mcp/
rust`). npm packages are thin bundlers over these; crates.io ships the natives.

## Publish targets (set up, do not auto-publish)

crates.io: `hanzo-cli`, `hanzo-dev`. npm: `@hanzo/cli` (+ platform subpkgs),
`@hanzo/dev`, `@hanzo/mcp`. PyPI: `hanzo-mcp`, `hanzo-dev`.
