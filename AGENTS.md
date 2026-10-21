# TailorMouse

This is an original macOS app plus an evidence-based investigation of the installed SteerMouse app. Use the pinned `rea-agents` CLI (`npm run rea -- ...`) for artifact work. REA upstream: https://github.com/morluto/rea.

Read `docs/research/README.md` before extending analysis. Distinguish observed static facts, inferred behavior, and unanswered questions. Keep exact target hashes and REA Evidence IDs with findings. Raw evidence belongs in ignored `.local/evidence/`; never commit the target executable, proprietary assets, user settings, account data, or decompiler databases.

App source is independently written Swift. Do not patch SteerMouse, its registration checks, or its preferences. Do not activate remapping, grant accessibility permissions, quit existing mouse managers, or install login items as part of builds/tests. Build with `npm run build:app`, verify with `swift test`. Input changes need tests for matched down/up behavior and recovery. The user authorized automatic handling on app open on 2026-10-20. Preserve the manual Start/Stop controls, attempt automatic start only once per launch when enabled, and never auto-start in previews or tests.

## After-install permission refresh

The user explicitly authorized the assistant on 2026-10-13 to handle TailorMouse's stale permission entries after future authorized installations. This is a separate post-install runtime step, never a build/test action. Use native System Settings UI to refresh only TailorMouse's Accessibility and Input Monitoring entries for `/Applications/TailorMouse.app`, removing the old entry when needed, re-adding the installed copy and verifying it is enabled. Accept the Quit & Reopen prompt for TailorMouse when required. Do not change other apps' permissions, edit TCC databases, weaken macOS protections or start remapping solely as a permission-refresh action. The user separately authorized automatic handling when opening the app on 2026-10-20. If native UI control is unavailable or macOS requires user authentication, explain the concrete blocker and let the user complete that step. Do not request repeated authorization for this same permission refresh.
