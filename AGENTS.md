# Repository Guidelines

## Agent Docs Location

- Root agent guide: `AGENTS.md`
- Detailed agent docs: `codex/agent-docs/` (e.g. `codex/agent-docs/git.md`)

## Project Structure & Module Organization

- `Package.swift`: Swift Package Manager (SPM) manifest for the `Alfy` library and its test target.
- `Sources/`: Library source code, organized by feature folders (e.g. `Network/`, `Database/`, `Components/`, `ViewModifiers/`).
- `Tests/`: XCTest-based unit tests for the package (e.g. `Tests/CachedURLSession+Tests.swift`).
- `.swiftpm/` and `Package.resolved`: SPM metadata and pinned dependency versions.

## Build, Test, and Development Commands

- `swift build`: Builds the `Alfy` library target.
- `swift test`: Builds and runs the unit test suite.
- `swift test -q`: Quieter test output (useful in CI/logs).

This repo is an SPM package; most development workflows also work directly from Xcode by opening the folder.

## Coding Style & Naming Conventions

- Language: Swift.
- Indentation: 4 spaces; follow Xcode’s default formatting.
- Naming: types/protocols in `UpperCamelCase`, functions/vars in `lowerCamelCase`, acronyms capitalized consistently (e.g. `URLSession`, `HTTPURLResponse`).
- Prefer small, focused changes and avoid reformatting unrelated code. If you introduce multi-argument calls, format them consistently (one argument per line when it improves readability).

## Testing Guidelines

- Framework: `XCTest` with async/await tests where appropriate.
- Naming: test methods use `test…` prefixes and describe behavior (e.g. `testUseProtocolCachePolicyWithTTLExpiresAndRefetches`).
- Prefer deterministic tests: stub network via `URLProtocol` and avoid real network I/O.

Run tests locally with `swift test` before opening a PR.

## Commit & Pull Request Guidelines

- Commit messages in history are short and lowercase (e.g. `fix`, `added`, `missing check`). Keep messages concise and action-oriented.
- PRs should include: a brief summary, rationale, and how to verify (commands or steps). If behavior changes, add/adjust tests in `Tests/`.

## Notes for Agents/Automation

- Keep edits scoped to the requested change, do not stage files unless asked, and prefer `swift test` to validate.
- Before finishing a prompt/skill task, build the project (`swift build`) and fix any build failures introduced by the change.
