# Mission Wheel

Mission Wheel is a small macOS utility that maps a horizontal mouse wheel to the trackpad-style Mission Control gestures:

- Wheel right/up: Mission Control
- Wheel left/down: Application Windows / App Expose for the frontmost app
- After Mission Control opens, the next horizontal wheel tick in either direction selects the hovered window
- Left-click or Escape clears that pending wheel-selection state

It was built and tested for the **ProtoArc EM11 Pro** vertical mouse. That mouse has a side horizontal scroll wheel whose physical motion maps naturally to the macOS trackpad gesture mental model: up for Mission Control, down for Application Windows.

Mission Wheel may also work with other mice that expose a horizontal wheel to macOS as standard horizontal scroll events. It does not try to identify mouse hardware.

Mission Wheel is not affiliated with ProtoArc or Apple.

## Requirements

- macOS 13 or later
- Swift toolchain / Xcode command line tools for building from source
- Accessibility permission for the installed app

## Install

Recommended once, before installing:

```sh
scripts/create-signing-identity.sh
```

That creates a local self-signed code-signing identity named **Mission Wheel Signing**. The installer auto-detects it so macOS can keep the Accessibility approval across rebuilds. macOS may show one-time keychain or trust prompts while creating the identity, and codesign may ask for keychain access the first time it signs the app.

```sh
scripts/install.sh
```

The installer builds a release binary, creates an agent-style app bundle, signs it, registers a LaunchAgent, and starts it:

```text
~/Applications/Mission Wheel.app
~/Library/LaunchAgents/com.danielbriskin.mission-wheel.plist
```

The app has no Dock icon or menu bar item.

On first install, macOS may prompt for Accessibility permission. If it does not, open:

```text
System Settings > Privacy & Security > Accessibility
```

Enable **Mission Wheel**. The LaunchAgent waits for the grant and should begin reacting shortly afterward; no manual kickstart is needed just to finish the permission step.

Check status:

```sh
launchctl print gui/$UID/com.danielbriskin.mission-wheel | grep 'state ='
```

## Configuration

If your mouse reports the horizontal wheel directions in the opposite order:

```sh
SWAP_DIRECTIONS=1 scripts/install.sh
```

To tune the suppression window for repeated scroll ticks:

```sh
COOLDOWN_MS=300 scripts/install.sh
```

To leave specific frontmost apps alone:

```sh
EXCLUDE_BUNDLE_IDS=com.apple.Terminal,com.apple.finder scripts/install.sh
```

To sign with a specific code signing identity instead of the auto-detected **Mission Wheel Signing** identity:

```sh
CODESIGN_IDENTITY="Developer ID Application: Your Name" scripts/install.sh
```

If no identity is provided or auto-detected, the installer falls back to ad-hoc signing.

## Troubleshooting

If Mission Wheel appears in Accessibility but does not react, check the LaunchAgent state and logs:

```sh
launchctl print gui/$UID/com.danielbriskin.mission-wheel | grep 'state ='
```

Installed logs:

```text
~/Library/Logs/mission-wheel.log
~/Library/Logs/mission-wheel.err.log
```

For ad-hoc signed installs only: if Mission Wheel appears in Accessibility but does not react after a rebuild, macOS may be holding a stale approval for the previous code hash:

```sh
tccutil reset Accessibility com.danielbriskin.mission-wheel
scripts/install.sh
```

Then enable **Mission Wheel** again in Accessibility. To avoid this after the first approval, create the stable local signing identity with `scripts/create-signing-identity.sh` and reinstall.

Useful diagnostics:

```sh
swift run mission-wheel check
swift run mission-wheel --help
swift run mission-wheel listen
swift run -c release mission-wheel trigger-application-windows
swift run -c release mission-wheel trigger-mission-control
swift run -c release mission-wheel run --debug
swift run -c release mission-wheel run --exclude-bundle-id com.apple.Terminal
```

Runtime `run` options include `--cooldown-ms <ms>`, `--swap-directions`, `--exclude-bundle-id <id>` (repeatable, comma-separated accepted), and `--debug`.

## Uninstall

```sh
scripts/uninstall.sh
```

## Development

```sh
swift test
swift build -c release
```

## License

MIT
