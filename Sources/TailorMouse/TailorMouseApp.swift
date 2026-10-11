import AppKit
import SwiftUI
import TailorMouseCore

#if !TAILORMOUSE_UI_PREVIEW
@main
struct TailorMouseApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup("TailorMouse") {
            ContentView(model: model)
                .frame(minWidth: 660, minHeight: 490)
                .onAppear {
                    NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true)
                    Self.adoptCompactWindowOnce()
                }
        }
        .defaultSize(width: 680, height: 510)
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
    private static func adoptCompactWindowOnce() {
        // SwiftUI restores the previous sidebar window's larger dimensions.
        // Adopt the new layout once; subsequent user resizing is preserved.
        let key = "compactWindowLayoutAdopted"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard let window = NSApp.windows.first(where: { $0.canBecomeMain }) else { return }
            window.setContentSize(NSSize(width: 680, height: 510))
            window.center()
            UserDefaults.standard.set(true, forKey: key)
        }
    }
}

#endif

private enum EditorTab: String, CaseIterable, Identifiable {
    case buttons = "Buttons", wheel = "Wheel", chords = "Chords", cursor = "Cursor", device = "Device", support = "Support"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .buttons: return "computermouse"
        case .wheel: return "arrow.up.arrow.down"
        case .cursor: return "cursorarrow"
        case .chords: return "square.stack.3d.up"
        case .device: return "antenna.radiowaves.left.and.right"
        case .support: return "questionmark.circle"
        }
    }
}

struct ContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var catalog: DeviceCatalog
    @State private var tab = EditorTab.buttons
    init(model: AppModel) { self.model = model; self.catalog = model.devices }
    private var profile: Binding<MouseProfile> {
        Binding(get: { model.selectedProfile }, set: { model.updateProfile($0) })
    }
    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 10) {
                Button(model.isRunning ? "Stop" : "Start") {
                    if model.isRunning { model.stop() } else { model.start() }
                }.buttonStyle(CompactButtonStyle()).frame(width: 50)
                    .help(model.isRunning ? "Stop mouse handling" : "Start mouse handling")
                Menu {
                    Button("Default") { model.selectedID = model.configuration.defaultProfile.id }
                    ForEach(model.configuration.appProfiles) { item in
                        Button(item.name) { model.selectedID = item.id }
                    }
                } label: {
                    HStack {
                        Text(model.selectedID == model.configuration.defaultProfile.id ? "Default" : model.selectedProfile.name)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .bold))
                            .padding(3).background(CompactTheme.accent, in: RoundedRectangle(cornerRadius: 3))
                    }.padding(.leading, 10).padding(.trailing, 2).frame(height: 21)
                        .background(CompactTheme.control, in: RoundedRectangle(cornerRadius: 4))
                }.menuStyle(.button).buttonStyle(.plain).frame(width: 245).accessibilityLabel("Profile")
                Menu("Edit") {
                    Button("Add application…", action: model.addApplication)
                    Button("Remove this profile", action: model.removeSelected)
                        .disabled(model.selectedID == model.configuration.defaultProfile.id)
                    Divider()
                    Button("Import profiles…", action: model.importProfiles)
                    Button("Export profiles…", action: model.exportProfiles)
                }.menuStyle(.button).buttonStyle(.plain).padding(.horizontal, 10).padding(.vertical, 3)
                    .background(CompactTheme.control, in: RoundedRectangle(cornerRadius: 4)).tint(.white)
                Spacer(minLength: 12)
                Menu {
                    Button("Razer Naga Pro · every connection") { model.setDeviceFamily("razer.naga.pro") }
                    Button("All mice") { model.setDeviceFamily(nil) }
                    ForEach(Array(Set(catalog.devices.map { $0.identity.canonicalFamily })).filter { $0 != "razer.naga.pro" }.sorted(), id: \.self) { family in
                        Button(family) { model.setDeviceFamily(family) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Circle().fill(catalog.connections.contains { $0.identity.canonicalFamily == model.configuration.selectedDeviceFamily } ? Color.green : Color.gray).frame(width: 7, height: 7)
                        Text(model.configuration.selectedDeviceFamily == nil ? "All mice" : model.configuration.selectedDeviceFamily == "razer.naga.pro" ? "Naga Pro" : "Selected mouse")
                        Spacer()
                    }.padding(.horizontal, 7).padding(.vertical, 3)
                        .background(CompactTheme.control.opacity(0.55))
                }.menuStyle(.button).buttonStyle(.plain).frame(width: 205).tint(.white)
            }.controlSize(.small)
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 5).fill(CompactTheme.panel)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(CompactTheme.border, lineWidth: 1))
                    .padding(.top, 10)
                VStack(spacing: 0) {
                    Picker("Settings", selection: $tab) {
                        ForEach(EditorTab.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 460).accessibilityLabel("Settings tabs")
                    Group {
                        if tab == .buttons {
                            ButtonsView(profile: profile)
                        } else {
                            ScrollView {
                                Group {
                                    switch tab {
                                    case .wheel: WheelView(profile: profile)
                                    case .chords: ChordsView(profile: profile)
                                    case .cursor: CursorView(sensitivity: model.sensitivity)
                                    case .device: DevicesView(model: model, catalog: catalog)
                                    case .support: SupportView(model: model)
                                    case .buttons: EmptyView()
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(22)
                            }
                        }
                    }.id(model.selectedID).padding(.top, 14)
                }.padding(.bottom, 14)
            }
            HStack(spacing: 8) {
                Circle().fill(model.isRunning ? Color.green : Color.gray).frame(width: 6, height: 6)
                Text(model.status).font(.system(size: 10)).lineLimit(2).help(model.status)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Permissions…", action: model.openPermissions).controlSize(.mini)
            }.foregroundStyle(.secondary)
        }.padding(.horizontal, 19).padding(.top, 20).padding(.bottom, 10)
            .font(.system(size: 13)).tint(CompactTheme.accent)
            .background(CompactTheme.background).preferredColorScheme(.dark)
    }
}

