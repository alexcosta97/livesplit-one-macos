This walks you from opening the app for the first time to saving your first run. It takes about five minutes. You need the app installed: if you haven't, start with [Installing](Installing).

## 1. Open the app

Open **LiveSplit One for macOS**. The window has no title bar and shows only the timer: LiveSplit One's default layout, and a run with one segment, **Time**. Everything else is in the right-click menu. See [The Timer Window](The-Timer-Window).

## 2. Open your splits

1. Right-click the timer, choose **Open Splits**, then **Open…**.
2. Pick your splits file, for example a `.lss` from LiveSplit.

The timer shows your run. If you don't have splits yet, skip this step: the run with one segment works for trying the timer. You can save it in step 6.

More about formats and recent files is in [Splits and Layouts](Splits-and-Layouts#opening-splits).

## 3. Open a layout

1. Right-click the timer, choose **Open Layout**, then **Open…**.
2. Pick a `.lsl` or `.ls1l` file.

Your splits keep their times. Drag the edges of the window to change its size: the app remembers it for this layout. If your splits name a layout, it was opened for you in step 2, and you can skip this step.

## 4. Start and split

Click the timer so it is the window in front, then:

1. Press Space to start the timer.
2. Press Space again at the end of each segment to split.
3. Press P to pause, and P again to resume.

The other keys are in [The Timer Window](The-Timer-Window#keyboard-shortcuts). The same commands are in **Control** in the right-click menu.

## 5. Reset

Press ⌫ (Delete) to reset. If the attempt beat some of your best times, the app asks whether to update them. Choose **Yes** or **No**: the app remembers your answer and doesn't ask again. [Splits and Layouts](Splits-and-Layouts#reset-with-new-best-times) says how to change it.

## 6. Save

Press ⌘S, or choose **Save Splits** in the **File** menu. If the splits came from another format, or have no file yet, the app asks for a name and saves them as `.lss`.

Quit with ⌘Q. The app asks to save changes, if there are any. The next time you open the app, it reopens the same splits and layout, with the window where you left it.

## 7. Connect to livesplit-asr-bridge

If your game runs on another computer with [livesplit-asr-bridge](https://github.com/alexcosta97/livesplit-asr-bridge), let it drive the timer:

1. Start the bridge on the gaming PC.
2. Right-click the timer and choose **Connect to Server…**.
3. Type the gaming PC's address and the bridge's port, such as `192.168.1.20:9087`, and click **Connect**.

The timer shows **Connected to 192.168.1.20:9087**, and the auto splitter now starts and splits the timer. The first time, macOS asks to allow local network access: choose **Allow**. [Connecting to a Server](Connecting-to-a-Server) says which address to use and what happens when the connection drops.

## Next

- [Editing Splits](Editing-Splits): renaming segments and changing times.
- [The Menu](The-Menu): every command in the menus.
- [Splits and Layouts](Splits-and-Layouts): everything about files.
- [Connecting to a Server](Connecting-to-a-Server): everything about the bridge.
- [Settings and Logs](Settings-and-Logs): changing keys and what the app remembers.
