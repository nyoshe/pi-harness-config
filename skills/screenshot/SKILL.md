---
name: screenshot
description: Take a screenshot of the user's screen or focused window and look at it. Use when the user asks you to look at their screen, a UI, a visual bug, or a layout, or when a visual check would settle a question.
---

# Screenshot (niri / Wayland)

Capture to a file with `niri msg`, then open the file with the `read` tool, which shows images to you.

```bash
# Whole focused screen
niri msg action screenshot-screen --show-pointer false --path /tmp/shot-$(date +%s).png

# Only the focused window
niri msg action screenshot-window --path /tmp/shot-$(date +%s).png
```

Rules:

- `--path` must be absolute. Use a unique name under `/tmp`; the default save location is the user's Pictures folder, so do not omit `--path`.
- The capture also lands on the user's clipboard. That is expected.
- Prefer `screenshot-window` over `screenshot-screen`: smaller, and it avoids capturing unrelated windows or notifications.
- You can only capture the window that is focused right now. If it is the terminal running you, tell the user to focus the window they want you to see, then capture after they confirm.
- Screenshots can contain private data (messages, tokens, other apps). Capture only when asked or clearly needed, and never upload or paste the image anywhere.
- After `read`, describe what you see and act on it. If the image does not come back (the model may not accept images), say so instead of guessing.
- Delete the file when you are done: `rm /tmp/shot-*.png`.
