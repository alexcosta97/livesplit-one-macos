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

The app is Swift and AppKit, built with Xcode, on top of a Rust library in
`core/`. Spec §4 describes how the pieces fit together and how they're built.

1. Install Xcode 26.6 or newer from the App Store (the version CI uses is
   set in `.github/actions/select-xcode/action.yml`). Then run
   `sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer`.
   Xcode includes `swift format`, which the checks use.
2. Install [rustup](https://rustup.rs/) and [mise](https://mise.jdx.dev/),
   then run `mise install` and `npm ci` in the repository. Rust's version and
   targets come from `rust-toolchain.toml`. mise installs XcodeGen,
   git-cliff, shellcheck, actionlint and Node, and `npm ci` installs
   commitlint from `package.json`. rustup from Homebrew doesn't put `cargo`
   on your `PATH`: add `$(brew --prefix rustup)/bin` to it, or the `cargo`
   checks below fail with "command not found".
3. Build `core/` and generate the Xcode project:

   ```sh
   scripts/build-core.sh
   xcodegen generate
   ```

   The first build downloads and compiles livesplit-core and takes a few
   minutes. After that, building in Xcode rebuilds `core/` when it needs to.

   Open the generated `LiveSplitOne.xcodeproj` in Xcode. It is never
   committed: run `xcodegen generate` again after pulling changes to
   `project.yml`.
4. Before pushing, run the same checks CI runs, from the repository root:

   ```sh
   git fetch origin main
   mise x -- npx commitlint --from origin/main --to HEAD --verbose
   cargo fmt --check --manifest-path core/Cargo.toml
   cargo clippy --all-targets --locked --manifest-path core/Cargo.toml -- -D warnings
   cargo test --locked --manifest-path core/Cargo.toml
   swift format lint --strict --recursive App Tests LiveSplitCore/Wrapper scripts
   mise x -- actionlint
   mise x -- shellcheck scripts/*.sh scripts/release/*.sh scripts/wiki/*.sh
   mise x -- scripts/release/test-release-scripts.sh
   scripts/wiki/test-wiki-scripts.sh
   scripts/wiki/check.sh docs/wiki
   xcodegen generate
   xcodebuild test -project LiveSplitOne.xcodeproj -scheme LiveSplitOne -destination 'platform=macOS'
   scripts/build-app.sh 0.0.0-dev
   ```

   commitlint checks every commit on the branch against the Conventional
   Commits rules in `commitlint.config.mjs`, as CI's `commitlint` check does,
   including a 100-character limit on each line of the body.
   `scripts/build-app.sh` writes the app to `dist/`. The release script tests
   need git-cliff (from `mise install`) and `jq`, which macOS ships. Spec §15
   lists what each CI check runs.

## Testing

Spec §14 describes the test levels (unit, headless UI, integration and E2E),
what each may drive and check, the E2E harness and the list of E2E flows.

- A bug found at a higher level gets a test at the lowest level that can catch
  it.
- Every pull request that changes the app adds tests at each level the change
  needs, including an E2E test for a new or changed user flow.

### Snapshot tests

When a change is meant to change how a layout looks (a livesplit-core update,
for example), record new reference images in `Tests/Integration/Snapshots/`,
look at each one, and commit them with the change:

```sh
TEST_RUNNER_LSO_RECORD_SNAPSHOTS=1 xcodebuild test -project LiveSplitOne.xcodeproj \
  -scheme LiveSplitOne -destination 'platform=macOS' \
  -only-testing:LiveSplitOneIntegrationTests/RenderingTests
```

Recording makes each snapshot test fail, so a run that records is never
taken for a pass. Run the tests again without the variable to check. When a
comparison fails, the message names a file with that run's image.

## User documentation

The user documentation is the repository's
[wiki](https://github.com/alexcosta97/livesplit-one-macos/wiki), written in
`docs/wiki/` and published on merge to `main` (spec §16). Never edit the wiki
on GitHub: the next sync overwrites it.

- A pull request that changes something users can see updates the
  documentation in the same pull request: the wiki page it belongs on (spec
  §16.2), or, once there is a full release, the Upcoming Changes page (spec
  §16.3).
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
update dependencies, configured in `renovate.json`. Spec §15 says which
updates are `fix(deps)` and released, and which are `ci(deps)` or
`chore(deps)` and not.

- When you add a Swift package that only the tests use, add a rule to
  `renovate.json` making its updates `chore`, or they'll be released.
- When you add a GitHub Action, pin it to a full commit SHA with the exact
  version as a comment, for example
  `uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1`
  (`gh api repos/actions/checkout/commits/v7.0.1 --jq .sha` gives the SHA).
  Renovate then updates the SHA and the comment together. Don't add one to
  the release jobs that publish (spec §15).

Renovate's pull requests are the one exception to the linked-issue rule. They
go through the same checks and are merged by a maintainer like any other pull
request. The Dependency Dashboard issue lists pending updates.

## Releases

Releases are automated: there is no version bump to commit and no changelog
to write. Spec §15 describes how the version is worked out, when candidates
are published and what the release contains. A maintainer's part:

- Every merge to `main` that produces a version publishes a release
  candidate, a GitHub pre-release tagged `vX.Y.Z-rc.N`. To release it,
  approve its pending release job in the `release` environment. That
  publishes `vX.Y.Z` from the same commit, marked **Latest**.
- Approve when no merge is pending: a newer merge cancels the older Release
  run, even one already approved and publishing. If a run is cancelled after
  approval, approve the newer candidate.
- Never re-run an older Release run: it would cancel the newer candidate, and
  approving it would publish an older commit.
- A leftover draft release `vX.Y.Z[-rc.N]` with no tag is from a publish that
  was killed. Don't publish it by hand, and don't re-run the killed run: the
  next Release run for that version replaces it. If the version has moved on
  (after a newer `feat`, say), delete it with `gh release delete <tag> --yes`.

## License

By contributing, you agree that your contributions are dual licensed under
the MIT and Apache-2.0 licenses, as described in the [README](README.md#license),
without any additional terms or conditions.