private struct ButtonSelection: Identifiable {
    let button: Int
    let modifiers: ModifierMask
    let binding: ActionBinding
    var id: Int { button }
}

private struct ButtonsView: View {
    @Binding var profile: MouseProfile
    @State private var page = 0
    @State private var modifiers = ModifierMask()
    @State private var selection: ButtonSelection?
    init(profile: Binding<MouseProfile>, initialPage: Int = 0) {
        _profile = profile; _page = State(initialValue: initialPage)
    }
    private var rows: [Int] {
        page == 0 ? Array(0..<8) : page == 1 ? Array(100..<106) : Array(106..<112)
    }
    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(spacing: 0) {
                VStack(spacing: 18) {
                    ForEach(rows, id: \.self) { button in
                        HStack(spacing: 8) {
                            Text(compactButtonTitle(button)).frame(width: 104, alignment: .trailing)
                            let binding = profile.actionBinding(for: button, modifiers: modifiers)
                            Button {
                                selection = ButtonSelection(button: button, modifiers: modifiers, binding: binding)
                            } label: {
                                HStack(spacing: 7) {
                                    Image(systemName: actionSymbol(binding.action)).font(.system(size: 12))
                                    Text(bindingTitle(binding, button: button)).lineLimit(1)
                                    Spacer(minLength: 0)
                                }.padding(.horizontal, 8).frame(height: 23)
                                    .frame(maxWidth: .infinity).background(CompactTheme.control, in: RoundedRectangle(cornerRadius: 5))
                            }.buttonStyle(.plain).help("Edit \(compactButtonTitle(button))")
                        }
                    }
                }
                Spacer(minLength: 16)
                HStack(spacing: 10) {
                    ForEach(0..<3) { index in
                        Button { page = index } label: {
                            Circle().fill(page == index ? Color.white.opacity(0.9) : Color.white.opacity(0.3)).frame(width: 9, height: 9)
                        }.buttonStyle(.plain)
                            .accessibilityLabel(index == 0 ? "Mouse buttons" : index == 1 ? "Side buttons 1 through 6" : "Side buttons 7 through 12")
                            .help(index == 0 ? "Mouse buttons" : index == 1 ? "Side buttons 1–6" : "Side buttons 7–12")
                    }
                    Menu {
                        ForEach(8..<32, id: \.self) { button in
                            Button(compactButtonTitle(button)) {
                                selection = ButtonSelection(button: button, modifiers: modifiers,
                                    binding: profile.actionBinding(for: button, modifiers: modifiers))
                            }
                        }
                    } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.button).buttonStyle(.plain).help("More mouse buttons")
                }.padding(.bottom, 3)
            }.frame(maxWidth: .infinity)
            VStack(spacing: 12) {
                Spacer(minLength: 25)
                MouseIllustration(sidePanel: page > 0).frame(width: 188, height: 220)
                Spacer(minLength: 16)
                Text(modifiers.isEmpty ? "Default mapping" : "\(modifiers.title) mapping")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                CompactModifierPicker(modifiers: $modifiers)
            }.frame(width: 180).padding(.bottom, 4)
        }.padding(.horizontal, 24).padding(.top, 2)
            .sheet(item: $selection) { selected in
                ButtonActionSheet(title: compactButtonTitle(selected.button), initial: selected.binding,
                    inherited: modifiers.isEmpty ? MouseProfile().actionBinding(for: selected.button) : profile.actionBinding(for: selected.button),
                    isModifier: !selected.modifiers.isEmpty) { binding, useInherited in
                    if selected.modifiers.isEmpty {
                        profile.bindings[String(selected.button)] = binding
                        if selected.button == 3 { profile.button3 = binding.action }
                        if selected.button == 4 { profile.button4 = binding.action }
                    } else {
                        let key = "\(selected.button):\(selected.modifiers.rawValue)"
                        if useInherited { profile.modifierBindings.removeValue(forKey: key) }
                        else { profile.modifierBindings[key] = binding }
                    }
                }
            }
    }
}

