TailorMouse 0.4.2 adds a modifier-only mouse action and stops empty shortcut editors from inventing A when a modifier is clicked.

Choose **Modifier Key → Command** to hold Command alone while the mouse button is held. Shift, Option and Control are available too. A keyboard shortcut with no selected key now stays empty when toggling its modifier controls; it only gains a key when you explicitly record or choose one.

Modifier holds start immediately, retain matched releases, coexist with physical keyboard modifiers, and clean up on Stop/disconnect. Existing profiles and configured shortcuts remain unchanged until edited. Wheel-triggered modifier actions use complete taps because scrolling has no physical release.

All 197 core tests pass, including ten new modifier-only cases covering raw reports from all three Naga transports, repeated/chord holds, physical-key ownership, multiple owners, snapshots and recovery. Physical modifier-only acceptance remains separate user testing.

This universal macOS 13+ preview is ad hoc signed, not Apple notarized. Download the DMG or use **Check for Updates…** from 0.4.0 or later. Profiles remain local, and the app reopens stopped.
