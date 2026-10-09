# Friday v50 - foreground volume window for overlay commands (test candidate)

User device evidence: OnePlus Android16. On v49 the overlay command set volume60 returned initial39/160, target96/160 and two unchanged readbacks. The same command works in the main Friday app. This supports a foreground/background restriction rather than parsing failure.

Bar-issued volume changes now show an honest foreground Activity. The overlay is temporarily hidden and made non-focusable. Friday waits for the Activity's window focus, then uses the existing exact media-index write and two-readback verification. Result returns to the bar. Main-app volume behavior remains unchanged.

No settings changes, audio playback trick, developer option or security bypass. Locked phone refuses the command. Cancel, close, timeout and interrupted verification do not claim success. Diagnostics remain visible.

Requires CI compilation/tests and real OnePlus overlay retest. No phone success has been observed for this candidate. Existing .task model/runtime and other features are unchanged.

Background media-write behavior references:
https://precisevolume.phascinate.com/docs/device-specific-tweaks-fixes-etc/oneplus-oppo-devices/
https://stackoverflow.com/questions/72398470/why-volume-is-not-changing-when-app-is-running-background
