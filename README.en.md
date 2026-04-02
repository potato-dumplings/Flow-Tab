# FlowTab

[简体中文](./README.md) | [English](./README.en.md)

FlowTab is a macOS app switcher designed to stay close to the native `Command + Tab` feel while giving you better control over multi-window switching.

## What You Can Do

- Customize global switch shortcuts (default `Option + Tab` / `Option + Shift + Tab`)
- Switch across app-level and window-level views
- Preview windows and activate a specific window directly
- Quit the highlighted app inside the panel (default `Option + Q`)
- Search with partial match, Chinese tokenization, pinyin, abbreviations, and bundle-id keywords

## Download And Install

Download the DMG from GitHub Releases:

- Apple Silicon: `flowtab-aarch64-apple-darwin.dmg`
- Intel Mac: `flowtab-x86_64-apple-darwin.dmg`

Install steps:

1. Open the downloaded `.dmg`.
2. Drag `Flow Tab.app` into the `Applications` folder.
3. Launch FlowTab from `Applications`.

Notes:

- Current builds are unsigned and not notarized, so Gatekeeper prompts may appear on first launch.
- If blocked, allow it in `System Settings -> Privacy & Security` and open it again.

## Required Permissions

For full functionality, grant:

- Accessibility: required for window switching and activation
- Screen Recording: required for window previews (switching still works without it)

System paths:

- `System Settings -> Privacy & Security -> Accessibility`
- `System Settings -> Privacy & Security -> Screen Recording`

## Quick Start

1. Launch FlowTab and press `Option + Tab` to open the switch panel.
2. Press `Tab` to move forward and `Shift + Tab` to move backward.
3. Press `Enter` in the panel to start searching and narrow results.
4. Release the main modifier key to confirm and switch.

## FAQ

1. No windows are listed: Accessibility permission is usually missing or not applied. Re-grant permission and relaunch.
2. No preview image: confirm Screen Recording permission is granted.
3. Shortcut conflict: change the main shortcut in FlowTab settings.
4. Quit shortcut does not work: make sure the switch panel is visible, then hold the modifier and press the quit key.

## Feedback

Please report issues and suggestions in GitHub Issues.
