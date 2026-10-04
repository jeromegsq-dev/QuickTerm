# QuickTerm

A native macOS terminal that drops down when you push the pointer to the top centre of your screen.

**[Download](https://github.com/jeromegsq-dev/QuickTerm/releases/latest/download/QuickTerm.dmg)** · [Website](https://jeromegsq-dev.github.io/QuickTerm/) · macOS 14 or later, Apple silicon and Intel

## Use

| | |
|---|---|
| Open or close | Push the pointer against the top centre of the screen |
| Close | `Esc` at the prompt |
| New tab / close tab | `⌘T` / `⌘W` |
| Switch tab | `⌘1`–`⌘9`, `⌃Tab`, `⌃⇧Tab` |
| Resize | Drag the bottom or side edges |

Shells keep running while the panel is hidden. The panel stays off full-screen Spaces and hides when you switch Space.

## Build

Requires Xcode 16 or later.

```sh
./Scripts/build-app.sh   # build/QuickTerm.app, ad-hoc signed
./Scripts/release.sh     # signed and notarized build/QuickTerm.dmg
```

Terminal emulation by [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm).

## License

[MIT](LICENSE)
