# UI connections to native implementations

REA decoded five compiled nib documents: the manager's menu, English and Japanese configuration UI, and English and Japanese shortcut-recording windows. Its graph has 3,783 nodes and 2,899 edges. Recognized object/connection decoding was complete for those archives; dynamic views and unrecognized private fields remain unknown.

**Source:** REA `decode_interface_builder` Evidence `ev_b67425e6ce1700aa3d666cbca72bbd1e0bc65128033196775eb24c11fab83eb5`, plus main arm64 symbol inventory. The following addresses are unslid and bound to main SHA-256 `8829a0c3544b76def71808b7ed09af2fd6049bf110a30bab52eaa5571e4dc9f5`.

| Packaged UI action | Target class from nib | Matching arm64 implementation |
| --- | --- | --- |
| `changeButtonSelector:` | `APLControllerClass` | `0x10001a830` |
| `changeButtonCount:` | `APLControllerClass` | `0x10001a86c` |
| `changeScrollText:` | `APLControllerClass` | `0x10001ffa8` |
| `scrollWaySelector:` | `APLControllerClass` | `0x10002006c` |
| `restoreCursorSpeed:` | `APLControllerClass` | `0x10001d248` |
| `changeCursorSpeedLocked:` | `APLControllerClass` | `0x10001d260` |
| `changeCursorSpeedDisabled:` | `APLControllerClass` | `0x10001d190` |
| `changeSmoothScroll:` | `SM608WinDelegate` | `0x100022f78` |
| `applySetting:` | `PS838RecdWinClass` | `0x1000382ec` |

These are actual packaged source-control → action → target connections plus matching implementation symbols. They establish useful entry points for tracing settings changes. They do not establish runtime execution or prove what each implementation does merely from its name.

The English main nib hash is `e2af65308f9915d1a1c74ebeedee001302a870f52761b8185ec8d5e90139001a`; the English recording nib hash is `008cde7289f7002bbcf5592df336aa62b0c583ade797d66ea4659f53ca58236a`. No nib bytes, icons or extracted proprietary interface assets are committed.

Reproduce the cross-check:

```sh
npm run research
node scripts/capture-static.mjs
node scripts/ui-map.mjs
```

The last command writes `.local/evidence/ui-map-summary.json` with source connection IDs, resource hashes and addresses. English/Japanese resource duplication is not two distinct implementations. The cross-check matches Objective-C class and selector names and does not resolve dynamic method replacement or dispatch overrides.
