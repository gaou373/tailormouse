import AppKit
import SwiftUI
import TailorMouseCore

@main
struct TailorMouseApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 900, minHeight: 640)
                .onAppear { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
        }
        .defaultSize(width: 1040, height: 740)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Import Profiles…", action: model.importProfiles)
                Button("Export Profiles…", action: model.exportProfiles)
            }
        }
        MenuBarExtra("TailorMouse", systemImage: model.isRunning ? "computermouse.fill" : "computermouse") {
            Text(model.isRunning ? "TailorMouse is running" : "TailorMouse is stopped")
            Button("Show TailorMouse") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
            }
            Button("Stop Mouse Handling", action: model.stop).disabled(!model.isRunning)
            Divider()
            Button("Quit TailorMouse") { model.stop(); NSApp.terminate(nil) }.keyboardShortcut("q")
        }
    }
}

private enum EditorTab: String, CaseIterable, Identifiable {
    case buttons = "Buttons", wheel = "Wheel", cursor = "Cursor", chords = "Chords", device = "Device"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .buttons: return "computermouse"
        case .wheel: return "arrow.up.arrow.down"
        case .cursor: return "cursorarrow"
        case .chords: return "square.stack.3d.up"
        case .device: return "antenna.radiowaves.left.and.right"
        }
    }
}

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var tab = EditorTab.buttons
    private var profile: Binding<MouseProfile> {
        Binding(get: { model.selectedProfile }, set: { model.updateProfile($0) })
    }
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                header
                Picker("Settings", selection: $tab) {
                    ForEach(EditorTab.allCases) { Label($0.rawValue, systemImage: $0.icon).tag($0) }
                }.pickerStyle(.segmented).padding(.horizontal, 26).padding(.bottom, 20)
                Divider()
                ScrollView {
                    Group {
                        switch tab {
                        case .buttons: ButtonsView(profile: profile)
                        case .wheel: WheelView(profile: profile)
                        case .cursor: CursorView(profile: profile)
                        case .chords: ChordsView(profile: profile)
                        case .device: DevicesView(model: model, catalog: model.devices)
                        }
                    }.id(model.selectedID).padding(26).frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider()
                footer
            }.background(Color(nsColor: .windowBackgroundColor))
        }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "computermouse.fill").font(.title2).foregroundStyle(.tint)
                Text("TailorMouse").font(.title3.weight(.semibold))
            }.padding(.top, 28).padding(.horizontal, 20)
            Text("Make every button yours.").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.top, 7)
            Text("PROFILES").font(.caption2.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.top, 32).padding(.bottom, 10)
            List(selection: $model.selectedID) {
                Label("All applications", systemImage: "square.grid.2x2").tag(model.configuration.defaultProfile.id)
                ForEach(model.configuration.appProfiles) { item in
                    Label(item.name, systemImage: "app").tag(item.id)
                }
            }.listStyle(.sidebar)
            HStack {
                Button(action: model.addApplication) { Label("Add application", systemImage: "plus") }.buttonStyle(.borderless)
                Spacer()
                Button(action: model.removeSelected) { Image(systemName: "minus") }
                    .buttonStyle(.borderless).disabled(model.selectedID == model.configuration.defaultProfile.id).help("Remove this application profile")
            }.padding(18)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Label("One profile, every connection", systemImage: "link").font(.caption.weight(.medium))
                Text("Naga Pro mappings follow your mouse across Bluetooth, USB and its wireless receiver.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Import…", action: model.importProfiles)
                    Button("Export…", action: model.exportProfiles)
                }.controlSize(.small).padding(.top, 7)
            }.padding(18)
        }.frame(width: 235).background(Color(nsColor: .controlBackgroundColor))
    }
    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.selectedID == model.configuration.defaultProfile.id ? "All applications" : model.selectedProfile.name).font(.largeTitle.weight(.semibold))
                Text(model.selectedProfile.bundleIdentifier == nil ? "Your default settings. Application profiles override these." : "Custom settings for this application.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(model.isRunning ? .green : .secondary).frame(width: 7, height: 7)
                Text(model.isRunning ? "Running" : "Stopped").font(.caption.weight(.medium))
            }.padding(.horizontal, 12).padding(.vertical, 8).background(.quaternary, in: Capsule())
        }.padding(26)
    }
    private var footer: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.status).font(.callout).fixedSize(horizontal: false, vertical: true)
                if !model.isRunning {
                    Button("Open Accessibility Settings", action: model.openPermissions).buttonStyle(.link).font(.caption)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if model.isRunning {
                Button("Stop", action: model.stop).controlSize(.large)
            } else {
                Button("Start", action: model.start).buttonStyle(.borderedProminent).controlSize(.large)
            }
        }.padding(.horizontal, 26).padding(.vertical, 18)
    }
}

