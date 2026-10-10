<!--
Title: use a Conventional Commit, for example `feat(server): add automatic reconnection`.
Pull requests are squash-merged and the title becomes the commit on `main`,
so it decides the next version. See CONTRIBUTING.md.
-->

## Issue

<!-- Link the issue that describes this work. Every pull request needs one;
open an issue first if none exists. -->

Closes #

## What changed and why

## How it was tested

## Checklist

- [ ] The pull request links the issue it resolves.
- [ ] The title follows Conventional Commits.
- [ ] Every commit is signed and follows Conventional Commits.
- [ ] The Rust checks (`cargo fmt --check`, `cargo clippy … -D warnings`,
      `cargo test --locked`), `swift format lint --strict` and
      `xcodebuild test` pass locally (see CONTRIBUTING.md).
- [ ] Tests are added at each level the change needs: unit, headless UI,
      integration, and E2E for user flows (spec §14).
- [ ] Changes to the design are reflected in the design spec.
- [ ] Changes users can see are documented in `README.md`, and any
      screenshots to retake are listed.
- [ ] Every problem found while working on this is fixed here, or linked
      above to the issue where it was deferred, will be investigated, or is
      its own task.
