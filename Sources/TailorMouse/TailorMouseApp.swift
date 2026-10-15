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
            CommandGroup(replacing: .appTermination) {
                Button("Quit TailorMouse") { model.stop(); NSApp.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
            }
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
    init(model: AppModel, tabName: String = "Buttons") {
        self.model = model; self.catalog = model.devices
        _tab = State(initialValue: EditorTab(rawValue: tabName) ?? .buttons)
    }
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
                            ButtonsView(profile: profile, indicators: model.indicators)
                        } else if tab == .chords {
                            ChordsView(profile: profile, indicators: model.indicators, prepareRecording: { if model.isRunning { model.stop() }; catalog.refresh() })
                                .padding(.horizontal, 12).padding(.bottom, 4)
                        } else {
                            ScrollView {
                                Group {
                                    switch tab {
                                    case .wheel: WheelView(profile: profile, indicators: model.indicators)
                                    case .chords: EmptyView()
                                    case .cursor: CursorView(profile: profile, pointer: model.pointer, sensitivity: model.sensitivity)
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
    @ObservedObject var indicators: InputIndicators
    @State private var page = 0
    @State private var modifiers = ModifierMask()
    @State private var selection: ButtonSelection?
    init(profile: Binding<MouseProfile>, indicators: InputIndicators = InputIndicators(), initialPage: Int = 0) {
        _profile = profile; self.indicators = indicators; _page = State(initialValue: initialPage)
    }
    private var effectiveModifiers: ModifierMask { modifiers.union(indicators.modifiers) }
    private var ordinaryButtons: [Int] { VisibleMouseButtons.ordinary(observed: indicators.observedOrdinaryButtons) }
    private var rows: [Int] {
        page == 0 ? Array(ordinaryButtons.prefix(8)) : page == 1 ? Array(100..<106) : Array(106..<112)
    }
    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(spacing: 0) {
                VStack(spacing: 18) {
                    ForEach(rows, id: \.self) { button in
                        HStack(spacing: 8) {
                            Text(compactButtonTitle(button)).frame(width: 104, alignment: .trailing)
                            let binding = profile.actionBinding(for: button, modifiers: effectiveModifiers)
                            Button {
                                selection = ButtonSelection(button: button, modifiers: effectiveModifiers, binding: binding)
                            } label: {
                                HStack(spacing: 7) {
                                    Image(systemName: actionSymbol(binding.action)).font(.system(size: 12))
                                    Text(bindingTitle(binding, button: button)).lineLimit(1)
                                    Spacer(minLength: 0)
                                }.padding(.horizontal, 8).frame(height: 23)
                                    .frame(maxWidth: .infinity).background(CompactTheme.control, in: RoundedRectangle(cornerRadius: 5))
                                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(indicators.detectedButton == button ? CompactTheme.accent : .clear, lineWidth: 2))
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
                    if ordinaryButtons.count > 8 { Menu {
                        ForEach(Array(ordinaryButtons.dropFirst(8)), id: \.self) { button in
                            Button(compactButtonTitle(button)) {
                                selection = ButtonSelection(button: button, modifiers: effectiveModifiers,
                                    binding: profile.actionBinding(for: button, modifiers: effectiveModifiers))
                            }
                        }
                    } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.button).buttonStyle(.plain).help("Other detected mouse buttons") }
                }.padding(.bottom, 3)
            }.frame(maxWidth: .infinity)
            VStack(spacing: 12) {
                Spacer(minLength: 25)
                MouseIllustration(sidePanel: page > 0, selectedButton: indicators.detectedButton).frame(width: 188, height: 190)
                    .onHover { indicators.hover($0) }
                Text(indicators.detectedButton.map(compactButtonTitle) ?? indicators.inspectionMessage)
                    .font(.system(size: 10)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).foregroundStyle(.secondary)
                Spacer(minLength: 16)
                Text(effectiveModifiers.isEmpty ? "Default mapping" : "\(effectiveModifiers.title) mapping")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                CompactModifierPicker(modifiers: $modifiers, pressed: indicators.modifiers)
            }.frame(width: 180).padding(.bottom, 4)
        }.padding(.horizontal, 24).padding(.top, 2)
            .onDisappear { indicators.hover(false) }
            .onReceive(indicators.$detectionGeneration) { _ in
                if let button = indicators.detectedButton { page = button >= 106 ? 2 : button >= 100 ? 1 : 0 }
            }
            .sheet(item: $selection) { selected in
                ButtonActionSheet(title: compactButtonTitle(selected.button), initial: selected.binding,
                    inherited: selected.modifiers.isEmpty ? MouseProfile().actionBinding(for: selected.button) : profile.actionBinding(for: selected.button),
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
    let wheel: Bool
    let save: (ActionBinding, Bool) -> Void
    @State private var draft: ActionBinding
    @Environment(\.dismiss) private var dismiss
    init(title: String, initial: ActionBinding, inherited: ActionBinding, isModifier: Bool, wheel: Bool = false,
         save: @escaping (ActionBinding, Bool) -> Void) {
        self.title = title; self.inherited = inherited; self.isModifier = isModifier; self.wheel = wheel; self.save = save
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
            CategoryPicker(binding: $draft, wheel: wheel)
            VStack(spacing: 0) {
                ForEach(0..<4) { index in
                    HStack {
                        Text(index == 0 ? (wheel && draft.action == .passthrough ? "Native scrolling" : bindingTitle(draft, button: 100)) : " ").lineLimit(1)
                        Spacer()
                    }.padding(.horizontal, 8).frame(height: 24)
                        .background(index == 0 ? Color.white.opacity(0.16) : index % 2 == 0 ? Color.white.opacity(0.025) : Color.clear)
                }
            }.overlay(Rectangle().stroke(CompactTheme.border, lineWidth: 1))
            ActionDetails(binding: $draft, wheel: wheel)
            Spacer(minLength: 6)
            HStack {
                Button(isModifier ? "Use Default Mapping" : "Restore Defaults") { draft = inherited }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("OK") { save(draft, isModifier && draft == inherited); dismiss() }.buttonStyle(CompactConfirmationStyle())
                    .keyboardShortcut(.defaultAction).disabled((draft.action == .shortcut && draft.shortcut == nil) || (draft.action == .open && (draft.openTarget?.isEmpty ?? true)))
            }
        }.padding(20).frame(width: 520, height: 400).font(.system(size: 13))
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
            Text("Mouse handling starts only when you press Start. Cursor tracking changes apply while Running and restore when you press Stop.")
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
        VStack(alignment: .leading, spacing: 12) {
            CategoryPicker(binding: $binding)
            ActionDetails(binding: $binding)
        }
    }
}

private struct CategoryPicker: View {
    @Binding var binding: ActionBinding
    var wheel = false
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: actionSymbol(binding.action))
            Picker("Action", selection: Binding(get: { ActionCategory.category(for: binding.action, wheel: wheel) }, set: { category in
                binding.action = category.actions[0]
            })) {
                ForEach(ActionCategory.allCases.dropLast()) { Text($0.rawValue).tag($0) }
                Divider()
                Text(ActionCategory.none.rawValue).tag(ActionCategory.none)
            }.labelsHidden().frame(width: 230)
        }
    }
}

private struct ActionDetails: View {
    @Binding var binding: ActionBinding
    var wheel = false
    private var category: ActionCategory { .category(for: binding.action, wheel: wheel) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if category == .shortcut {
                ShortcutRecorder(shortcut: $binding.shortcut)
                ModifierPicker(modifiers: Binding(get: { binding.shortcut?.modifiers ?? [] }, set: { flags in
                    var shortcut = binding.shortcut ?? Shortcut(keyCode: 0); shortcut.modifiers = flags; binding.shortcut = shortcut
                }))
                if wheel {
                    Text("Wheel shortcuts run once per scroll step.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Picker("Behavior", selection: Binding(get: { binding.shortcutBehavior ?? .tap }, set: { binding.shortcutBehavior = $0 == .tap ? nil : $0 })) {
                        ForEach(ShortcutBehavior.allCases) { Text($0.title).tag($0) }
                    }
                    Text(binding.shortcutBehavior == .repeatWhileHeld ? "Keeps the key down and repeats at your keyboard's rate until you release the button." :
                         binding.shortcutBehavior == .hold ? "Keeps the key down until you release the button." : "Runs once per button press.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if binding.shortcut?.functionKey != nil {
                    Text("F21–F24 use macOS function characters; the receiving app must support them.").font(.caption).foregroundStyle(.secondary)
                }
            } else if category == .click {
                Picker("Behavior", selection: $binding.action) {
                    Text("Click").tag(ButtonAction.mouseClick)
                    Text("Original input (Passthrough)").tag(ButtonAction.passthrough)
                }
                if binding.action == .mouseClick {
                    Picker("Click", selection: $binding.mouseButton) {
                        ForEach(0..<5, id: \.self) { Text(buttonTitle($0)).tag($0) }
                    }
                }
            } else if category == .scroll {
                if wheel {
                    Picker("Behavior", selection: $binding.action) {
                        Text("Native scrolling").tag(ButtonAction.passthrough)
                        Text("Custom scrolling").tag(ButtonAction.scroll)
                    }
                }
                if binding.action == .scroll {
                    HStack {
                        Stepper("Vertical: \(binding.scrollY)", value: $binding.scrollY, in: -50...50)
                        Stepper("Horizontal: \(binding.scrollX)", value: $binding.scrollX, in: -50...50)
                    }
                    Text("Positive scrolls up / left; negative scrolls down / right.").font(.caption).foregroundStyle(.secondary)
                }
            } else if [.system, .zoom, .music].contains(category) {
                Picker("Command", selection: $binding.action) { ForEach(category.actions) { Text($0.title).tag($0) } }
            } else if category == .open {
                HStack {
                    TextField("File, application or web address", text: Binding(get: { binding.openTarget ?? "" }, set: { binding.openTarget = $0 }))
                        .textFieldStyle(.roundedBorder)
                    Button("Choose…") {
                        let panel = NSOpenPanel(); panel.canChooseDirectories = true
                        if panel.runModal() == .OK { binding.openTarget = panel.url?.path }
                    }
                }
            } else if category == .snapping {
                Picker("Destination", selection: Binding(get: { binding.snapDestination ?? "screen" }, set: { binding.snapDestination = $0 })) {
                    Text("Current display center").tag("screen")
                    Text("Front window center").tag("window")
                }
            } else {
                Text(category == .none ? "No action while TailorMouse is running." : category == .mission ? "Show Mission Control." : "Switch to the next application.")
                    .font(.caption).foregroundStyle(.secondary)
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
            Menu {
                ForEach(ShortcutKeyGroup.allCases, id: \.self) { group in
                    Menu(group.rawValue) {
                        ForEach(ShortcutKeyChoice.choices(in: group)) { key in
                            Button(key.title) {
                                stopRecording()
                                shortcut = key.shortcut(modifiers: shortcut?.modifiers ?? [])
                            }
                        }
                    }
                }
            } label: { Image(systemName: "chevron.down") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 24).disabled(recording)
                .accessibilityLabel("Choose hotkey").help("Choose a key without pressing it, including F1–F24.")
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
            let scalar = event.charactersIgnoringModifiers?.unicodeScalars.first?.value
            let functionKey = scalar.flatMap { (0xF718...0xF71B).contains($0) ? Int($0 - 0xF703) : nil }
            shortcut = Shortcut(keyCode: functionKey == nil ? event.keyCode : 127, modifiers: mask, functionKey: functionKey)
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

private struct WheelEditSelection: Identifiable {
    let direction: WheelDirection
    let modifiers: ModifierMask
    let binding: ActionBinding
    var id: String { direction.rawValue }
}
private struct WheelView: View {
    @Binding var profile: MouseProfile
    @ObservedObject var indicators: InputIndicators
    @State private var horizontal = false
    @State private var modifiers = ModifierMask()
    @State private var selected: WheelEditSelection?
    private var effective: ModifierMask { modifiers.union(indicators.modifiers) }
    private var directions: [WheelDirection] { horizontal ? [.left, .right] : [.up, .down] }
    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 9) {
                SpeedSlider(title: "Vertical", value: $profile.wheelSpeed, range: 0.25...4)
                SpeedSlider(title: "Horizontal", value: $profile.horizontalWheelSpeed, range: 0.25...4)
                HStack {
                    Toggle("Reverse vertical", isOn: $profile.invertWheel)
                    Toggle("Reverse horizontal", isOn: $profile.invertHorizontalWheel)
                    Spacer()
                }.controlSize(.small)
            }
            Divider()
            HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 24) {
                    Picker("Wheel", selection: $horizontal) {
                        Text("Vertical").tag(false); Text("Horizontal").tag(true)
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 200)
                    VStack(spacing: 2) {
                        wheelRow(directions[0])
                        HStack {
                            Color.clear.frame(width: 76, height: 20)
                            Button {
                                profile.swapWheelBindings(horizontal: horizontal, modifiers: effective)
                            } label: {
                                Image(systemName: "arrow.left.arrow.right")
                                    .font(.system(size: 15, weight: .semibold))
                                    .frame(width: 32, height: 20).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                                .frame(maxWidth: .infinity)
                                .help("Swap \(directions[0].title) and \(directions[1].title) assignments")
                                .accessibilityLabel("Swap \(directions[0].title) and \(directions[1].title) assignments")
                        }
                        wheelRow(directions[1])
                    }
                }.frame(maxWidth: .infinity)
                VStack {
                    MouseIllustration().frame(width: 135, height: 120).scaleEffect(0.7)
                        .overlay(Image(systemName: horizontal ? "arrow.left.arrow.right" : "arrow.up.arrow.down")
                            .font(.system(size: 27, weight: .bold)).foregroundStyle(.red).rotationEffect(.degrees(25)))
                    CompactModifierPicker(modifiers: $modifiers, pressed: indicators.modifiers)
                }.frame(width: 155)
            }
            Text("Choose an action for each roll direction. Speed and reverse settings apply to scrolling; held modifiers select their own mappings.")
                .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }.sheet(item: $selected) { selection in
            let flags = selection.modifiers
            let direction = selection.direction
            ButtonActionSheet(title: direction.title, initial: selection.binding,
                inherited: flags.isEmpty ? MouseProfile().wheelBinding(direction: direction) : profile.wheelBinding(direction: direction),
                isModifier: !flags.isEmpty, wheel: true) { binding, inherit in
                let key = flags.isEmpty ? direction.rawValue : "\(direction.rawValue):\(flags.rawValue)"
                if inherit { profile.wheelBindings.removeValue(forKey: key) } else { profile.wheelBindings[key] = binding }
            }
        }
    }
    private func wheelRow(_ direction: WheelDirection) -> some View {
        HStack {
            Text(direction.title).frame(width: 76, alignment: .trailing)
            let binding = profile.wheelBinding(direction: direction, modifiers: effective)
            Button { selected = WheelEditSelection(direction: direction, modifiers: effective, binding: binding) } label: {
                HStack {
                    Image(systemName: binding.action == .passthrough ? "arrow.up.arrow.down" : actionSymbol(binding.action))
                    Text(binding.action == .passthrough ? "Scroll \(direction.rawValue.capitalized)" : bindingTitle(binding, button: 100)).lineLimit(1)
                    Spacer()
                }.padding(.horizontal, 8).frame(height: 24)
                    .background(CompactTheme.control, in: RoundedRectangle(cornerRadius: 4))
            }.buttonStyle(.plain)
        }
    }
}

private struct SpeedSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var body: some View {
        HStack(spacing: 16) {
            Text(title).frame(width: 65, alignment: .leading)
            Slider(value: Binding(get: { value }, set: { value = ($0 * 20).rounded() / 20 }), in: range)
            Text(String(format: "%.2f×", value)).monospacedDigit().frame(width: 56)
        }
    }
}

