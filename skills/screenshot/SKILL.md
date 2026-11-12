---
name: screenshot
description: Take a screenshot of the user's screen or any window, launch GUI apps and find or focus their windows, and look at the result. Use when the user asks you to look at their screen, a UI, a visual bug, or a layout, when you start an app and want to see it, or when a visual check would settle a question.
---

# Screenshot and window control (niri / Wayland)

Capture to a file with `niri msg`, then open the file with the `read` tool, which shows images to you.

## Capture

```bash
# A specific window by id. No focus change needed; prefer this.
niri msg action screenshot-window --id <ID> --path /tmp/shot-$(date +%s).png

# The focused window, or the whole focused screen
niri msg action screenshot-window --path /tmp/shot-$(date +%s).png
niri msg action screenshot-screen --show-pointer false --path /tmp/shot-$(date +%s).png
```

## Find windows

```bash
niri msg --json windows | jq '.[] | {id, title, app_id, pid, is_focused}'
```

Windows have a numeric `id`. Match on `app_id`, `title`, or the `pid` of a process you started.

## Launch and control apps you run

```bash
# Start an app detached from your shell (keeps running after your command returns)
niri msg action spawn -- <command> [args...]
# or, for a shell line: niri msg action spawn-sh -- '<command line>'

# Windows open asynchronously: poll for the new window, do not assume it is there
for i in $(seq 20); do
  id=$(niri msg --json windows | jq -r '.[] | select(.app_id=="<app_id>") | .id' | tail -1)
  [ -n "$id" ] && break; sleep 0.5
done

niri msg action focus-window --id "$id"   # bring it forward / give it focus
niri msg action close-window --id "$id"   # close it when you are done
```

Only close windows you opened yourself. Take the id from the list; never close a window you did not start.

`close-window` is ignored by some apps (WezTerm, for one). Check the window list afterwards; if it is still there, stop the process you started (`kill <pid>`, using the `pid` from the window list or the command you spawned) rather than leaving it open. Never use `pkill` or kill by name, since that can take down the user's own windows.

If `spawn` shows no window, do not launch the app again by another route. Look at the window list first, since the window may just be slow to appear, and wait up to about 10 seconds. If it still did not open, check that the command runs on its own (`command -v <cmd>`), fix it, and spawn once more. Never leave two copies running; close any extra one you opened before you continue.

## Rules

- `--path` must be absolute. Use a unique name under `/tmp`; without `--path` the file lands in the user's Pictures folder.
- The capture also lands on the user's clipboard. That is expected.
- Prefer `screenshot-window --id` over `screenshot-screen`: smaller, and it avoids unrelated windows and notifications.
- Focusing a window moves the user's focus and can interrupt what they are doing. Focus only apps you launched or when asked. After a capture you do not need to refocus the terminal; `niri msg action focus-window --id <your terminal's id>` restores it if you changed focus (note the focused window's id before you move).
- Screenshots can contain private data (messages, tokens, other apps). Capture only when asked or clearly needed, and never upload or paste the image anywhere.
- After `read`, describe what you see and act on it. If the image does not come back (the model may not accept images), say so instead of guessing.
- Delete the files when you are done: `rm /tmp/shot-*.png`.
