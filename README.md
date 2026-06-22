# Quick_Drop

A macOS drag-and-drop launcher: a palette that fans out as a semicircle from a
screen edge on a global hotkey, so you can drop files onto pinned folders, apps,
scripts, and share targets without window-switching.

## What's implemented

- **Global hotkey** — press **⌃⌥Space** (Control-Option-Space) anywhere to
  toggle the palette. Registered via the Carbon Hot Key API, so it needs **no
  Accessibility permission**. The combination is **customizable** from
  Preferences (see below).
- **Semicircle palette** — a translucent half-disc of your destinations fans
  out from a screen edge (or a quarter-fan from a corner). When you have more
  destinations than fit on the arc, on-screen **scroll chevrons** appear at the
  ends and you can **scroll/roll** through the rest (trackpad, wheel, or the
  chevrons); tiles slide and fade as they roll.
- **Drag-and-drop onto destinations:**
  - Drop files on a **folder** → copied into it (or moved, if configured).
  - Drop files on an **app** → opened with that app.
  - Drop files on a **script** → the file paths are passed as arguments.
  - Drop files on a **share** target → sent via a macOS Share Service
    (AirDrop, Messages, Mail, and discovered share extensions).
- **Click a destination** (no drop) → folders open in Finder, apps launch,
  scripts run.
- **Menu-bar item** with Show Palette / Preferences / Manage Destinations /
  Reload Config / Quit.
- **Preferences card** — start at login, hide Dock icon, mouse-shake
  activation, **Light / Dark / Clear appearance**, a **customizable activation
  hotkey** (click the pill and press the new combination), and an **Arc Opens
  From** compass that picks which edge/corner the palette fans out from. Its
  category rows (Folders & Locations, Applications & Scripts, Send & Share) open
  the destinations manager. Adapts to the chosen appearance; dismiss with the
  **✕** button or **Escape**.
- **Destinations manager** — a visual editor to add, remove, and edit
  destinations without hand-writing JSON. Toolbar has **Edit JSON…** (open the
  file in your editor), **Reload** (re-read it from disk), and **Save**
  (auto-closes the window). Close with **Escape**, and it follows the appearance
  preference live.
- Runs as a background **agent** (no Dock icon).

## Requirements

- macOS 13 or later.
- The **Swift toolchain**. The free *Xcode Command Line Tools* are enough —
  install with:
  ```sh
  xcode-select --install
  ```
  (Full Xcode also works.)

## Installation

### Build from source

From the project root:

```sh
chmod +x build.sh
./build.sh
open ./dist/Quick_Drop.app
```

`build.sh` compiles the package and assembles `Quick_Drop.app` inside `dist/`
with a proper `Info.plist`, then ad-hoc code-signs it.

To install it permanently:

```sh
cp -R ./dist/Quick_Drop.app /Applications/
```

Quick test without bundling:

```sh
swift run
```

### Install a prebuilt copy (shared with you)

If someone sent you a `Quick_Drop.zip`:

1. Unzip it, then drag `Quick_Drop.app` into `/Applications`.
2. **Right-click** the app → **Open** → **Open** (do *not* double-click the
   first time — that path gives no "Open" button).
3. If macOS still refuses, run:
   ```sh
   xattr -dr com.apple.quarantine /Applications/Quick_Drop.app
   ```

> **First launch / Gatekeeper:** because the app is ad-hoc signed (not from a
> paid Apple Developer ID), macOS may block the first open. Use the right-click
> → **Open** step above, or go to **System Settings → Privacy & Security** and
> click **Open Anyway**.

### Share a build with someone else

Package the bundle with `ditto` (not Finder's Compress) so the signature and
symlinks survive:

```sh
ditto -c -k --keepParent ./dist/Quick_Drop.app ~/Desktop/Quick_Drop.zip
```

Then AirDrop / email / upload `~/Desktop/Quick_Drop.zip`.

## Configure your destinations

Two ways to manage destinations, easiest first:

1. **Destinations manager (recommended).** Menu-bar icon → **Manage
   Destinations…**, or click any category row in the **Preferences** card. Add,
   remove, and edit entries with a form — no JSON required. **Save** persists
   and closes the window; **Escape** closes without saving.
2. **Edit the JSON directly.** In the manager, click **Edit JSON…** to open the
   file in your editor, then **Reload** to pick the changes back up (the palette
   also reloads each time you summon it, and **Reload Config** in the menu does
   the same).

The JSON lives at:

```
~/Library/Application Support/Quick_Drop/destinations.json
```

Each entry looks like:

```json
[
  { "name": "Desktop",  "kind": "folder", "path": "~/Desktop" },
  { "name": "Archive",  "kind": "folder", "path": "~/Documents/Archive", "moveOnDrop": true },
  { "name": "Preview",  "kind": "app",    "path": "/System/Applications/Preview.app" },
  { "name": "Resize",   "kind": "script", "path": "~/bin/resize.sh", "iconPath": "~/Pictures/resize.png" },
  { "name": "AirDrop",  "kind": "share",  "path": "", "service": "airdrop" }
]
```

Fields:

| field        | required | meaning |
|--------------|----------|---------|
| `name`       | yes      | label shown under the icon |
| `kind`       | yes      | `folder`, `app`, `script`, or `share` |
| `path`       | yes      | filesystem path; `~` is expanded (use `""` for `share`) |
| `service`    | share    | share service key — `airdrop`, `messages`, `mail`, `notes`, or `reminders` |
| `moveOnDrop` | no       | folders only — `true` moves instead of copies |
| `iconPath`   | no       | custom icon image (png/icns); otherwise the system icon is used |
| `enabled`    | no       | `false` hides the destination from the palette |
| `accepts`    | no       | file categories to accept, e.g. `["image","pdf"]`; omit for any |

## Change the hotkey

Open the menu-bar icon → **Preferences…**, click the **Activation Hotkey** pill
(it turns "Type shortcut…"), and press the new combination. It takes effect
immediately and persists across launches. The default is **⌃⌥Space**.

> A combination already claimed by the system or another app may silently fail
> to register — if the palette stops responding to your chosen keys, pick a
> different combination.

The default lives in `Shortcut.default` (`Sources/Quick_Drop/Shortcut.swift`).

## Project layout

```
Quick_Drop/
├── Package.swift
├── README.md
├── LICENSE
├── SECURITY.md
├── build.sh                      # compiles + assembles dist/Quick_Drop.app
├── .github/workflows/ci.yml      # macOS build check
└── Sources/Quick_Drop/
    ├── main.swift                # entry point, accessory app policy
    ├── AppDelegate.swift         # menu-bar item + hotkey wiring
    ├── HotKey.swift              # Carbon global hotkey
    ├── Shortcut.swift            # customizable hotkey model (keycode + modifiers)
    ├── ShakeDetector.swift       # mouse-shake activation
    ├── PaletteController.swift   # summons/dismisses the window at the cursor
    ├── RadialMenuView.swift      # the ring + draggable item buttons
    ├── ArcOrigin.swift           # where the ring blooms from
    ├── Destination.swift         # model + drop/click behavior
    ├── FileCategory.swift        # file-type categories for `accepts`
    ├── ShareExtensionInvoker.swift # routes drops to share services
    ├── InstalledApps.swift       # app discovery for the picker
    ├── Store.swift               # JSON load/save of destinations
    ├── Preferences.swift         # user settings model
    ├── PreferencesController.swift # the preferences card UI
    └── SettingsController.swift  # destination management UI
```
