# User Documentation Wiki Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish the user documentation as the repository's GitHub wiki, written in `docs/wiki/`, checked on pull requests and synced on merge to `main`, with the pages for what the app does so far, so every issue after this one documents itself in its own page (issue #25).

**Architecture:** A port of livesplit-asr-bridge's wiki (its plan `docs/superpowers/plans/2026-10-01-user-docs-wiki.md` and its spec §15). Pages are Markdown in `docs/wiki/`. `scripts/wiki/check.sh` checks page links, images and sidebar coverage in the required `lint` job. `.github/workflows/wiki.yml` mirrors `docs/wiki/` into `livesplit-one-macos.wiki` with `scripts/wiki/publish.sh` on push to `main`. After a full release, the release job opens an issue when Upcoming Changes has entries (`scripts/wiki/upcoming.sh`). The README shrinks to a summary that links to the wiki.

**Tech Stack:** GitHub wiki (Gollum Markdown), Bash, GitHub Actions, shellcheck and actionlint (pinned in `mise.toml`), git, rsync.

**Spec:** `docs/superpowers/specs/2026-10-09-livesplit-one-macos-design.md`, section 16 (with 3, 11, 12 and 15 as the source of the page contents). Issue: #25. The pages for later features are written by their issues (spec §16.2), and #41 adds the screenshots and the whole-wiki pass.

**Branch and worktree:** `docs/user-wiki`, at `../livesplit-one-macos-wt/user-wiki`. **PR title:** `docs: publish the user documentation wiki`. **PR body:** `Closes #25`, using the pull request template. One pull request; each task is one commit.

## Before you start

- **#17 (logging) and #16 (settings) are merged first**: the Settings and Logs page describes them. Read `App/Log/` and `App/Config/` before writing it.
- The rules for documentation in every change (`AGENTS.md`, `CONTRIBUTING.md` "User documentation") were already updated by #40. Don't change them here, except as Task 4 says.
- Fetch the bridge's files this plan ports, to compare against: `gh api repos/alexcosta97/livesplit-asr-bridge/contents/scripts/wiki/check.sh -q .content | base64 -d` (and the same for `publish.sh`, `upcoming.sh`, `test-wiki-scripts.sh`, `.github/workflows/wiki.yml`).
- `mise install` in the repository, for shellcheck and actionlint.

## Global Constraints

- The app is named **LiveSplit One for macOS** in the pages; `livesplit-one-macos` only for files, folders and the repository. It is always described as unofficial and a version of LiveSplit One, not of the original Windows LiveSplit (spec §3).
- Voice: plain and direct, short sentences, the words the app shows, no marketing superlatives (spec §16.2).
- Menu items, buttons and notices in bold, spelled exactly as the app shows them. Check each one against `App/` with `grep -rn '"<name>' App/` before writing it. Names from macOS (System Settings, Finder, Console.app) are checked against macOS 15 and the current macOS.
- Each fact lives on one page; other pages link to it.
- Page links use page names: `[Troubleshooting](Troubleshooting)`. Images: `images/<subject>.png` or `.svg`.
- There is no full release yet, so pages describe `main` and Upcoming Changes has no entries (spec §16.3).
- Screenshots don't exist yet. Where one belongs, write `<!-- screenshot: <ID> <file> -->` (IDs from spec §16.4) followed by a one-sentence description of the screen. #41 replaces them.
- Pages describe only what `main` does. A page or sentence for a feature that isn't merged yet waits for that feature's issue.
- Folders: settings `~/Library/Application Support/livesplit-one-macos/` (`app.toml`, `app.toml.bad`); logs `~/Library/Logs/livesplit-one-macos/`, files `livesplit-one-macos-YYYY-MM-DD.log`.
- Release asset: `livesplit-one-macos-<version>-macos-universal.zip` (`scripts/build-app.sh`), containing `LiveSplit One.app`. Download link: `https://github.com/alexcosta97/livesplit-one-macos/releases/latest`. Requirements: macOS 15 (Sequoia) or newer, Apple Silicon or Intel.
- Workflows: only first-party actions (`actions/checkout@v7`) in a job with a write token, as #36 recommends.
- Commits: Conventional Commits, signed, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **A bold name that doesn't match the app** (a menu item renamed, "Logs folder" instead of **Open Log Folder**): readers search for it and find nothing. Each page task ends with a step that greps each bold term in `App/`.
2. **Links that work in `docs/wiki/` but not in the published wiki**, or the reverse: `check.sh` pins page and image links; Task 5 checks the published wiki by hand.
3. **The sync before the wiki repository exists** (GitHub creates it only with the first page): `publish.sh` fails with a message saying what to do, not a bare git error. Test in Task 1.
4. **A sync that deletes the wiki's `.git`, pushes when nothing changed, or prints the token**: Task 1 tests all three against a local bare repository.
5. **The Upcoming Changes step failing a release**: it runs after the release is published, and an empty page opens no issue. Task 1 tests the entry count; Task 2 places the step last.