private struct ButtonsView: View {
    @Binding var profile: MouseProfile
    @State private var selectedButton = 100
    @State private var buttonCount = 5
    @State private var modifiers = ModifierMask()
    private var selectedBinding: Binding<ActionBinding> {
        Binding(get: { profile.actionBinding(for: selectedButton, modifiers: modifiers) }, set: { value in
            if modifiers.isEmpty {
                profile.bindings[String(selectedButton)] = value
                if selectedButton == 3 { profile.button3 = value.action }
                if selectedButton == 4 { profile.button4 = value.action }
            } else {
                profile.modifierBindings["\(selectedButton):\(modifiers.rawValue)"] = value
            }
        })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Choose a button").font(.title2.weight(.semibold))
                Text("Select a button below, then choose what it does.").foregroundStyle(.secondary)
                Text("Unassigned Naga side buttons use No action to prevent typing and alert sounds while running. Choose Passthrough to send their original keys.").font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Naga Pro side panel", systemImage: "square.grid.3x3").font(.headline)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(100..<112, id: \.self) { button in
                            Button { selectedButton = button } label: {
                                VStack(spacing: 5) {
                                    Text("\(button - 99)").font(.title3.weight(.semibold))
                                    Text(profile.actionBinding(for: button, modifiers: modifiers).action.title).font(.caption2).lineLimit(1)
                                }.frame(maxWidth: .infinity).frame(height: 62)
                                    .foregroundStyle(selectedButton == button ? Color.white : Color.primary)
                                    .background(selectedButton == button ? Color.accentColor : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
                            }.buttonStyle(.plain)
                        }
                    }
                }.frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 12) {
                    Label("Mouse buttons", systemImage: "computermouse").font(.headline)
                    ForEach(0..<min(buttonCount, 5), id: \.self) { button in mouseRow(button) }
                    if buttonCount > 5 {
                        ScrollView {
                            VStack(spacing: 6) { ForEach(5..<buttonCount, id: \.self) { mouseRow($0) } }
                        }.frame(maxHeight: 160)
                    }
                    Stepper("\(buttonCount) buttons", value: $buttonCount, in: 5...32).font(.caption)
                }.frame(maxWidth: .infinity)
            }
            Divider()
            HStack {
                Text(buttonTitle(selectedButton)).font(.headline)
                Spacer()
                if !modifiers.isEmpty {
                    Button("Use default mapping") { profile.modifierBindings.removeValue(forKey: "\(selectedButton):\(modifiers.rawValue)") }.controlSize(.small)
                }
            }
            ModifierPicker(modifiers: $modifiers)
            ActionEditor(binding: selectedBinding)
            Text(modifiers.isEmpty ? "This mapping applies when no modifier key is held." : "This mapping applies while the selected modifier keys are held. Unassigned combinations use the default mapping.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private func mouseRow(_ button: Int) -> some View {
        Button { selectedButton = button } label: {
            HStack {
                Text(buttonTitle(button)).font(.callout.weight(.medium))
                Spacer()
                Text(profile.actionBinding(for: button, modifiers: modifiers).action.title).font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 12).padding(.vertical, 9)
                .background(selectedButton == button ? Color.accentColor.opacity(0.13) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain)
    }
}

private func buttonTitle(_ button: Int) -> String {
    if button >= 100 { return "Side button \(button - 99)" }
    switch button {
    case 0: return "Left click"
    case 1: return "Right click"
    case 2: return "Middle click"
    case 3: return "Button 4"
    case 4: return "Button 5"
    default: return "Button \(button + 1)"
    }
}

private struct ModifierPicker: View {
    @Binding var modifiers: ModifierMask
    private let items: [(String, ModifierMask)] = [("⌘ Command", .command), ("⇧ Shift", .shift), ("⌥ Option", .option), ("⌃ Control", .control)]
    var body: some View {
        HStack(spacing: 9) {
            Text("With:").font(.callout).foregroundStyle(.secondary)
            ForEach(0..<items.count, id: \.self) { index in
                Toggle(items[index].0, isOn: Binding(get: { modifiers.contains(items[index].1) }, set: { selected in
                    if selected { modifiers.insert(items[index].1) } else { modifiers.remove(items[index].1) }
                })).toggleStyle(.button).controlSize(.small)
            }
        }
    }
}

