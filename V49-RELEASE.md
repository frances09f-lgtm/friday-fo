# Friday v49 - bar volume evidence and completion guards (phone test candidate)

The user reported that "Set volume to 40" from v48's bar said Done without changing volume. The exact failure has not been reproduced on his phone; the expected v48 percent path already returned measured text, so the installed/runtime discrepancy remains unexplained.

This candidate:
- Stops speech capture before executing bar actions to avoid recognition teardown overlapping volume writes.
- Rejects empty or bare Done/OK/success volume results instead of promoting them into completion.
- Sets an exact media-stream index for both percent and step commands.
- Requires two readbacks at 350ms and 1000ms and a stable output-device list before reporting a volume change.
- Shows build version, stream, requested percent/direction, initial and target indices, audio mode, output types, and both readbacks.
- Leaves volume results in the bar for inspection and screenshots; other commands retain their existing dismissal behavior.

224 Flutter tests pass, including the actual bar/controller/parser/channel route for "Set volume to 40" with a mocked native result. Native phone volume behavior is not proved by this test. Preview uses a simulated failure response, not a phone observation. Analysis has no errors (existing warnings/info remain).

Retest from bar on phone speaker: "Set volume to 40". Read the build and measured indices. A target already reached is reported as no change. A remote cast speaker has separate controls. Existing .task model, runtime, Spotify controls and screen workflows are unchanged.
