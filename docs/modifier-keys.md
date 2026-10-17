# Modifier-only mouse buttons

In 0.4.2, choose **Modifier Key → Command** in a button's action editor to make it hold Command while the mouse button is held. Release ends the hold. Shift, Option and Control are also available. This action does not send A or another letter. Existing chords still take precedence when they complete; a modifier pressed first remains active as an anchor while the chord runs. Modifier-only chord actions end when either member releases. A scroll action emits a complete modifier tap because scroll has no held state.

**Keyboard Shortcut** remains for shortcuts containing an actual key. Clicking Command/Shift/Option/Control with no key selected leaves the key empty; it does not create A. Pending modifiers are applied if a key is later chosen. Clear removes the key and pending state, Cancel leaves the saved mapping unchanged, and OK stays disabled for an incomplete keyboard shortcut.

Holds are scoped to their physical connection and output owner. Duplicate reports do not retrigger or repeat a modifier. Multiple sources holding the same modifier share one effective key state; releasing one source does not release another's hold. Stop, disconnection and input failure release remaining synthetic ownership. A physically held keyboard modifier is preserved rather than synthetically released. Profiles only change when the user saves an editor.