---

### Task 1: The wiki scripts and their tests

**Files:**
- Create: `scripts/wiki/check.sh`
- Create: `scripts/wiki/publish.sh`
- Create: `scripts/wiki/upcoming.sh`
- Create: `scripts/wiki/test-wiki-scripts.sh`

**Interfaces:**
- Produces: `check.sh [dir]` (exit 1 and one line per problem), `publish.sh <src-dir> <wiki-remote-url> <source-sha>`, `upcoming.sh [file]` (one heading per line), and `test-wiki-scripts.sh`. Tasks 2 and 3 run them.

These are livesplit-asr-bridge's scripts. Copy each one from the bridge and change only what is listed here, so the two repositories stay alike.

- [ ] **Step 1: Copy the scripts**

```bash
mkdir -p scripts/wiki
for f in check.sh publish.sh upcoming.sh test-wiki-scripts.sh; do
  gh api "repos/alexcosta97/livesplit-asr-bridge/contents/scripts/wiki/$f" -q .content \
    | base64 -d > "scripts/wiki/$f"
done
chmod +x scripts/wiki/*.sh
```

- [ ] **Step 2: Adapt them**

The scripts have no bridge-specific names, with one exception. In `test-wiki-scripts.sh`, the `upcoming.sh` test uses bridge page names. Replace:

```bash
printf '# Upcoming Changes\n\n## Connecting LiveSplit One\n\ntext\n\n## Logs and Files\n\ntext\n' > "$tmp/two.md"
expect_upcoming "upcoming: prints each heading in order" $'Connecting LiveSplit One\nLogs and Files' "$tmp/two.md"
```

with:

```bash
printf '# Upcoming Changes\n\n## Connecting to a Server\n\ntext\n\n## Settings and Logs\n\ntext\n' > "$tmp/two.md"
expect_upcoming "upcoming: prints each heading in order" $'Connecting to a Server\nSettings and Logs' "$tmp/two.md"
```

Then check nothing else names the bridge: `grep -n -i 'asr\|bridge' scripts/wiki/*.sh` prints nothing.

