# Defiller

Skip the boring parts of your **local videos in VLC — automatically.** Mark the filler, recaps, intros, and "next episode" previews once; from then on they're skipped during normal playback, with no button to press. Built for rewatching anime, works for any video file.

100% offline — no app, no account, no network. Just two small Lua files and a plain-text skip list per video.

---

## What's in the box

| File | Goes in | Job |
|------|---------|-----|
| `defiller.lua` | `lua/extensions/` | The panel where you **mark and save** skip ranges. |
| `defiller-intf.lua` | `lua/intf/` | A tiny background engine that **does the skipping** while you watch. |

---

## Install (about 3 minutes)

**1. Open your VLC config folder.**

| OS | Folder |
|----|--------|
| **Windows** | `%APPDATA%\vlc\` |
| macOS | `~/Library/Application Support/org.videolan.vlc/` |
| Linux | `~/.local/share/vlc/` |

> Windows: paste `%APPDATA%\vlc\` into the File Explorer address bar and press Enter.

**2. Put the two files in place** (create the `lua`, `extensions`, and `intf` folders if missing):

- `defiller.lua` &rarr; `lua\extensions\`
- `defiller-intf.lua` &rarr; `lua\intf\`

**3. Turn on automatic skipping — pick ONE:**

- **Always-on (recommended).** Open `vlcrc` in the config folder, find these lines, delete the leading `#`, and set the values:
  ```
  extraintf=luaintf
  lua-intf=defiller-intf
  ```
- **Launcher.** Or use `Watch with Defiller.bat` — double-click it, or drag a video file onto it. Close any other open VLC window first.

**4. Restart VLC.**

---

## Using it

1. Play a video.
2. View menu &rarr; **Defiller** &rarr; the panel opens.
3. At the filler's start, click **Mark Start**.
4. At the filler's end, click **Mark End**. (Leave the panel open while you watch — it floats over the video and doesn't block playback.)
5. Click **Add skip range**, then **Save list**.

Done — that video now skips those ranges automatically, every time. Repeat step 3–5 for each filler section.

**Remove a range:** select it &rarr; **Delete selected** &rarr; **Save list**.

### Good to know

- You don't have to close the panel — it's a floating window; leave it open and scrub underneath.
- Your in-progress mark is remembered: Mark Start, close the panel (or even restart your PC), reopen &rarr; the Start is pre-filled. It clears once you Add the range.
- The View-menu check mark is VLC's own "extension is on" indicator (built into VLC). Closing the panel via its X un-checks it; clicking the menu item opens it again.

---

## The skip-list format

Each video gets a small text file, `defiller-<filename>.skip`, in your VLC config folder — plain text, editable, shareable:

```
# Defiller skip list
# file: Dragon Ball Z - 123.mkv
# One range per line, in seconds:  START,END
83.000,151.500
540.000,712.250
1325.000,1410.000
```

Lines starting with `#` are ignored.

---

## Sharing skip lists (and the honest limitation)

You can share a `.skip` file, but read this first. Online skip-sharing works because every video has one global ID. **Local files don't.** Your "Dragon Ball Z 123" and a friend's are usually *different rips* — different intro length, trims, PAL vs NTSC speed, broadcast vs Blu-ray — so the same timestamps can be **off by seconds to minutes** on someone else's copy, or line up perfectly if you both have the exact same release.

- Sharing is reliable between people with the **identical release** (same rip / same torrent).
- To use someone's list: drop their file into your VLC config folder and rename it `defiller-<your-filename>.skip`.

---

## How the auto-skip works

`defiller-intf.lua` checks the playback position four times a second. When it enters a saved range, it instantly seeks to the end of that range. It only reads the position and seeks — it never modifies your video files, and does nothing on videos that have no `.skip` file.

---

## License

[MIT](LICENSE) — use it, fork it, share it.