private func compactButtonTitle(_ button: Int) -> String {
    if button >= 100 { return "Side Button \(button - 99)" }
    switch button {
    case 0: return "Left Button"
    case 1: return "Right Button"
    case 2: return "Middle Button"
    default: return "Button \(button + 1)"
    }
}

private func actionSymbol(_ action: ButtonAction) -> String {
    switch action {
    case .disabled: return "nosign"
    case .passthrough, .mouseClick: return "computermouse.fill"
    case .scroll: return "arrow.up.arrow.down"
    default: return "keyboard"
    }
}

private func bindingTitle(_ binding: ActionBinding, button: Int) -> String {
    if binding.action == .shortcut { return binding.shortcut.map(shortcutTitle) ?? "Keyboard Shortcut…" }
    if binding.action == .passthrough {
        return button < 3 ? "(\(button == 0 ? "Left Click" : button == 1 ? "Right Click" : "Middle Click"))" : "(Passthrough)"
    }
    if binding.action == .mouseClick { return "(\(buttonTitle(binding.mouseButton)))" }
    if binding.action == .disabled { return "(No Action)" }
    return binding.action.title
}

private struct ButtonActionSheet: View {
    let title: String
    let inherited: ActionBinding
    let isModifier: Bool
    let save: (ActionBinding, Bool) -> Void
    @State private var draft: ActionBinding
    @Environment(\.dismiss) private var dismiss
    init(title: String, initial: ActionBinding, inherited: ActionBinding, isModifier: Bool,
         save: @escaping (ActionBinding, Bool) -> Void) {
        self.title = title; self.inherited = inherited; self.isModifier = isModifier; self.save = save
        _draft = State(initialValue: initial)
    }
    private var shortcutModifiers: Binding<ModifierMask> {
        Binding(get: { draft.shortcut?.modifiers ?? [] }, set: { mask in
            var shortcut = draft.shortcut ?? Shortcut(keyCode: 0); shortcut.modifiers = mask
            draft.shortcut = shortcut
        })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 16, weight: .semibold)).frame(maxWidth: .infinity)
                .padding(.vertical, 10).background(CompactTheme.panel, in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(CompactTheme.border))
            HStack(spacing: 9) {
                Image(systemName: actionSymbol(draft.action))
                Picker("Action", selection: $draft.action) {
                    ForEach(ButtonAction.allCases) { Text($0 == .shortcut ? "Keyboard Shortcut" : $0.title).tag($0) }
                }.labelsHidden().frame(width: 225)
            }
            VStack(spacing: 0) {
                ForEach(0..<4) { index in
                    HStack {
                        Text(index == 0 ? bindingTitle(draft, button: 100) : " ").lineLimit(1)
                        Spacer()
                    }.padding(.horizontal, 8).frame(height: 24)
                        .background(index == 0 ? Color.white.opacity(0.16) : index % 2 == 0 ? Color.white.opacity(0.025) : Color.clear)
                }
            }.overlay(Rectangle().stroke(CompactTheme.border, lineWidth: 1))
            if draft.action == .shortcut {
                ShortcutRecorder(shortcut: $draft.shortcut)
                HStack(spacing: 12) {
                    ForEach([(0, "cmd", ModifierMask.command), (1, "shift", .shift), (2, "option", .option), (3, "control", .control)], id: \.0) { item in
                        Toggle(item.1, isOn: Binding(get: { shortcutModifiers.wrappedValue.contains(item.2) }, set: { enabled in
                            var mask = shortcutModifiers.wrappedValue
                            if enabled { mask.insert(item.2) } else { mask.remove(item.2) }
                            shortcutModifiers.wrappedValue = mask
                        })).toggleStyle(.checkbox)
                    }
                }
                Text("Shortcuts run once per button press.").font(.system(size: 11)).foregroundStyle(.secondary)
            } else if draft.action == .mouseClick {
                Picker("Click", selection: $draft.mouseButton) {
                    ForEach(0..<5, id: \.self) { Text(buttonTitle($0)).tag($0) }
                }
            } else if draft.action == .scroll {
                HStack {
                    Stepper("Vertical: \(draft.scrollY)", value: $draft.scrollY, in: -50...50)
                    Stepper("Horizontal: \(draft.scrollX)", value: $draft.scrollX, in: -50...50)
                }
            } else {
                Text(draft.action == .passthrough ? "Sends the button's original input to the active application." : draft.action == .disabled ? "No action while TailorMouse is running." : "Runs the selected action when you press the button.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            HStack {
                Button(isModifier ? "Use Default Mapping" : "Restore Defaults") { draft = inherited }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("OK") { save(draft, isModifier && draft == inherited); dismiss() }.buttonStyle(CompactConfirmationStyle())
                    .keyboardShortcut(.defaultAction).disabled(draft.action == .shortcut && draft.shortcut == nil)
            }
        }.padding(20).frame(width: 520, height: 360).font(.system(size: 13))
            .background(CompactTheme.background).tint(CompactTheme.accent).preferredColorScheme(.dark)
    }
}