private struct CursorView: View {
    @Binding var profile: MouseProfile
    @ObservedObject var pointer: NativePointer
    @ObservedObject var sensitivity: NagaSensitivity
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Speed").font(.headline)
            VStack(spacing: 14) {
                TrackingControl(title: "Acceleration", value: Binding(get: { profile.pointerAcceleration ?? min(5, pointer.systemAcceleration) }, set: { profile.pointerAcceleration = $0 }), range: 0...5)
                TrackingControl(title: "Sensitivity", value: Binding(get: { profile.pointerSensitivity ?? 1 }, set: { profile.pointerSensitivity = $0 }), range: 0.25...4)
            }.disabled(!pointer.supported)
            Button("Reset Tracking Adjustments") { profile.pointerAcceleration = nil; profile.pointerSensitivity = nil }
            Text(pointer.message).font(.callout).foregroundStyle(.secondary)
            Divider()
            Text("Hardware DPI · Wired Naga Pro").font(.headline)
            HStack(spacing: 10) {
                Text("DPI").frame(width: 90, alignment: .trailing)
                TextField("DPI", value: $sensitivity.requestedDPI, format: .number.precision(.fractionLength(0)))
                    .textFieldStyle(.roundedBorder).frame(width: 62).onSubmit { sensitivity.apply() }
                Slider(value: Binding(get: { log2(max(100, sensitivity.requestedDPI)) }, set: {
                    sensitivity.requestedDPI = min(20000, max(100, (pow(2, $0) / 100).rounded() * 100))
                }), in: log2(100)...log2(20000), onEditingChanged: { editing in if !editing { sensitivity.apply() } })
                    .accessibilityLabel("Hardware DPI")
            }.disabled(sensitivity.busy || sensitivity.current == nil)
            HStack {
                Button("Read from mouse", action: sensitivity.refresh).disabled(sensitivity.busy)
                Button("Restore previous DPI", action: sensitivity.restore).disabled(sensitivity.busy || !sensitivity.canRestore)
                Spacer()
                ForEach([800, 1600, 3200], id: \.self) { dpi in
                    Button("\(dpi)") { sensitivity.requestedDPI = Double(dpi); sensitivity.apply() }
                        .disabled(sensitivity.busy || sensitivity.current == nil)
                }
            }
            Text(sensitivity.message).font(.caption).foregroundStyle(.secondary)
            Text("DPI applies on slider release or Return. Wired USB only; Restore undoes DPI.")
                .font(.caption).foregroundStyle(.secondary)
        }.onAppear { pointer.inspect(); sensitivity.refresh() }
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in pointer.inspect() }
    }
}

