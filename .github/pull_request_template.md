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
- [ ] In `core/`, `cargo fmt --check`,
      `cargo clippy --all-targets --locked -- -D warnings` and
      `cargo test --locked` pass locally.
- [ ] `swift format lint --strict --recursive App Tests` and `xcodebuild test`
      for the app scheme pass locally.
- [ ] Tests are added at each level the change needs: unit, headless UI,
      integration, and E2E for user flows (spec §14).
- [ ] Changes to the design are reflected in the design spec.
- [ ] Changes users can see are documented in `README.md`, and any
      screenshots to retake are listed.
