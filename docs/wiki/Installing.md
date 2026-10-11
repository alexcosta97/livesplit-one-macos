LiveSplit One for macOS runs on macOS 15 (Sequoia) or newer, on Apple Silicon and Intel Macs. One download works on both.

## Downloading

Get the latest version from [the latest release](https://github.com/alexcosta97/livesplit-one-macos/releases/latest). Under **Assets**, download `livesplit-one-macos-<version>-macos-universal.zip`.

Releases marked **Pre-release** are release candidates for testing. The latest full release is the one the link above opens. Until the first full release, the link shows the release candidates, and these pages describe the app as it is being built, which can be ahead of the newest one.

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
