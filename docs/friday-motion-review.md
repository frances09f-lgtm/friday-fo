# Friday motion review

Settings was implemented first. The current v78 Settings screen, not the draft's sample features, is the inventory source. Nothing is renamed, hidden or removed. Existing expansion groups remain expandable. Settings now uses 16px outer inset, 28px opaque tonal cards, 12px inter-card spacing, 18px inner spacing and theme-based text colors instead of fixed translucent Stitch surfaces. Voice is a tonal card. Keys retain obscuring, controllers and the same save action.

Preserved Settings inventory:
- Get started: Assistant setup; Contact nicknames & saved matches; Connected devices.
- Voice: Speak replies out loud.
- More settings: AI & models; Qwen local model; On-device fallback; Cloud fallback keys; Gemini API key; Groq API key; OpenRouter API key; Groq model; OpenRouter model; Advanced legacy .task installer on Android/iOS; Advanced legacy model URL (.task); Install specified .task and install status.
- Permissions & phone controls: Accessibility Service; Microphone and Android permission state; Floating assistant and overlay permission state; Spotify controls on Android.
- Commands; secure-storage/screen-safety note; Windows Groq voice note; Save changes and Settings saved result.

All existing destinations and their actions remain: Assistant setup (overlay/mic/default assistant, preview bar, show/hide bubble, power-button diagnostics, system session test, invocation history, refresh); local model setup (download/test, load/test, cancel, progress, diagnostics); Agent Mode (accessibility, local setup, task/voice/start/stop, diagnostics, examples); Connected devices (local link, address/key, QR, scan, pair, disconnect); Spotify controls (notification access/status); Commands (every existing group and example). Their model, phone and service logic is unchanged.

Measured web motion: cubic-bezier(.34,1.56,.64,1) spring and cubic-bezier(.22,1,.36,1) out. Main entrances: 480ms, y18px and scale .96 to 1. Settings: 450ms, x28px and scale .97. Buttons .94; icons .88/.90; release 300ms. Switches: 400ms spring, 16px thumb grows 1.35x and travels 20px. Dock: 56x32px selected pill expands from .35 to 1 over 500ms, selected icon scales 1.12. The web has separate expanding pills; physically sliding the selected indicator and staggered list entrances are requested additions.

The native dock remains a 68px NavigationBar with the same labels, keyboard behavior and accessibility; its indicator is animated behind the native controls. Tabs stay lazy and mounted in an IndexedStack. Reduced motion skips custom effects. No sample data or fake permission/update behavior is copied from the draft.

Nothing is phone-tested. No merge, tag, release or update-feed write. The v78 floating bar, overlay files, Android services, business/model code, version and release workflows are untouched. The CI-only APK is arm64 and debug-signed; it is not an update for an existing release-key install. Do not uninstall an existing app and lose data to test it.
