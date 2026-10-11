import AppKit
import SwiftUI
import TailorMouseCore

@main
struct TailorMouseApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 760, minHeight: 500)
                .onAppear { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
        }.defaultSize(width: 860, height: 550)
        MenuBarExtra("TailorMouse", systemImage: model.isRunning ? "computermouse.fill" : "computermouse") {
            Text(model.isRunning ? "TailorMouse is running" : "TailorMouse is stopped")
            Button("Show TailorMouse") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
            }
            Button("Stop mouse handling") { model.stop() }.disabled(!model.isRunning)
            Divider()
            Button("Quit TailorMouse") { model.stop(); NSApp.terminate(nil) }.keyboardShortcut("q")
        }
    }
}

struct ContentView: View {
    @ObservedObject var model: AppModel
    private var profile: Binding<MouseProfile> {
        Binding(get: { model.selectedProfile }, set: { model.updateProfile($0) })
    }
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Label("TailorMouse", systemImage: "computermouse.fill").font(.title3.bold())
                Text("Your mouse. Your shortcuts.").font(.caption).foregroundStyle(.secondary)
                List(selection: $model.selectedID) {
                    Label("Default", systemImage: "slider.horizontal.3").tag(model.configuration.defaultProfile.id)
                    ForEach(model.configuration.appProfiles) { item in
                        Label(item.name, systemImage: "app").tag(item.id)
                    }
                }.listStyle(.sidebar)
                Button(action: model.addApplication) { Label("Add application…", systemImage: "plus") }
                if model.selectedID != model.configuration.defaultProfile.id {
                    Button("Remove profile", role: .destructive, action: model.removeSelected)
                }
                Spacer(minLength: 0)
            }.padding(20).frame(width: 225).background(.quaternary.opacity(0.35))
            Divider()
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.selectedProfile.name).font(.largeTitle.bold())
                        Text(model.selectedProfile.bundleIdentifier ?? "Used when an application has no custom profile.")
                            .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Spacer()
                    Circle().fill(model.isRunning ? Color.green : Color.gray).frame(width: 8, height: 8)
                    Text(model.isRunning ? "Running" : "Stopped").font(.callout)
                }
                GroupBox("Wheel") {
                    VStack(alignment: .leading, spacing: 14) {
                        Toggle("Reverse wheel direction", isOn: profile.invertWheel)
                        HStack {
                            Text("Speed")
                            Slider(value: profile.wheelSpeed, in: 0.25...4, step: 0.25)
                            Text(String(format: "%.2f×", model.selectedProfile.safeWheelSpeed)).monospacedDigit().frame(width: 55)
                        }
                        Text("Applies to discrete wheel ticks. Continuous scrolling keeps its original behavior.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(10)
                }
                GroupBox("Side buttons") {
                    VStack(alignment: .leading, spacing: 14) {
                        Picker("Button 4 · event 3", selection: profile.button3) {
                            ForEach(ButtonAction.allCases) { Text($0.title).tag($0) }
                        }
                        Picker("Button 5 · event 4", selection: profile.button4) {
                            ForEach(ButtonAction.allCases) { Text($0.title).tag($0) }
                        }
                        Text("Back and Forward send ⌘[ and ⌘]. Support varies by application.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(10)
                }
                Spacer(minLength: 0)
                HStack(alignment: .center, spacing: 18) {
                    Text(model.status).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if model.isRunning {
                        Button("Stop", action: model.stop).controlSize(.large)
                    } else {
                        Button("Start", action: model.start).buttonStyle(.borderedProminent).controlSize(.large)
                    }
                }
            }.padding(28)
        }
    }
}
