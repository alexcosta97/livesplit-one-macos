LiveSplit One for macOS can take its timer commands from a server on another computer, such as [livesplit-asr-bridge](https://github.com/alexcosta97/livesplit-asr-bridge) on your gaming PC. The server starts, splits and resets the timer as your game's auto splitter says, and the timer still answers your own keys and menus.


## Connecting

1. Start the server on the other computer.
2. Right-click the timer and choose **Connect to Server…**. It is also in the **File** menu.
3. Type the server's address under **Server address:**, for example `ws://192.168.1.20:9087`, and click **Connect**.

<!-- screenshot: S3 connect-sheet.png -->
The Connect to Server sheet.

The timer shows **Connected to &lt;host&gt;** once the server answers. The app remembers the address and fills it in next time. It doesn't connect by itself when it opens: choose **Connect to Server…** each time.

## Which address to use

The address is the other computer's address and the port the server listens on, as `ws://<address>:<port>`. If you leave out `ws://`, the app adds it. Use `wss://` for a server that uses a secure connection. The bridge's own documentation says which port it uses.

- **On the same network:** the gaming PC's local address, such as `192.168.1.20`. On Linux, `ip addr` shows it.
- **Through a VPN such as Tailscale:** the address the VPN gives the gaming PC, such as `100.101.102.103`. This works when the local address doesn't, for example because of the PC's firewall.

If the sheet says **Use a ws:// or wss:// address.**, the address starts with another scheme, such as `http://`. If it says **Enter the server's address.**, the address has no computer name or number.

## Local network access

The first time you connect to another computer, macOS asks whether LiveSplit One for macOS may find devices on your local network. Choose **Allow**.

<!-- screenshot: T2 macos-local-network-prompt.png -->
macOS asking to allow local network access.
 If you chose **Don't Allow**, connecting fails with **LiveSplit One for macOS needs local network access. Allow it in System Settings › Privacy & Security › Local Network.** Turn on **LiveSplit One for macOS** there, then connect again.

<!-- screenshot: T3 macos-local-network-settings.png -->
System Settings, with LiveSplit One for macOS allowed under Local Network.

## What the timer shows

<!-- screenshot: S4 overlay-notice.png -->
The **Connected to &lt;host&gt;** notice.

| Notice | What it means |
|---|---|
| **Connected to &lt;host&gt;** | The server answered. Its commands now move the timer. |
| **Couldn't connect to &lt;host&gt;: &lt;reason&gt;** | The first attempt failed, so the app doesn't try again: the address may be wrong. Check it and choose **Connect to Server…** again. See [Troubleshooting](Troubleshooting#the-app-cant-connect-to-the-server). |
| **Lost connection to &lt;host&gt;, retrying…** | The connection worked, then stopped. The app tries again by itself, below. |

&lt;host&gt; is the server's address, with its port, such as `192.168.1.20:9087`.

## When the connection is lost

If the server stops, the gaming PC sleeps or the network drops, the app notices within about 20 seconds and shows **Lost connection to &lt;host&gt;, retrying…**. It tries again after 1 second, then 2, 4, 8, 16 and 30 seconds, then every 30 seconds until the server answers. Failed tries show nothing; the log has a line for each. Once it reconnects, the timer shows **Connected to &lt;host&gt;** again.

While the connection is down, the timer keeps running, and your keys and menus still work.

## Disconnecting

While connected, or while connecting or retrying, the menu item reads **Disconnect from &lt;host&gt;**. Choose it to close the connection and stop retrying. Quitting the app does the same.

## What the server sees

Every change to the timer goes to the server while connected, including your own splits from the keyboard or the menus, so the server always knows where the timer is. Changes while not connected aren't sent later.

## Other servers

Any server that speaks LiveSplit One's server protocol works, such as the ones LiveSplit One in a browser connects to. A server that requires a browser's `Origin` header isn't supported.

The log records what the server sends and what the app replies: see [Settings and Logs](Settings-and-Logs#logs).
