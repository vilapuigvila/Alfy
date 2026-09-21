# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`Alfy` is a Swift Package Manager library of reusable helpers the author shares across their own
iOS/macOS projects (networking, caching, SwiftData persistence, UserDefaults, small SwiftUI
components/modifiers). It is a grab-bag utility library, not an application — there is no single
cohesive feature to reason about; each folder under `Sources/` is a mostly independent subsystem.

See `AGENTS.md` for coding style, commit/PR conventions, and the git branching workflow
(`codex/agent-docs/git.md`) — this file focuses on build/test commands and architecture that spans
multiple files.

## Commands

```bash
swift build          # build the Alfy library target
swift test            # build and run the full XCTest suite
swift test -q          # quieter output, useful in CI/logs

# Run a single test class or method:
swift test --filter CachedURLSessionTests
swift test --filter CachedURLSessionTests/testCachesGETResponsesAndServesHit
```

Before finishing a task: run `swift build` and fix any build failures it introduces, and prefer
`swift test` to validate behavior changes (per `AGENTS.md`).

## Platform targets and availability gating

`Package.swift` declares `.iOS(.v17), .macOS(.v11)`, but not all code supports both platforms
equally:

- `Sources/Database/*` (SwiftData) is wrapped in `#if canImport(SwiftData)` and marked
  `@available(iOS 17, macOS 14, *)` — on macOS < 14 the whole `DatabaseManager` type collapses to
  an empty stub (see the `#else` branch in `DatabaseManager.swift` /
  `DatabaseManagerProtocol.swift`).
- UIKit-only code (`Sources/Components/SparkView.swift`,
  `Sources/ViewModifiers/UIApplication.Notification.swift`) is wrapped in `#if canImport(UIKit)`
  with a macOS-safe fallback (a no-op view / no-op modifier body).

When touching these files, preserve the `#if canImport(...)` / `#else` stub pattern rather than
assuming iOS-only or dropping macOS support.

## Networking stack (`Sources/Network/`)

Three pieces work together:

- **`Requester`** — the public, static call-site API (`Requester.request(...)`,
  `Requester.makeRequest(urlString).header(...).ttl(...).send()`). It only issues `GET` requests,
  builds a `URLRequest`, and stamps per-request cache overrides onto it via
  `URLProtocol.setProperty(_:forKey:in:)` using the private keys `AlfyAllowStaleOnError`,
  `AlfyCacheControlBehavior`, `AlfyBypassCache`. It checks `NetworkStatusMonitor.shared.hasConnection`
  before building the request and throws `Requester.ErrorReason.noInternetConnection` if offline.
- **`CachedURLSession`** — an `actor` singleton (`CachedURLSession.shared`, configured once via
  `Requester.configureCache(...)` / `CachedURLSession.configure(...)`) that layers disk+memory
  caching over a wrapped `URLSession`. It reads back the per-request overrides `Requester` set via
  `URLProtocol.property(forKey:in:)`. Cache entries are keyed by `sha256("GET <url>")`, stored as
  binary plists under `Caches/<cacheNamespace>/`, and expiry is derived from
  `Cache-Control: max-age` / `Expires` headers when `cacheControlBehavior == .respectServer`, else
  from the configured TTL. In-flight requests for the same key are deduplicated
  (`inflight: [String: Task<...>]`). Responses carry a synthetic `X-Cache: HIT|MISS|STALE` header —
  tests assert on this header rather than reaching into cache internals.
- **`NetworkStatusMonitor`** — wraps `NWPathMonitor` behind a singleton with a Combine
  `statusChanged` publisher; `Requester` consults it before every request.

Tests for the cache (`Tests/CachedURLSession+Tests.swift`) construct an isolated
`CachedURLSession` with a stub `URLProtocol` (`TestURLProtocol`) and a dedicated cache namespace —
follow that pattern (don't hit the real network or the shared singleton's cache directory) for any
new networking tests.

## SwiftData persistence (`Sources/Database/`)

`DatabaseManager` is a singleton that must be explicitly created once via
`DatabaseManager.makeShared([YourModel.Type, ...])` (asserts if called twice) before any code
accesses `DatabaseManager.shared`. It conforms to `DatabaseManagerProtocol`, which exists so
consuming apps can inject a fake in tests.

`RequestThrottleController` also lives in `Sources/Database/` despite being a generic
non-persistence rate limiter (tracks `lastRequestDate` and grants a limited number of "extra"
requests after a failure, resetting once the minimum interval has elapsed again) — it isn't
SwiftData-related, just co-located there.

## UserDefaults wrapper (`Sources/UserDefaults/UserPreferences.swift`)

A single file containing a full mini-module: the `@UserDefault` property wrapper (generic over
`Codable`), `UserDefaultPublisher` (Combine projection with `reset()`/`peek()`/`remove()`),
`UserDefaultsStorageProtocol` + `UserDefaultsStorage` (for swapping in a mock in tests, see
`MockUserDefaultsStorage` in `Tests/UserPreferences+Tests.swift`), and `UserDefaultOperations` /
`UserDefaultLogger` internals. Reads/writes go through `JSONEncoder`/`JSONDecoder`, so wrapped
types must be `Codable`, not just property-list-compatible.

## Everything else

`Sources/Extensions/`, `Sources/ViewModifiers/`, `Sources/Components/`, `Sources/Types/` are small,
independent, single-purpose files (e.g. `EquatableError` for wrapping non-Equatable `Error`s in
`Equatable` contexts, `Date+Ext`/`Data+Ext` convenience helpers, `onAppLifecycleEvent` /
`onAppear(action:)` SwiftUI modifiers). There's no cross-file architecture to learn here beyond
what's in each file.
