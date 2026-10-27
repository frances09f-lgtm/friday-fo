One fix:

- The floating bar now comes back by itself. Before, Android (especially OxygenOS battery management) could quietly end Friday's overlay service, and the bar and bubble never returned until they were switched on again by hand. Friday now remembers that you left the bubble on and brings it back after the system kills it, after a reboot, after a Friday update, and whenever you open Friday. Turning it off still turns it fully off: Hide in the panel, the notification, or Settings > Assistant setup. Nothing else about the bar changed - same size, same gestures, same look.

Built on v1.0.162, with all of its changes kept (including in-app updates and trading from Friday). Signed with the same key, so it installs over v1.0.162, v1.0.161, v80 or v1.0.160 with no uninstall. Checked by CI tests, not yet on a phone.

v1.0.164 adds one diagnostic on top of v1.0.163: if the bubble fails to reappear after Friday asks the system for it, the attempt is recorded in the Assistant invocation log so a missing bar can be told apart from a bar that was never requested.
