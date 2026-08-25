<h1 align="center">FlowTab</h1>

<p align="center">
  <strong>English</strong> | <a href="./README.zh-CN.md">简体中文</a>
</p>

FlowTab is a macOS app switcher designed to stay close to the native `Command + Tab` feel while giving you better control over multi-window switching.

## What You Can Do

- Record seven key-set fields directly from the keyboard; every field accepts any recognized keys and has no app-defined key-count limit
- Switch across app-level and window-level views
- Preview windows and activate a specific window directly
- Quit the highlighted app inside the panel (default `Option + Q`)
- Search with partial match, Chinese tokenization, pinyin, abbreviations, and bundle-id keywords

## Download And Install

Download the DMG from GitHub Releases:

- Universal (Apple Silicon + Intel): `FlowTab-v<version>.dmg`
- Verify it with the accompanying `FlowTab-v<version>.sha256` file.
- Public alpha assets are universal Community Builds signed with the established Apple Development identity. They are unnotarized, so macOS may ask you to confirm the first launch from Finder's Open action.

Install steps:

1. Open the downloaded `.dmg`.
2. Drag `Flow Tab.app` into the `Applications` folder.
3. Launch FlowTab from `Applications`.

Uninstall steps:

1. Quit FlowTab.
2. Move `/Applications/Flow Tab.app` to Trash.

## Required Permissions

For full functionality, grant:

- Accessibility: required for window switching, activation, in-app shortcut monitoring, and arbitrary global key sets
- Screen Recording: required for window previews (switching still works without it)
- Terminal content preview: FlowTab uses Apple Events to read only the currently selected tab in the target Terminal window and renders the preview in memory; tab content is not written to preferences, logs, or files, and is not sent over the network

System paths:

- `System Settings -> Privacy & Security -> Accessibility`
- `System Settings -> Privacy & Security -> Screen Recording`
- `System Settings -> Privacy & Security -> Automation`

## Quick Start

1. Launch FlowTab and press `Option + Tab` to open the switch panel.
2. Press `Tab` to move forward and `Shift + Tab` to move backward.
3. Press `Enter` in the panel to start searching and narrow results.
4. Release a key from the configured primary key set to confirm and switch.

The seven defaults are `Option`, `Shift`, `Tab`, `Q`, `Control`, `Shift`, and
`Tab`. Recording accumulates every simultaneously held key and saves after
the complete set is released. The first four fields are pairwise disjoint, as
are the three in-app fields. Partial reuse across those two families is allowed,
while the five resulting action chords must remain distinct. Invalid input is
rejected with field-level red feedback and the saved value is retained.
Without Accessibility permission, the primary and reverse modifier fields
accept non-empty modifier sets, while the main-key field accepts zero or more
modifiers plus exactly one ordinary or function key. Each valid field edit is
saved independently; remaining incompatible fields keep their field-level
requirement messages. Carbon monitoring resumes automatically after all three
fields form compatible forward and reverse chords. The panel-local quit
shortcut keeps arbitrary key-set support. Previously saved arbitrary main
chords remain stored and resume after Accessibility permission is granted.

## FAQ

1. No windows are listed or a multi-key shortcut does not respond: Accessibility permission is usually missing or not applied. Re-grant it and return to FlowTab so hotkey monitoring can retry.
2. No preview image: confirm Screen Recording permission is granted.
3. Shortcut conflict: change the main shortcut in FlowTab settings.
4. Quit shortcut does not work: make sure the switch panel is visible, then hold the primary key set and press the configured quit key set.

## Feedback

Please report issues and suggestions in GitHub Issues.
