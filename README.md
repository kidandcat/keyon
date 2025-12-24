# KeyOn

A keyboard-driven UI navigation tool for macOS, similar to [Shortcat](https://shortcat.app/). Navigate and click any UI element using only your keyboard.

![KeyOn Demo](https://img.shields.io/badge/macOS-11.0+-blue) ![License](https://img.shields.io/badge/license-MIT-green) ![Zig](https://img.shields.io/badge/zig-0.13+-orange)

## Features

- **Keyboard-driven navigation** - Click any button, link, or UI element by typing its label
- **Global hotkey** - Activate with `Cmd+<` from anywhere
- **Smart labels** - Left-hand keyboard priority for faster typing (A, S, D, F, etc.)
- **Scroll support** - Use `Shift+Arrow` keys to scroll while overlay is active
- **Mouse movement** - Arrow keys move the mouse cursor
- **Left & right click** - `Space` for left click, `Enter` for right click
- **Auto-refresh** - Labels recalculate after scrolling to catch new elements
- **Lightweight** - Built with Zig and raylib for minimal resource usage
- **Menu bar icon** - Easy access to quit the app

## Installation

### Prerequisites

- macOS 11.0 or later
- [Zig](https://ziglang.org/) 0.13 or later
- [raylib](https://www.raylib.com/) 5.0 or later
- [cliclick](https://github.com/BlueM/cliclick) (for reliable clicking)

### Install dependencies

```bash
brew install zig raylib cliclick
```

### Build from source

```bash
git clone https://github.com/kidandcat/keyon.git
cd keyon
zig build -Doptimize=ReleaseFast
```

### Install as application

```bash
# Create app bundle
mkdir -p /Applications/KeyOn.app/Contents/MacOS
cp zig-out/bin/keyon /Applications/KeyOn.app/Contents/MacOS/
cp Info.plist /Applications/KeyOn.app/Contents/

# Sign the app (required for accessibility permissions)
codesign --force --sign - /Applications/KeyOn.app
```

## Usage

### First Run

1. Launch KeyOn from `/Applications/KeyOn.app`
2. Grant **Accessibility** permissions when prompted:
   - System Settings → Privacy & Security → Accessibility → Enable KeyOn
3. The app will appear in your menu bar

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Cmd+<` | Toggle overlay (show/hide labels) |
| `A-Z` | Type label characters to filter |
| `Space` | Left click on element (or at cursor if no label typed) |
| `Enter` | Right click on element (or at cursor if no label typed) |
| `Arrow keys` | Move mouse cursor |
| `Shift+Arrow` | Scroll in that direction |
| `Backspace` | Delete last typed character |
| `Escape` | Close overlay |

### Tips

- Labels prioritize left-hand keys (A, S, D, F, G, Q, W, E, R, T) for faster typing
- Two-letter combos start with left-hand combinations (AS, AD, AF, etc.)
- After scrolling, wait 1 second and labels will refresh to show new elements
- The hint bar at the bottom shows what you've typed

## How It Works

KeyOn uses macOS Accessibility APIs to:
1. Detect the frontmost application
2. Scan for clickable UI elements (buttons, links, text fields, etc.)
3. Display labeled overlays on each element
4. Perform clicks using native mouse events

## Architecture

```
src/
├── main.zig          # Application entry point
├── overlay.zig       # Overlay window rendering (raylib)
├── hotkey.zig        # Global keyboard event handling
├── click.zig         # Mouse click and scroll operations
├── accessibility.zig # macOS Accessibility API integration
├── ui_element.zig    # UI element data structure
├── statusbar.m       # Menu bar icon (Objective-C)
└── statusbar.h       # Menu bar header
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- Inspired by [Shortcat](https://shortcat.app/)
- Scroll implementation based on [robotgo](https://github.com/go-vgo/robotgo)
- Built with [Zig](https://ziglang.org/) and [raylib](https://www.raylib.com/)