What the scripts do, so the review can check it (from the bridge's code):
- `check.sh`: every `](target)` and `src="target"` in each page is a page that exists (no `.md` suffix) or an image under `images/` that exists. External links (`scheme:`), anchors and `#section` suffixes are skipped. Every page except `_*.md` is linked from `_Sidebar.md`.
- `publish.sh`: shallow-clones the wiki, `rsync -a --delete --exclude .git` the pages into it, commits as `github-actions[bot]` with `Sync from <short sha>` only when something changed, and pushes. A failed clone says to create the first wiki page and prints git's error with any `x-access-token:…@` masked.
- `upcoming.sh`: prints each `## ` heading outside code fences.

- [ ] **Step 3: Run the tests**

Run: `mise x -- shellcheck scripts/wiki/*.sh && scripts/wiki/test-wiki-scripts.sh`
Expected: shellcheck prints nothing; every test line starts `ok   -`, with none starting `FAIL`, and the script exits 0. The tests include "publish: a missing wiki repository fails with guidance", "publish: an unchanged tree publishes nothing" and "publish: a failed clone shows git's error without the token".

- [ ] **Step 4: Commit**

```bash
git add scripts/wiki
git commit -m "ci(wiki): add the wiki check, publish and upcoming scripts

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Publishing, and the Upcoming Changes issue

**Files:**
- Create: `.github/workflows/wiki.yml`
- Modify: `.github/workflows/release.yml` (the `release` job)

**Interfaces:**
- Consumes: `publish.sh`, `upcoming.sh` (Task 1).
- Produces: the `Wiki` workflow (push to `main` changing `docs/wiki/**`, and manual dispatch), and the release job's last step.

Key facts:
- The wiki is checked in the required `lint` job (Task 3), so unlike the bridge's `wiki.yml` this one has no `check` job and doesn't run on pull requests. It only publishes.
- The `release` job has `contents: write`. Opening an issue also needs `issues: write`.

- [ ] **Step 1: Write the workflow**

`.github/workflows/wiki.yml`:

```yaml
name: Wiki

# Publishes docs/wiki/ to the repository's wiki (spec §16.1). The pages are
# checked on pull requests by the lint job in ci.yml.
on:
  push:
    branches: [main]
    paths:
      - docs/wiki/**
  workflow_dispatch:

permissions:
  contents: read

jobs:
  publish:
    name: publish wiki
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    permissions:
      contents: write
    # One sync at a time, in order: a newer push waits rather than racing.
    concurrency:
      group: wiki
    steps:
      - uses: actions/checkout@v7
      - name: Publish
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          scripts/wiki/publish.sh docs/wiki \
            "https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.wiki.git" \
            "$GITHUB_SHA"
```

- [ ] **Step 2: Add the Upcoming Changes step to the release job**

In `.github/workflows/release.yml`, in the `release` job, change `permissions` to:

```yaml
    permissions:
      contents: write
      # The Upcoming Changes issue (spec §16.3).
      issues: write
```

and add this as the job's last step, after "Publish the release":

```yaml
      # After the release is published, so it can't fail the release.
      - name: Ask to move upcoming documentation into the wiki
        env:
          GH_TOKEN: ${{ github.token }}
          TAG: v${{ needs.version.outputs.version }}
        run: |
          entries=$(scripts/wiki/upcoming.sh)
          if [[ -n "$entries" ]]; then
            {
              echo "$TAG is released, so move its documentation from Upcoming Changes into the wiki pages (spec §16.3), then empty Upcoming Changes."
              echo
              echo "Entries:"
              while IFS= read -r entry; do echo "- $entry"; done <<< "$entries"
            } > body.md
            gh issue create --title "Move upcoming documentation into the wiki for $TAG" \
              --label task --body-file body.md
          fi
```

- [ ] **Step 3: Lint the workflows**

Run: `mise x -- actionlint`
Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/wiki.yml .github/workflows/release.yml
git commit -m "ci(wiki): publish the wiki on merge and ask for upcoming docs after a release

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: The wiki's frame: Home, sidebar, footer, Upcoming Changes, and the lint check

**Files:**
- Create: `docs/wiki/Home.md`
- Create: `docs/wiki/_Sidebar.md`
- Create: `docs/wiki/_Footer.md`
- Create: `docs/wiki/Upcoming-Changes.md`
- Create: `docs/wiki/images/two-pcs.svg`
- Modify: `.github/workflows/ci.yml` (the `lint` job)
- Modify: `CONTRIBUTING.md` (the checks in "Development setup", step 4)

**Interfaces:**
- Consumes: `check.sh`, `test-wiki-scripts.sh` (Task 1).
- Produces: the sidebar, in spec §16.2's order, holding only pages that exist. Each later issue adds its page to the sidebar in that order.

- [ ] **Step 1: Write the diagram**

`docs/wiki/images/two-pcs.svg`, adapted from the bridge's:

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 720 220" width="720" height="220" role="img" aria-label="The gaming PC runs livesplit-asr-bridge and sends timer commands over ws://…:16834 to LiveSplit One for macOS on the Mac.">
  <style>text{font-family:system-ui,-apple-system,"Segoe UI",Roboto,Helvetica,Arial,sans-serif}</style>
  <rect width="720" height="220" fill="#0B0B0C"/>
  <rect x="24.5" y="40.5" width="230" height="140" rx="4" fill="#151517" stroke="#2A2A2E"/>
  <circle cx="60" cy="76" r="14" fill="#F5F5F4"/>
  <text x="84" y="82" font-size="20" font-weight="700" fill="#F5F5F4">Gaming PC</text>
  <text x="44" y="126" font-size="14" fill="#F5F5F4">livesplit-asr-bridge</text>
  <text x="44" y="148" font-size="14" fill="#A1A1AA">runs the auto splitter</text>
  <rect x="465.5" y="40.5" width="230" height="140" rx="4" fill="#151517" stroke="#2A2A2E"/>
  <circle cx="501" cy="76" r="14" fill="#FF4D00"/>
  <text x="525" y="82" font-size="20" font-weight="700" fill="#F5F5F4">Mac</text>
  <text x="485" y="126" font-size="14" fill="#F5F5F4">LiveSplit One for macOS</text>
  <text x="485" y="148" font-size="14" fill="#A1A1AA">shows the timer</text>
  <line x1="262" y1="110" x2="448" y2="110" stroke="#F5F5F4" stroke-width="4" stroke-linecap="round"/>
  <path d="M440 98 L458 110 L440 122 Z" fill="#F5F5F4"/>
  <text x="360" y="92" font-size="14" text-anchor="middle" fill="#F5F5F4">ws://…:16834</text>
  <text x="360" y="136" font-size="13" text-anchor="middle" fill="#A1A1AA">start, split, reset</text>
</svg>
```

- [ ] **Step 2: Write the pages**

`docs/wiki/Home.md`:

```markdown
# LiveSplit One for macOS

An unofficial native macOS version of LiveSplit One, the speedrun timer. It isn't made by the LiveSplit team, and it is a version of LiveSplit One, not of the original Windows LiveSplit.

It behaves like the classic LiveSplit: one window showing only the timer, with everything else in a right-click menu. It reads and writes the same splits and layout files as LiveSplit One, and draws layouts with the same renderer, so a layout looks the same as in LiveSplit One.

It is made for two-PC setups: a gaming PC runs the game and [livesplit-asr-bridge](https://github.com/alexcosta97/livesplit-asr-bridge), and a Mac shows the timer.

<img src="images/two-pcs.svg" width="720" alt="Two computers joined by a link. The gaming PC runs livesplit-asr-bridge and the auto splitter. The Mac runs LiveSplit One for macOS. Timer commands go from the gaming PC to the Mac over ws://…:16834.">

## Start here

1. [Installing](Installing): download the app and open it the first time.

## More

- [Settings and Logs](Settings-and-Logs): where the app keeps its settings and logs.
- [Troubleshooting](Troubleshooting): what you see, why, and what to do.
- [Upcoming Changes](Upcoming-Changes): documentation for changes not yet released.
```

`docs/wiki/_Sidebar.md`:

```markdown
- [Home](Home)
- [Installing](Installing)
- [Settings and Logs](Settings-and-Logs)
- [Troubleshooting](Troubleshooting)
- [Upcoming Changes](Upcoming-Changes)
```

`docs/wiki/_Footer.md`:

```markdown
Questions and bugs go to the [issues](https://github.com/alexcosta97/livesplit-one-macos/issues). Until the first full release, these pages describe the newest release candidate, and after it, the latest release. What's coming is on [Upcoming Changes](Upcoming-Changes).
```

`docs/wiki/Upcoming-Changes.md`:

```markdown
Until the first full release, the other pages describe the newest release candidate. After it, they describe the latest release. When a change adds or alters something you can see in the app, its documentation waits here until that change is released, under a heading naming the page it belongs on. Then it moves into its page.

Nothing yet. The documentation matches the current pre-release.
```

Installing, Settings and Logs and Troubleshooting are written in Task 4; until then the check fails on their links, which is expected.

- [ ] **Step 3: Check the wiki in the lint job**

In `.github/workflows/ci.yml`, in the `lint` job, change the shellcheck step and add two steps after it:

```yaml
      - run: shellcheck scripts/*.sh scripts/release/*.sh scripts/wiki/*.sh
      # The wiki's pages and its scripts (spec §16.1).
      - run: scripts/wiki/test-wiki-scripts.sh
      - run: scripts/wiki/check.sh docs/wiki
```

In `CONTRIBUTING.md`, in "Development setup" step 4, change `mise x -- shellcheck scripts/*.sh scripts/release/*.sh` to `mise x -- shellcheck scripts/*.sh scripts/release/*.sh scripts/wiki/*.sh`, and add after the release scripts line:

```sh
   scripts/wiki/test-wiki-scripts.sh
   scripts/wiki/check.sh docs/wiki
```

- [ ] **Step 4: Run the check**

Run: `scripts/wiki/check.sh docs/wiki`
Expected: exit 1, naming exactly `Home.md: link to missing page Installing`, `… Settings-and-Logs`, `… Troubleshooting` and the same three from `_Sidebar.md` (the sidebar isn't checked as a page, but its links are). Nothing else.

- [ ] **Step 5: Commit**

```bash
mise x -- actionlint
git add docs/wiki .github/workflows/ci.yml CONTRIBUTING.md
git commit -m "docs(wiki): add the wiki's home, sidebar, footer and upcoming changes

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Installing, Settings and Logs, Troubleshooting, and a shorter README

**Files:**
- Create: `docs/wiki/Installing.md`
- Create: `docs/wiki/Settings-and-Logs.md`
- Create: `docs/wiki/Troubleshooting.md`
- Modify: `README.md`
- Modify: `.github/ISSUE_TEMPLATE/3-bug-report.yml` (the Logs field)

**Interfaces:**
- Consumes: the folders and names from #16 and #17 (`App/Config/`, `App/Log/`).
- Produces: the pages Home and the sidebar link to.

- [ ] **Step 1: Write Installing**

`docs/wiki/Installing.md`:

```markdown
LiveSplit One for macOS runs on macOS 15 (Sequoia) or newer, on Apple Silicon and Intel Macs. One download works on both.

## Downloading

Get the latest version from [the latest release](https://github.com/alexcosta97/livesplit-one-macos/releases/latest). Under **Assets**, download `livesplit-one-macos-<version>-macos-universal.zip`.

Releases marked **Pre-release** are release candidates for testing. The latest full release is the one the link above opens. Until the first full release, the link shows the release candidates, and these pages describe the newest one.

## Installing

1. Open the downloaded `.zip`. Finder unzips it into `LiveSplit One.app`.
2. Move `LiveSplit One.app` to your **Applications** folder.

## Opening the app for the first time

The app isn't notarised by Apple yet, so macOS blocks it the first time you open it.

1. Open the app. macOS says it can't verify that the app is free of malware. Click **Done**.
2. Open **System Settings**, then **Privacy & Security**.
3. Scroll down to the message about "LiveSplit One" and click **Open Anyway**. Confirm with your password or Touch ID, then click **Open Anyway** again.

<!-- screenshot: T1 macos-open-anyway.png -->
The Privacy & Security page in macOS System Settings, with the Open Anyway button next to the message about "LiveSplit One".

After that, the app opens normally. The message stays in Privacy & Security for about an hour after you try to open the app, so if it isn't there, open the app again first.

## Updating

There is no automatic update yet. Download the new release and replace `LiveSplit One.app` in Applications. You may need to choose **Open Anyway** again. Your settings and logs are kept: they live in folders that replacing the app doesn't touch ([Settings and Logs](Settings-and-Logs)).

## Uninstalling

1. Quit the app and move `LiveSplit One.app` from Applications to the Bin.
2. To remove its settings and logs too, delete these folders. In Finder, choose **Go → Go to Folder…** and paste each path:
   - `~/Library/Application Support/livesplit-one-macos`
   - `~/Library/Logs/livesplit-one-macos`

Your splits and layouts aren't in those folders, so they are kept.
```

- [ ] **Step 2: Write Settings and Logs**

`docs/wiki/Settings-and-Logs.md`. Check every fact against `App/Config/` and `App/Log/` as merged; if a message or name differs from this text, use the code's and say so in the pull request.

```markdown
## Settings

The app keeps its settings in one file:

    ~/Library/Application Support/livesplit-one-macos/app.toml

It holds the last splits and layout you opened, the recent files, the window's position for each layout, Always on Top, and the last server address. Your splits and layouts stay wherever you keep them; the app only stores where they are.

The file is created the first time a setting changes, and rewritten each time one does. It is a [TOML](https://toml.io) text file, so you can read it, but quit the app before editing it: the app rewrites it when a setting changes.

If the app can't read the file, for example after a mistake while editing it, it starts with the default settings and keeps the old file next to it as `app.toml.bad`, so nothing is lost. Each time this happens, the previous `app.toml.bad` is replaced.

## Logs

The app records what it does in log files, one per day:

    ~/Library/Logs/livesplit-one-macos/livesplit-one-macos-YYYY-MM-DD.log

- Files older than 7 days are deleted.
- Each day's file is limited to 50 MB. Past that, only errors are written to it until the next day, and one line says so.
- Each line starts with the time and what the line is about: **ERROR**, **CONNECTION** (connecting to a server, and every command and event), **TIMER** (timer actions and where they came from) or **APP** (the app starting, settings, files opened and saved).

For example:

    19:31:01.254  APP  LiveSplit One for macOS 0.1.0 started on macOS 15.1.0

If the app can't write the files, it keeps running and the lines still go to the system log.

### Finding the logs

- In Finder, choose **Go → Go to Folder…** and paste `~/Library/Logs/livesplit-one-macos`.
- **Console.app** lists the files under **Log Reports**.
- Console.app's live stream also shows every line as it happens, next to macOS's own messages, such as whether the app was allowed local network access. Search for the subsystem `dev.alexcosta.livesplit-one-macos`.
```

If #13 is merged when this is written, add to "Finding the logs", first: `- Right-click the timer and choose **Open Log Folder**.` Otherwise #13 adds it.

- [ ] **Step 3: Write Troubleshooting**

`docs/wiki/Troubleshooting.md`:

```markdown
Each section starts with what you see. If yours isn't here, [report a bug](#reporting-a-bug).

## macOS says the app can't be opened

The app isn't notarised by Apple yet. [Installing](Installing#opening-the-app-for-the-first-time) shows how to open it with **Open Anyway**.

## The settings were reset

The app couldn't read its settings file, so it started with the defaults. The old file is kept as `app.toml.bad` next to the new one. [Settings and Logs](Settings-and-Logs#settings) says where it is.

## Reporting a bug

Open a [bug report](https://github.com/alexcosta97/livesplit-one-macos/issues/new?template=3-bug-report.yml) and attach the log file for the day it happened. [Settings and Logs](Settings-and-Logs#logs) says where the files are. Each time the app starts, the log records its version, so the file also says which version you were using.
```

- [ ] **Step 4: Check the pages**

Run: `scripts/wiki/check.sh docs/wiki`
Expected: exit 0, no output.

Then check the bold names. These pages name only macOS's own items (**Done**, **System Settings**, **Privacy & Security**, **Open Anyway**, **Go → Go to Folder…**, **Console.app**, **Log Reports**, **Applications**, **Assets**, **Pre-release**) and the log tags. Run `grep -rn '"ERROR"\|"CONNECTION"\|"TIMER"\|"APP"' App/Log/` and check all four tags are found. Check the macOS names on the Mac in front of you, and the launch line's text against `App/AppDelegate.swift`.

- [ ] **Step 5: Shorten the README**

The README keeps what the app is and links to the wiki; details live only in the wiki (spec §16). In `README.md`:

- After the "Status" note, add: `The user documentation is in [the wiki](https://github.com/alexcosta97/livesplit-one-macos/wiki).`
- Replace the "Download" section and its "Opening the app the first time" subsection with:

  ```markdown
  ## Download

  Get it from
  [the latest release](https://github.com/alexcosta97/livesplit-one-macos/releases/latest).
  The app isn't notarised yet, so macOS blocks it the first time;
  [Installing](https://github.com/alexcosta97/livesplit-one-macos/wiki/Installing)
  shows how to open it.
  ```

- Replace the "Settings and logs" section with:

  ```markdown
  ## Settings and logs

  Settings are in `~/Library/Application Support/livesplit-one-macos/` and
  logs in `~/Library/Logs/livesplit-one-macos/`, the same rules as
  livesplit-asr-bridge.
  [Settings and Logs](https://github.com/alexcosta97/livesplit-one-macos/wiki/Settings-and-Logs)
  has the details.
  ```

- Leave "What it will do", "Requirements", "Using it with livesplit-asr-bridge" (#14 moves it into its own page), "Building from source" and "License" as they are.

- [ ] **Step 6: Point the bug form to the wiki**

In `.github/ISSUE_TEMPLATE/3-bug-report.yml`, at the end of the Logs field's description (line 74), add: ` [Settings and Logs](https://github.com/alexcosta97/livesplit-one-macos/wiki/Settings-and-Logs) has more.` Leave the Open Log Folder sentence: it describes the menu item #13 adds, and the form is for released versions.

- [ ] **Step 7: Commit**

```bash
git add docs/wiki README.md .github/ISSUE_TEMPLATE/3-bug-report.yml
git commit -m "docs(wiki): add Installing, Settings and Logs and Troubleshooting

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Checks, the pull request, and the first publish

- [ ] **Step 1: Run every check from `CONTRIBUTING.md`**

```bash
swift format lint --strict --recursive App Tests LiveSplitCore/Wrapper scripts
mise x -- actionlint
mise x -- shellcheck scripts/*.sh scripts/release/*.sh scripts/wiki/*.sh
mise x -- scripts/release/test-release-scripts.sh
scripts/wiki/test-wiki-scripts.sh
scripts/wiki/check.sh docs/wiki
```

No Swift or Rust changes, so the build and tests aren't needed locally; CI runs them.
Expected: every command succeeds.

- [ ] **Step 2: Open the pull request**

Push the branch and open the pull request with the template filled in: `Closes #25`; what changed and why; how it was tested; and, under a heading **After merging**, the maintainer's steps from Step 3, since the agent can't do them.

```bash
git push -u origin docs/user-wiki
PR_BODY=$(mktemp)
# Write the filled-in template to "$PR_BODY", then:
gh pr create --title "docs: publish the user documentation wiki" --body-file "$PR_BODY"
```

- [ ] **Step 3: The first publish (the maintainer, after merging)**

1. In the repository's **Settings → General → Features**, tick **Wikis** and **Restrict editing to collaborators only**.
2. Open the **Wiki** tab and create the first page with any text. GitHub creates the wiki repository only then.
3. Run the **Wiki** workflow from the **Actions** tab (**Run workflow** on `main`). Expected: the run passes and the wiki's history shows "Sync from <short sha>", replacing the page made in step 2.
4. Open the published wiki and click every link in the sidebar, Home and each page, and check the diagram shows. Anything that works in `docs/wiki/` but not in the wiki is a bug in `check.sh`: open an issue for it.
5. Run the workflow again. Expected: it prints `Nothing to publish` and adds no commit.