private struct TrackingControl: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    private var boundedValue: Binding<Double> {
        Binding(get: { value }, set: { candidate in
            guard candidate.isFinite else { return }
            value = min(range.upperBound, max(range.lowerBound, (candidate * 100).rounded() / 100))
        })
    }
    var body: some View {
        HStack(spacing: 10) {
            Text(title).frame(width: 90, alignment: .trailing)
            TextField(title, value: boundedValue, format: .number.precision(.fractionLength(2)))
                .textFieldStyle(.roundedBorder).monospacedDigit().frame(width: 62)
                .accessibilityLabel("\(title) value")
            Slider(value: boundedValue, in: range).accessibilityLabel(title)
            Stepper(title, value: boundedValue, in: range, step: 0.05)
                .labelsHidden().accessibilityLabel("Adjust \(title)")
        }
    }
}

private struct ChordEditorSelection: Identifiable {
    let chord: ChordBinding
    let isNew: Bool
    var id: UUID { chord.id }
}

private func chordTitle(_ chord: ChordBinding) -> String {
    chord.modifiers.title + chord.buttons.map(ChordButtonChoices.title).joined(separator: " + ")
}

private struct ChordsView: View {
    @Binding var profile: MouseProfile
    @ObservedObject var indicators: InputIndicators
    var prepareRecording: () -> Void = {}
    @State private var selectedID: UUID?
    @State private var editor: ChordEditorSelection?
    var body: some View {
        VStack(spacing: 8) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Text("Chord").frame(width: 196, alignment: .leading).padding(.leading, 8)
                    Divider()
                    Text("Function").frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 7)
                    Divider()
                    Text("Note").frame(width: 62, alignment: .leading).padding(.leading, 6)
                }.font(.system(size: 11, weight: .medium)).frame(height: 27)
                    .background(Color.black.opacity(0.25))
                Divider()
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(profile.chords.enumerated()), id: \.element.id) { index, chord in
                            chordRow(chord, index: index)
                        }
                        if profile.chords.isEmpty {
                            Text("No chords yet. Click + to add one.").font(.system(size: 12)).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity).padding(.vertical, 70)
                        }
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }.background(Color.black.opacity(0.08)).overlay(Rectangle().stroke(CompactTheme.border))
            HStack(spacing: 6) {
                HStack(spacing: 1) {
                    Button { editor = ChordEditorSelection(chord: ChordBinding(buttons: [100,101], binding: ActionBinding(action: .disabled)), isNew: true) } label: { Image(systemName: "plus").frame(width: 22, height: 20) }
                        .accessibilityLabel("Add chord").help("Add chord")
                    Button {
                        profile.chords.removeAll { $0.id == selectedID }; selectedID = nil
                    } label: { Image(systemName: "minus").frame(width: 22, height: 20) }
                        .disabled(selectedID == nil).accessibilityLabel("Remove selected chord").help("Remove selected chord")
                }.buttonStyle(.bordered).controlSize(.small)
                Button("Edit…") { if let chord = profile.chords.first(where: { $0.id == selectedID }) { open(chord) } }
                    .controlSize(.small).disabled(selectedID == nil)
                Spacer()
                Text("Click a function to edit its chord.").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .sheet(item: $editor) { selection in
                ChordActionSheet(initial: selection.chord, isNew: selection.isNew, indicators: indicators, prepareRecording: prepareRecording) { updated in
                    if let index = profile.chords.firstIndex(where: { $0.id == updated.id }) { profile.chords[index] = updated }
                    else { profile.chords.append(updated) }
                    selectedID = updated.id
                }
            }
            .onDisappear { indicators.cancelRecording() }
    }
    private func chordRow(_ chord: ChordBinding, index: Int) -> some View {
                            HStack(spacing: 0) {
                                Text(chordTitle(chord)).lineLimit(1).truncationMode(.middle)
                                    .frame(width: 196, alignment: .leading).padding(.leading, 8)
                                    .help(chordTitle(chord))
                                Divider()
                                Button { open(chord) } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: actionSymbol(chord.binding.action)).font(.system(size: 12))
                                        Text(bindingTitle(chord.binding, button: 100)).lineLimit(1)
                                        Spacer(minLength: 0)
                                    }.padding(.horizontal, 7).frame(height: 22)
                                        .background(CompactTheme.control.opacity(0.8), in: RoundedRectangle(cornerRadius: 5))
                                }.buttonStyle(.plain).padding(.horizontal, 6)
                                    .accessibilityLabel("Edit function for \(chordTitle(chord))")
                                Divider()
                                Text(chord.note ?? "").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                    .frame(width: 62, alignment: .leading).padding(.leading, 6).help(chord.note ?? "")
                            }.frame(height: 39).font(.system(size: 12))
                                .background(selectedID == chord.id ? Color.white.opacity(0.16) : index.isMultiple(of: 2) ? Color.black.opacity(0.19) : Color.white.opacity(0.025))
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) { open(chord) }
                                .onTapGesture { selectedID = chord.id }
    }
    private func open(_ chord: ChordBinding) { selectedID = chord.id; editor = ChordEditorSelection(chord: chord, isNew: false) }
}

