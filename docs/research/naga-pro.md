# Razer Naga Pro: current diagnosis

## Observed on this Mac (2026-10-11)

The connected device is `Naga Pro`, vendor `0x1532`, product `0x0092`, transport `Bluetooth Low Energy`, primary usage page 1 / usage 2. Its descriptor includes a keyboard collection (usage page 7, report ID 6), so the twelve-panel buttons must not be treated as twelve ordinary Quartz mouse buttons without further evidence.

SteerMouse initially displayed **partially available**. Its warning explicitly identified `com.razer.appengine.driver` on this same vendor/product/transport and said the driver must be uninstalled if the mouse does not work. The IORegistry attributed an interface to `RazerGenericHIDDriverKit`; `systemextensionsctl list` confirmed the Razer HID Driver Extension was activated and enabled.

Using System Settings → General → Login Items & Extensions → By Category → Driver Extensions, the **Razer HID Driver Extension** was switched off. Its process exited, `systemextensionsctl` reported `[activated disabled]`, and SteerMouse changed to **available** without rebooting. This removes a confirmed access conflict. Whether it fixes every side button remains unverified pending physical tests. The Razer virtual HID extension and other vendors' drivers were left unchanged.

Rollback: switch **Razer HID Driver Extension** back on in the same panel. Razer software may require its driver to control the device. If disabled but still active after a later change, macOS warns that termination is not guaranteed until reboot; do not reboot automatically.

## Static transport/profile facts

The bundled original `Razer Naga Pro.xml` recognizes vendor `0x1532` with product `0x008F` (wired) and `0x0090` (USB/dongle). Bluetooth currently reports `0x0092`. Actual wired/dongle identities still need a capture on this Mac.

The profile lookup predicate recovered from `_PS814fetchDevice` is:

```text
vid == %d AND pid == %d AND mid == %d AND transport == %@
```

This establishes why one physical mouse can acquire separate profile records. A `dataPersonality` alias is applied before the fetch in `_PS802DeviceClass loadMOC`. Other bundled definitions, including the Naga V2 Pro definition, use that alias mechanism; the original Naga Pro definition has no such aliases. V2 mappings are not interchangeable with the original Pro.

Original Pro USB decoding has explicit cases for keyboard usages `0x27`, `0x2D`, `0x2E` corresponding to panel buttons 10, 11, 12 and internal bits 18, 19, 20. Thus missing USB support cannot be inferred merely from the symptoms. Keyboard usage/report traces and driver-free physical tests must distinguish blocked input, onboard assignments, and decoder mismatch.

The helper loads user definitions before bundled definitions and prefers a user definition when personality scores tie. This is a promising reversible route for aliases, but the exact user-definition folder, transport-specific decoder selection, and existing mapping migration must be verified before installation. No profile or device-definition change has been applied.

## Follow-up research (no fixes applied)

First complete the static input and profile architecture reports. Physical analyzer tests are a later corroboration step, not a requirement to start applying changes. They would compare Bluetooth, wired and dongle behavior with the same onboard hardware profile and panel. Static descriptors alone do not prove which events a button emits.

An alias prototype is a potential future implementation. It is deferred at the user's request. The canonical profile would need to preserve existing assignments, not just collapse device names. The discovered override mechanism suggests a signed app-bundle patch may be unnecessary, but decoder/profile interactions remain to be established.

Official context: [Razer Naga Pro support](https://mysupport.razer.com/app/answers/detail/a_id/3260/) describes three connection modes and onboard profiles. [Razer's macOS uninstaller instructions](https://mysupport.razer.com/app/answers/detail/a_id/15233/) provide an alternative if reversible driver disabling does not clear a conflict.
