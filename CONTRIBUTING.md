# Contributing to livesplit-one-macos

Thanks for your interest in contributing. This guide covers how to set up a
development environment and the conventions every change follows.

## Before you start

- All work is tracked in the
  [issues](https://github.com/alexcosta97/livesplit-one-macos/issues), and
  every pull request must link one, except Renovate's dependency updates. If
  there's no issue for what you want to do, open one first with the matching
  template: **Task** for a well-defined piece of work, **Feature request** for
  a new idea, or **Bug report** for something that doesn't work.
- For anything beyond a small fix, comment on the issue before starting, so
  the approach can be agreed first.
- The design is described in
  [the design spec](docs/superpowers/specs/2026-10-09-livesplit-one-macos-design.md).
  Changes that alter the design update the spec in the same pull request.

## Development setup

The app is Swift and AppKit, built with Xcode. livesplit-core is linked
through a Rust static library in `core/`, and its Swift bindings are generated
into the `LiveSplitCore/` Xcode static library target. The Xcode project is
generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen)
and is not committed.

1. Install Xcode 26.6 or newer from the App Store (the version CI uses is
   set in `.github/actions/select-xcode/action.yml`). Then run
   `sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer`.
   Xcode includes `swift format`, which the checks use.
2. Install [rustup](https://rustup.rs/) and [mise](https://mise.jdx.dev/),
   then run `mise install` in the repository. Rust's version and targets come
   from `rust-toolchain.toml`. mise installs XcodeGen, git-cliff, shellcheck
   and actionlint.
3. Build `core/` and generate the Xcode project:

   ```sh
   scripts/build-core.sh
   xcodegen generate
   ```

   `xcodegen generate` runs `scripts/build-core.sh --bindings-only`, and
   building in Xcode runs `scripts/build-core.sh`, which builds `core/` with
   Cargo and regenerates livesplit-core's Swift bindings when needed. The
   first build downloads and compiles livesplit-core and takes a few minutes.

   Open the generated `LiveSplitOne.xcodeproj` in Xcode. The project is
   generated from `project.yml` and never committed: run `xcodegen generate`
   again after pulling changes to it.
4. Before pushing, run the same checks CI runs, from the repository root:

   ```sh
   cargo fmt --check --manifest-path core/Cargo.toml
   cargo clippy --all-targets --locked --manifest-path core/Cargo.toml -- -D warnings
   cargo test --locked --manifest-path core/Cargo.toml
   swift format lint --strict --recursive App Tests LiveSplitCore/Wrapper scripts
   mise x -- actionlint
   mise x -- shellcheck scripts/*.sh scripts/release/*.sh
   xcodegen generate
   xcodebuild test -project LiveSplitOne.xcodeproj -scheme LiveSplitOne -destination 'platform=macOS'
   scripts/build-app.sh 0.0.0-dev
   ```

   `actionlint` also runs shellcheck on the workflows' `run:` steps.
   `scripts/build-app.sh` makes the universal release build CI's `build`
   check makes, into `dist/`.

   For the release scripts and workflow linting, run
   `scripts/release/test-release-scripts.sh` and `actionlint` with the tools
   from `mise install`. The same tests run on pull requests that change
   release files.

## Testing

Tests follow a pyramid: many fast tests at the bottom, fewer integration
tests, and a small end-to-end (E2E) suite at the top. Spec §14 has the full
description, including the E2E harness and the list of E2E flows.

| Kind | Tooling | What it covers |
|---|---|---|
| **Unit** | Swift Testing; `cargo test` for `core/` | One function or type, called directly |
| **Headless UI** | Swift Testing, with views and view controllers but no window | One view: actions on it, then checks on its accessibility tree and what it asks the app to do |
| **Integration** | Swift Testing with the real livesplit-core and an in-process fake server | Modules working together, with no user flow, through their APIs |
| **E2E** | XCUITest | The whole app as a user uses it |

E2E tests drive the app **only** through user input to the window (clicks,
right-clicks, typing, keys, resizing, files the user picks) and check **only**
what the user can observe (what the window shows, what the fake server
receives, files on disk).

Rough proportions by count: 70–80 % unit and headless UI, 15–25 %
integration, under 10 % E2E.

- A bug found at a higher level gets a test at the lowest level that can catch
  it.
- Every pull request that changes the app adds tests at each level the change
  needs, including an E2E test for a new or changed user flow.

## User documentation

Until the wiki exists (spec §16, a backlog item), the user documentation is
[`README.md`](README.md).

- A pull request that changes something users can see updates the
  documentation in the same pull request.
- If a screen in a screenshot changes, say in the pull request which
  screenshots need retaking.

## Commits

### Conventional Commits

Every commit message follows
[Conventional Commits](https://www.conventionalcommits.org/):

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

| Type | Use for | Effect on the next version |
|---|---|---|
| `feat` | A new feature for users | Minor |
| `fix` | A bug fix for users | Patch |
| `perf` | A performance improvement | Patch |
| `refactor` | A code change that neither fixes a bug nor adds a feature | None |
| `docs` | Documentation only | None |
| `test` | Adding or changing tests | None |
| `build` | Build system or dependencies | None |
| `ci` | CI configuration and workflows | None |
| `style` | Formatting only, no code change | None |
| `chore` | Anything else that doesn't affect users | None |

- The description is in the imperative mood and lowercase, with no full stop:
  `feat: add always on top`, not `Added always on top.`
- A scope is optional and names the affected area: `fix(server): …`,
  `feat(splits-editor): …`.
- A **breaking change** is marked with `!` after the type or scope
  (`feat!: …`), or a `BREAKING CHANGE:` footer describing it. Until version
  1.0.0, breaking changes bump the minor version.

### Signed commits

All commits must be signed, and `main` rejects unsigned ones. Signing with an
SSH key is the simplest option:

```sh
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/id_ed25519.pub
git config --global commit.gpgsign true
```

Then add the same public key to your GitHub account as a **signing key**
(Settings → SSH and GPG keys → New SSH key → Key type: Signing Key). GitHub's
documentation on
[commit signature verification](https://docs.github.com/en/authentication/managing-commit-signature-verification)
covers GPG and other options.

## Branches

Name branches `<type>/<short-description>`, using the commit types above, for
example `feat/always-on-top` or `fix/reconnect-state`.

## Pull requests

- **Title:** a Conventional Commit, like a commit message. Pull requests are
  squash-merged, and the title becomes the commit on `main`, so it determines
  the next version.
- **Description:** fill in the pull request template. It asks for the issue
  the pull request resolves (`Closes #123`), what changed and why, how it was
  tested, and a short checklist.
- **Scope:** one logical change per pull request.
- **Requirements to merge:**
  - all CI checks pass, on macOS: formatting and linting for Rust and Swift,
    the Rust tests, the unit, headless UI and integration tests, the E2E
    suite, a release build of the universal app, and the Conventional Commits
    check on the title and every commit;
  - all review conversations are resolved;
  - all commits are signed.
- **Merging:** only maintainers can merge into `main`, using squash merge.
  The branch is deleted after merging.

## Dependency updates

[Renovate](https://docs.renovatebot.com/) opens pull requests every week to
update dependencies, configured in `renovate.json`. Their titles follow the
conventions above, and the type decides whether the update is released:

- `fix(deps)`: crates that ship in the app, including the LiveSplit crates
  (grouped together and labelled `livesplit`) and `Cargo.lock` refreshes, and
  Swift packages that ship in the app. These produce a release.
- `ci(deps)`: GitHub Actions. No release.
- `chore(deps)`: tools pinned in `mise.toml` and development-only packages.
  No release.

Renovate's pull requests are the one exception to the linked-issue rule. They
go through the same checks and are merged by a maintainer like any other pull
request. The Dependency Dashboard issue lists pending updates.

## Releases

Releases are automated. There is no manual version bump and no
`CHANGELOG.md`: the version and release notes come from the commits. The
version is embedded in the app at build time, as `CFBundleShortVersionString`.

- The version follows [Semantic Versioning](https://semver.org/) and is
  calculated from the commits since the last full release, starting at
  `0.1.0`. The largest change wins: a breaking change bumps major (minor
  before 1.0.0), otherwise a `feat` bumps minor, otherwise a `fix` or `perf`
  bumps patch. Commits of the other types alone don't produce a release.
- Every merge to `main` that produces a version publishes a **release
  candidate** as a GitHub pre-release, tagged `vX.Y.Z-rc.N`.
- A maintainer promotes a release candidate by approving the pending release
  job in the `release` environment. That publishes the full release `vX.Y.Z`
  from the same commit, marked **Latest**.
- The release is a universal (Apple Silicon and Intel) `.app` in a `.zip`,
  ad-hoc signed and not notarised, so users open it once with System Settings
  → Privacy & Security → Open Anyway.
- Release notes list every change since the previous full release, grouped by
  type. They are the project's changelog.

## License

By contributing, you agree that your contributions are dual licensed under
the MIT and Apache-2.0 licenses, as described in the [README](README.md#license),
without any additional terms or conditions.