private struct ChordActionSheet: View {
    @ObservedObject var indicators: InputIndicators
    let prepareRecording: () -> Void
    let save: (ChordBinding) -> Void
    @State private var draft: ChordBinding
    @State private var buttonsExpanded: Bool
    @Environment(\.dismiss) private var dismiss
    init(initial: ChordBinding, isNew: Bool, indicators: InputIndicators, prepareRecording: @escaping () -> Void, save: @escaping (ChordBinding) -> Void) {
        self.indicators = indicators; self.prepareRecording = prepareRecording; self.save = save
        _draft = State(initialValue: initial); _buttonsExpanded = State(initialValue: isNew)
    }
    private var canSave: Bool {
        draft.isValid && (draft.binding.action != .shortcut || draft.binding.shortcut != nil) &&
            (draft.binding.action != .open || !(draft.binding.openTarget?.isEmpty ?? true))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(chordTitle(draft)).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                .frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(CompactTheme.panel, in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(CompactTheme.border))
            HStack {
                CategoryPicker(binding: $draft.binding).disabled(indicators.recording)
                Spacer()
                if draft.buttons.first.map({ $0 < 3 }) == true {
                    Label("Caution", systemImage: "exclamationmark.triangle.fill").font(.system(size: 11))
                        .padding(.horizontal, 8).padding(.vertical, 3).background(CompactTheme.control.opacity(0.7), in: RoundedRectangle(cornerRadius: 4))
                        .help("When a primary click is pressed first, its normal click and drag still occur.")
                }
            }
            VStack(spacing: 0) {
                ForEach(0..<4) { index in
                    HStack {
                        Text(index == 0 ? bindingTitle(draft.binding, button: 100) : " ").lineLimit(1)
                        Spacer()
                    }.padding(.horizontal, 8).frame(height: 24)
                        .background(index == 0 ? Color.white.opacity(0.16) : index.isMultiple(of: 2) ? Color.white.opacity(0.025) : Color.clear)
                }
            }.overlay(Rectangle().stroke(CompactTheme.border))
            ActionDetails(binding: $draft.binding).disabled(indicators.recording)
            DisclosureGroup("Chord buttons & note", isExpanded: $buttonsExpanded) {
                ScrollView {
                    ChordTriggerControls(chord: $draft, indicators: indicators, prepareRecording: prepareRecording)
                        .padding(.top, 8)
                }.frame(height: 164)
            }
            Spacer(minLength: 4)
            HStack {
                Button("Restore Defaults") { draft.binding = ActionBinding(action: .disabled) }.disabled(indicators.recording)
                Spacer()
                Button("Cancel") { indicators.cancelRecording(); dismiss() }.keyboardShortcut(.cancelAction)
                Button("OK") { indicators.cancelRecording(); save(draft); dismiss() }
                    .buttonStyle(CompactConfirmationStyle()).keyboardShortcut(.defaultAction).disabled(!canSave || indicators.recording)
            }
        }.padding(20).frame(width: 540, height: buttonsExpanded ? 598 : 420).font(.system(size: 13))
            .background(CompactTheme.background).tint(CompactTheme.accent).preferredColorScheme(.dark)
            .onDisappear { indicators.cancelRecording() }
    }
}