private struct SupportView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("TailorMouse").font(.system(size: 20, weight: .semibold))
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development")")
                .foregroundStyle(.secondary)
            Text("One set of Naga Pro button profiles across USB, Bluetooth and the wireless receiver.")
            Divider()
            Button("Accessibility & Input Monitoring…", action: model.openPermissions)
            Link("Project on GitHub", destination: URL(string: "https://github.com/gaou373/tailormouse")!)
            Text("Mouse handling starts only when you press Start. USB hardware DPI changes are applied separately in Cursor.")
                .font(.caption).foregroundStyle(.secondary)
        }
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
    @ObservedObject var sensitivity: NagaSensitivity
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Find your pace").font(.title2.weight(.semibold))
            GroupBox("Wired Naga Pro sensitivity") {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Lower DPI moves the pointer less. Higher DPI moves it farther.").font(.callout)
                    Slider(value: $sensitivity.requestedDPI, in: 100...20000, step: 100)
                        .accessibilityLabel("Mouse sensitivity in DPI")
                    HStack {
                        Text("DPI")
                        TextField("DPI", value: $sensitivity.requestedDPI, format: .number.precision(.fractionLength(0)))
                            .textFieldStyle(.roundedBorder).frame(width: 100)
                        ForEach([800, 1600, 3200], id: \.self) { dpi in
                            Button("\(dpi)") { sensitivity.requestedDPI = Double(dpi) }
                        }
                        Spacer()
                    }
                    HStack {
                        Button("Read from mouse", action: sensitivity.refresh)
                        Button("Apply to mouse", action: sensitivity.apply).buttonStyle(.borderedProminent)
                            .disabled(sensitivity.current == nil)
                        Button("Restore previous DPI", action: sensitivity.restore)
                            .disabled(!sensitivity.canRestore)
                    }
                    Text(sensitivity.message).font(.callout).foregroundStyle(.secondary)
                }.padding(14)
                    .disabled(sensitivity.busy)
            }
            Text("Apply changes the connected USB mouse for all applications, even while button handling is stopped. This live setting may reset when you reconnect or change the mouse's onboard profile. Bluetooth and receiver sensitivity control is not available yet.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .onAppear { sensitivity.refresh() }
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

#if TAILORMOUSE_UI_PREVIEW
func buttonEditorPreview() -> some View {
    ButtonActionSheet(title: "Button 7",
        initial: ActionBinding(action: .shortcut, shortcut: Shortcut(keyCode: 123, modifiers: .option)),
        inherited: ActionBinding(), isModifier: false, save: { _, _ in })
}
func sideButtonsPreview() -> some View {
    ButtonsView(profile: .constant(MouseProfile()), initialPage: 2)
        .padding(.vertical, 18).frame(width: 640, height: 370)
        .background(CompactTheme.panel).preferredColorScheme(.dark)
}
#endif