private struct ActionEditor: View {
    @Binding var binding: ActionBinding
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Action", selection: $binding.action) {
                ForEach(ButtonAction.allCases) { Text($0.title).tag($0) }
            }.frame(maxWidth: 410)
            switch binding.action {
            case .passthrough:
                Text("Sends the original input to the focused app. Naga side buttons can type keys or play an alert when the app cannot use them.").font(.caption).foregroundStyle(.secondary)
            case .disabled:
                Text("Consumes the button without sending an action while TailorMouse is running.").font(.caption).foregroundStyle(.secondary)
            case .shortcut: ShortcutRecorder(shortcut: $binding.shortcut)
            case .mouseClick:
                Picker("Click", selection: $binding.mouseButton) {
                    ForEach(0..<5, id: \.self) { Text(buttonTitle($0)).tag($0) }
                }.frame(maxWidth: 410)
            case .scroll:
                HStack {
                    Stepper("Vertical: \(binding.scrollY)", value: $binding.scrollY, in: -50...50)
                    Stepper("Horizontal: \(binding.scrollX)", value: $binding.scrollX, in: -50...50)
                }
                Text("Positive values scroll up or left; negative values scroll down or right.").font(.caption).foregroundStyle(.secondary)
            default: EmptyView()
            }
        }
    }
}

private struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut?
    @State private var recording = false
    @State private var monitor: Any?
    var body: some View {
        HStack {
            Button(recording ? "Press a shortcut…" : shortcut.map(shortcutTitle) ?? "Record shortcut…") {
                if recording { stopRecording() } else { startRecording() }
            }.frame(minWidth: 160).help("Records a key combination only while this app is focused. Press Escape to cancel.")
            if shortcut != nil { Button("Clear") { stopRecording(); shortcut = nil }.controlSize(.small) }
            if recording { Text("Escape cancels").font(.caption).foregroundStyle(.secondary) }
        }.onDisappear { stopRecording() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in stopRecording() }
    }
    private func startRecording() {
        stopRecording()
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard recording else { return event }
            if event.keyCode == 53 { stopRecording(); return nil }
            var mask = ModifierMask()
            let flags = event.modifierFlags
            if flags.contains(.command) { mask.insert(.command) }
            if flags.contains(.shift) { mask.insert(.shift) }
            if flags.contains(.option) { mask.insert(.option) }
            if flags.contains(.control) { mask.insert(.control) }
            shortcut = Shortcut(keyCode: event.keyCode, modifiers: mask)
            stopRecording()
            return nil
        }
    }
    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }

}

private struct WheelView: View {
    @Binding var profile: MouseProfile
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Scrolling that feels right").font(.title2.weight(.semibold))
            GroupBox("Vertical wheel") {
                VStack(alignment: .leading, spacing: 16) {
                    Toggle("Reverse direction", isOn: $profile.invertWheel)
                    SpeedSlider(title: "Speed", value: $profile.wheelSpeed, range: 0.25...4)
                }.padding(14)
            }
            GroupBox("Horizontal wheel") {
                VStack(alignment: .leading, spacing: 16) {
                    Toggle("Reverse direction", isOn: $profile.invertHorizontalWheel)
                    SpeedSlider(title: "Speed", value: $profile.horizontalWheelSpeed, range: 0.25...4)
                }.padding(14)
            }
            Text("Wheel speed applies to discrete wheel ticks. Smooth scrolling retains its original behavior.").font(.callout).foregroundStyle(.secondary)
        }
    }
}

private struct SpeedSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var body: some View {
        HStack(spacing: 16) {
            Text(title).frame(width: 52, alignment: .leading)
            Slider(value: $value, in: range, step: 0.05)
            Text(String(format: "%.2f×", value)).monospacedDigit().frame(width: 56)
        }
    }
}

private struct CursorView: View {
    @Binding var profile: MouseProfile
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Find your pace").font(.title2.weight(.semibold))
            GroupBox("Pointer") {
                VStack(alignment: .leading, spacing: 18) {
                    SpeedSlider(title: "Speed", value: $profile.pointerSpeed, range: 0.25...4)
                    HStack {
                        Text("1× keeps your current tracking speed.").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Reset") { profile.pointerSpeed = 1 }.controlSize(.small)
                    }
                }.padding(14)
            }
            Text("Pointer speed scales movement on top of macOS tracking. It does not replace the system acceleration curve.").font(.callout).foregroundStyle(.secondary)
        }
    }
}