private struct ChordTriggerControls: View {
    @Binding var chord: ChordBinding
    @ObservedObject var indicators: InputIndicators
    var prepareRecording: () -> Void = {}
    @State private var recordingTitle = ""
    private var extras: [Int] { ChordButtonChoices.extras(observed: indicators.observedOrdinaryButtons, saved: chord.buttons) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if indicators.recording || !indicators.recordingMessage.isEmpty {
                HStack {
                    Text(indicators.recording ? "\(recordingTitle): \(indicators.recordingMessage)" : indicators.recordingMessage).font(.caption)
                    Spacer()
                    if indicators.recording { Button("Cancel recording", action: indicators.cancelRecording).controlSize(.small) }
                }
            }
            ForEach(chord.buttons.indices, id: \.self) { index in
                HStack(spacing: 8) {
                    let title = index == 0 ? "First" : index == 1 ? "Second" : "Button \(index + 1)"
                    Text(title).frame(width: 48, alignment: .trailing)
                    Menu {
                        Section("Mouse clicks") {
                            ForEach(ChordButtonChoices.clicks, id: \.self) { button in
                                Button(ChordButtonChoices.title(button)) { chord.buttons[index] = button }
                            }
                        }
                        Menu("Side buttons") {
                            ForEach(ChordButtonChoices.sideButtons, id: \.self) { button in
                                Button(ChordButtonChoices.title(button)) { chord.buttons[index] = button }
                            }
                        }
                        if !extras.isEmpty {
                            Menu("Other detected or saved buttons") {
                                ForEach(extras, id: \.self) { button in
                                    Button(ChordButtonChoices.title(button)) { chord.buttons[index] = button }
                                }
                            }
                        }
                    } label: { Text(ChordButtonChoices.title(chord.buttons[index])).frame(maxWidth: .infinity) }
                        .menuStyle(.button).accessibilityLabel("\(title) mouse button")
                    Button("Record") {
                        prepareRecording(); recordingTitle = "Recording \(title.lowercased()) button"
                        indicators.recordButton { button in
                            guard chord.buttons.indices.contains(index) else { return }; chord.buttons[index] = button
                        }
                    }.controlSize(.small).accessibilityLabel("Record \(title.lowercased()) mouse button")
                }.disabled(indicators.recording)
            }
            if !chord.isValid { Text("Choose different mouse buttons.").font(.caption).foregroundStyle(.orange) }
            ModifierPicker(modifiers: $chord.modifiers).disabled(indicators.recording)
            TextField("Note", text: Binding(get: { chord.note ?? "" }, set: { chord.note = $0.isEmpty ? nil : String($0.prefix(160)) }))
                .textFieldStyle(.roundedBorder).disabled(indicators.recording)
            Text("Record stops handling. Press Start to resume after editing.").font(.caption).foregroundStyle(.secondary)
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
    shortcut.modifiers.title + shortcut.keyTitle
}

#if TAILORMOUSE_UI_PREVIEW
func chordEditorPreview(expanded: Bool = false) -> some View {
    let indicators = InputIndicators()
    indicators.monitoringEnabled = false
    return ChordActionSheet(initial: ChordBinding(buttons: [0,3], binding: ActionBinding(action: .shortcut, shortcut: Shortcut(keyCode: 51))),
        isNew: expanded, indicators: indicators, prepareRecording: {}, save: { _ in })
}
func buttonEditorPreview(functionKey: Int? = nil) -> some View {
    ButtonActionSheet(title: "Button 7",
        initial: ActionBinding(action: .shortcut, shortcut: functionKey.map { Shortcut(keyCode: 127, modifiers: .option, functionKey: $0) } ?? Shortcut(keyCode: 123, modifiers: .option)),
        inherited: ActionBinding(), isModifier: false, save: { _, _ in })
}
func sideButtonsPreview() -> some View {
    let indicators = InputIndicators()
    indicators.monitoringEnabled = false
    indicators.detectedButton = 109
    return ButtonsView(profile: .constant(MouseProfile()), indicators: indicators, initialPage: 2)
        .padding(.vertical, 18).frame(width: 640, height: 370)
        .background(CompactTheme.panel).preferredColorScheme(.dark)
}
#endif
