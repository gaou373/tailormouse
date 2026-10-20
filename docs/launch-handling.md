# Handling when the app opens

At the user's request on 2026-10-20, 0.4.6 defaults `autoStartOnOpen` to true, including settings saved before this option existed. Support exposes an opt-out. Existing profile actions and shared tracking are preserved. No login item is added.

The production app calls `applicationOpened()` once its window appears. A per-process policy permits only one attempt: reopening a window or switching tabs cannot undo Stop. A new process launch honors the preference again. Automatic start checks both existing input permissions before using the normal Start path; it never loops permission requests. Missing permission, a disconnected selected family, a conflicting mouse manager or startup failure leaves handling stopped with a status message. Manual Start/Stop remains available.

The UI-preview entry point never invokes this path; the model also rejects preview automatic starts. Builds, tests, packaging and installation do not open the production app or start handling. Launching the installed app is a separate authorized runtime action. The user's 2026-10-20 request supersedes the earlier manual-only runtime preference, as reflected in AGENTS.md.

Four policy/persistence tests cover one attempt per process, respecting Stop across window appearances, preview isolation, opt-out and legacy migration. The complete 0.4.6 suite passes 239 core tests and eight native checks; 18 isolated screens render successfully. The universal installed executable has SHA-256 `81c1e784e6876226c5b8d4556a79d805f6015d43b2734bc0db0fef8f62940651`. Saved profile bytes matched the pre-install backup immediately after installation. Permission refresh requires the user to complete the macOS Touch ID/password prompt before installed automatic-start acceptance can be verified.
