#if TAILORMOUSE_UI_PREVIEW
import AppKit
import SwiftUI
import TailorMouseCore

/// Separate render executable, excluded from the app. No event tap or hardware
/// writes; the view model is explicitly isolated from user settings/status.
@main
struct TailorMouseUIRender {
    static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let model = AppModel(preview: true)
        model.configuration.defaultProfile.bindings = [
            "0": ActionBinding(action: .shortcut, shortcut: Shortcut(keyCode: 123, modifiers: [.command, .shift])),
            "1": ActionBinding(action: .shortcut, shortcut: Shortcut(keyCode: 124, modifiers: [.command, .shift])),
            "3": ActionBinding(action: .shortcut, shortcut: Shortcut(keyCode: 38)),
            "4": ActionBinding(action: .shortcut, shortcut: Shortcut(keyCode: 37)),
            "5": ActionBinding(action: .disabled),
            "6": ActionBinding(action: .shortcut, shortcut: Shortcut(keyCode: 123, modifiers: .option)),
            "7": ActionBinding(action: .shortcut, shortcut: Shortcut(keyCode: 124, modifiers: .option))
        ]
        try render(ContentView(model: model), size: NSSize(width: 680, height: 510), to: output.appendingPathComponent("buttons.png"))
        try render(buttonEditorPreview(), size: NSSize(width: 520, height: 400), to: output.appendingPathComponent("button-editor.png"))
        try render(buttonEditorPreview(functionKey: 24), size: NSSize(width: 520, height: 400), to: output.appendingPathComponent("button-editor-f24.png"))
        try render(sideButtonsPreview(), size: NSSize(width: 640, height: 370), to: output.appendingPathComponent("side-buttons.png"))
        model.indicators.modifiers = [.command, .option]
        try render(ContentView(model: model), size: NSSize(width: 680, height: 510), to: output.appendingPathComponent("buttons-modifiers.png"))
        try render(ContentView(model: model, tabName: "Wheel"), size: NSSize(width: 680, height: 510), to: output.appendingPathComponent("wheel.png"))
        try render(ContentView(model: model, tabName: "Cursor"), size: NSSize(width: 680, height: 510), to: output.appendingPathComponent("cursor.png"))
    }
    private static func render<V: View>(_ view: V, size: NSSize, to url: URL) throws {
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("No bitmap") }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("No PNG") }
        try png.write(to: url)
        window.orderOut(nil)
        print("Rendered \(url.path)")
    }
}
#endif