private struct ChordsView: View {
    @Binding var profile: MouseProfile
    private let allowed = Array(3..<32) + Array(100..<112)
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Two buttons, one action").font(.title2.weight(.semibold))
                    Text("Hold one side button, then press another.").foregroundStyle(.secondary)
                }
                Spacer()
                Button { profile.chords.append(ChordBinding(buttons: [100, 101], binding: ActionBinding(action: .copy))) } label: { Label("Add chord", systemImage: "plus") }
            }
            if profile.chords.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "square.stack.3d.up").font(.system(size: 35)).foregroundStyle(.secondary)
                    Text("No button chords yet").font(.headline)
                    Text("Combine two side buttons to add another shortcut.").foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 60)
            }
            ForEach($profile.chords) { $chord in
                GroupBox {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            chordButton("First", chord: $chord, index: 0)
                            Text("+").foregroundStyle(.secondary)
                            chordButton("Second", chord: $chord, index: 1)
                            Button(role: .destructive) { profile.chords.removeAll { $0.id == chord.id } } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                        }
                        if chord.buttons.count == 2 && chord.buttons[0] == chord.buttons[1] {
                            Text("Choose two different buttons.").font(.caption).foregroundStyle(.orange)
                        }
                        ModifierPicker(modifiers: $chord.modifiers)
                        ActionEditor(binding: $chord.binding)
                    }.padding(12)
                }
            }
            Text("Left, right and middle clicks remain available for normal clicking while a chord is pending.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func chordButton(_ title: String, chord: Binding<ChordBinding>, index: Int) -> some View {
        Picker(title, selection: Binding(get: { chord.wrappedValue.buttons.count > index ? chord.wrappedValue.buttons[index] : 100 + index }, set: { button in
            var values = chord.wrappedValue.buttons
            while values.count <= index { values.append(100 + values.count) }
            values[index] = button
            chord.wrappedValue.buttons = values
        })) {
            ForEach(allowed, id: \.self) { Text(buttonTitle($0)).tag($0) }
        }
    }
}

private struct DevicesView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var catalog: DeviceCatalog
    private var families: [String] { Array(Set(catalog.devices.map { $0.identity.canonicalFamily } + ["razer.naga.pro"])).sorted() }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("Your connected mouse").font(.title2.weight(.semibold))
                Spacer()
                Button { catalog.refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
            }
            Picker("Apply profiles to", selection: Binding(get: { model.configuration.selectedDeviceFamily ?? "*" }, set: { model.setDeviceFamily($0 == "*" ? nil : $0) })) {
                Text("All mice").tag("*")
                ForEach(families, id: \.self) { family in
                    Text(family == "razer.naga.pro" ? "Razer Naga Pro · all connections" : family).tag(family)
                }
            }
            GroupBox("Connections") {
                VStack(alignment: .leading, spacing: 14) {
                    if catalog.connections.isEmpty {
                        Text("No mouse detected. Connect your mouse, then refresh.").foregroundStyle(.secondary)
                    }
                    ForEach(catalog.connections) { device in
                        HStack(spacing: 12) {
                            Image(systemName: device.identity.transport.lowercased().contains("bluetooth") ? "antenna.radiowaves.left.and.right" : "cable.connector").font(.title3).frame(width: 28)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(device.identity.product.isEmpty ? "Mouse" : device.identity.product).font(.headline)
                                Text(device.identity.transport.isEmpty ? "Connection unspecified" : device.identity.transport).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(device.canIdentifyEvents ? "Detected" : "Limited identification")
                                .font(.caption).foregroundStyle(device.canIdentifyEvents ? Color.green : Color.orange)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
            }
            GroupBox("Input activity") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Circle().fill(model.isRunning ? .green : .secondary).frame(width: 7, height: 7)
                        Text(model.isRunning ? model.lastInput : "Press Start to observe input from your selected mouse.").font(.callout).foregroundStyle(.secondary)
                        Spacer()
                    }
                    LabeledContent("Last side-button press", value: model.lastSideButtonPress)
                    LabeledContent("Last side-button release", value: model.lastSideButtonRelease)
                    Text("These two rows keep the latest side-button events visible. Onboard macros can finish before you release the physical button.").font(.caption).foregroundStyle(.secondary)
                }.padding(14)
            }
            if !model.configuration.nagaKeyboardLayouts.isEmpty {
                GroupBox("Side-button calibration") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(model.configuration.nagaKeyboardLayouts.keys.sorted(), id: \.self) { transport in
                            HStack {
                                Text("\(transport) · custom onboard keys")
                                Spacer()
                                Button("Use standard layout") { model.useStandardNagaLayout(transport: transport) }
                            }
                        }
                        Text("Calibration identifies physical buttons. Your button actions and application profiles stay shared across connections.").font(.caption).foregroundStyle(.secondary)
                    }.padding(14)
                }
            }
            Text("Naga Pro uses the same application profiles for Bluetooth, wired USB and the wireless receiver. Verify the twelve side buttons on each connection; device reports can vary.").font(.callout).foregroundStyle(.secondary)
            Text("If clicks appear here but side buttons do not, turn off the Naga in Karabiner-Elements → Devices. Its virtual keyboard hides which physical device sent the key.").font(.callout).foregroundStyle(.secondary)
        }
    }
}

private func shortcutTitle(_ shortcut: Shortcut) -> String {
    let keys: [UInt16: String] = [0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "−", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "Return", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space", 50: "`", 51: "Delete", 53: "Escape", 96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11", 109: "F10", 111: "F12", 118: "F4", 120: "F2", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑"]
    return shortcut.modifiers.title + (keys[shortcut.keyCode] ?? "Key \(shortcut.keyCode)")
}
