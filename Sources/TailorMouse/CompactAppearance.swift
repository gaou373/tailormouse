import SwiftUI
import TailorMouseCore

enum CompactTheme {
    static let background = Color(red: 0.17, green: 0.16, blue: 0.145)
    static let panel = Color(red: 0.215, green: 0.205, blue: 0.19)
    static let control = Color(red: 0.44, green: 0.435, blue: 0.42)
    static let border = Color.white.opacity(0.18)
    static let accent = Color(red: 0.30, green: 0.68, blue: 0.18)
}

struct CompactButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium))
            .frame(maxWidth: .infinity).padding(.vertical, 3)
            .background(CompactTheme.control.opacity(configuration.isPressed ? 0.6 : 1))
            .overlay(Rectangle().stroke(CompactTheme.border))
    }
}

struct CompactConfirmationStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
            .frame(minWidth: 65).padding(.vertical, 3)
            .background(enabled ? CompactTheme.accent.opacity(configuration.isPressed ? 0.7 : 1) : CompactTheme.control,
                in: RoundedRectangle(cornerRadius: 4))
    }
}

struct CompactModifierPicker: View {
    @Binding var modifiers: ModifierMask
    var pressed = ModifierMask()
    private let items: [(String, ModifierMask, String)] = [
        ("⌘", .command, "Command"), ("⇧", .shift, "Shift"),
        ("⌥", .option, "Option"), ("⌃", .control, "Control")
    ]
    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<items.count, id: \.self) { index in
                let item = items[index]
                Button {
                    if modifiers.contains(item.1) { modifiers.remove(item.1) }
                    else { modifiers.insert(item.1) }
                } label: {
                    Text(item.0).font(.system(size: 14, weight: .semibold)).frame(width: 35, height: 22)
                            .background(modifiers.union(pressed).contains(item.1) ? CompactTheme.accent : CompactTheme.control.opacity(0.65))
                }.buttonStyle(.plain).help("Mappings with \(item.2) held")
                    .accessibilityLabel("\(item.2) modifier")
                    .accessibilityValue(modifiers.union(pressed).contains(item.1) ? "Selected" : "Not selected")
            }
        }.overlay(Rectangle().stroke(CompactTheme.border))
    }
}

/// Original vector illustration; no target artwork or extracted assets.
struct MouseIllustration: View {
    var sidePanel = false
    var selectedButton: Int?
    private var bodyPath: Path {
        Path { p in
            p.move(to: CGPoint(x: 30, y: 153))
            p.addCurve(to: CGPoint(x: 82, y: 39), control1: CGPoint(x: 29, y: 116), control2: CGPoint(x: 58, y: 68))
            p.addCurve(to: CGPoint(x: 151, y: 36), control1: CGPoint(x: 97, y: 20), control2: CGPoint(x: 126, y: 20))
            p.addCurve(to: CGPoint(x: 171, y: 94), control1: CGPoint(x: 172, y: 47), control2: CGPoint(x: 179, y: 70))
            p.addCurve(to: CGPoint(x: 116, y: 172), control1: CGPoint(x: 163, y: 120), control2: CGPoint(x: 143, y: 160))
            p.addCurve(to: CGPoint(x: 30, y: 153), control1: CGPoint(x: 85, y: 189), control2: CGPoint(x: 32, y: 177))
            p.closeSubpath()
        }
    }
    var body: some View {
        ZStack {
            Path { p in
                p.move(to: CGPoint(x: 126, y: 28)); p.addLine(to: CGPoint(x: 154, y: 22))
                p.addLine(to: CGPoint(x: 139, y: 10)); p.addLine(to: CGPoint(x: 170, y: 7))
            }.stroke(Color.cyan, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            bodyPath.fill(Color.black.opacity(0.25)).offset(x: 1, y: 8).blur(radius: 5)
            bodyPath.fill(LinearGradient(colors: [Color.white, Color(red: 0.76, green: 0.80, blue: 0.87)], startPoint: .topLeading, endPoint: .bottomTrailing)).offset(y: 5)
            bodyPath.stroke(Color(red: 0.08, green: 0.67, blue: 0.95), lineWidth: 2).offset(y: 5)
            bodyPath.fill(LinearGradient(colors: [.white, Color(red: 0.94, green: 0.95, blue: 0.98)], startPoint: .top, endPoint: .bottomTrailing))
            bodyPath.stroke(Color.gray.opacity(0.35), lineWidth: 1)
            if selectedButton == 0 || selectedButton == 1 {
                bodyPath.stroke(CompactTheme.accent, lineWidth: 2)
            }
            Path { p in
                p.move(to: CGPoint(x: 58, y: 79))
                p.addCurve(to: CGPoint(x: 162, y: 89), control1: CGPoint(x: 92, y: 65), control2: CGPoint(x: 139, y: 68))
                p.move(to: CGPoint(x: 111, y: 76))
                p.addCurve(to: CGPoint(x: 71, y: 171), control1: CGPoint(x: 98, y: 104), control2: CGPoint(x: 75, y: 143))
            }.stroke(Color(red: 0.65, green: 0.69, blue: 0.77), lineWidth: 1)
            Capsule().fill(selectedButton == 2 ? CompactTheme.accent : Color(red: 0.30, green: 0.34, blue: 0.40)).frame(width: 9, height: 25)
                .rotationEffect(.degrees(25)).position(x: 116, y: 58)
            if sidePanel {
                VStack(spacing: 3) {
                    ForEach(0..<4) { row in
                        HStack(spacing: 3) {
                            ForEach(0..<3) { col in
                                Text("\(row * 3 + col + 1)").font(.system(size: 7, weight: .bold))
                                    .foregroundStyle(.white).frame(width: 12, height: 12)
                                    .background(selectedButton == 100 + row * 3 + col ? CompactTheme.accent : Color(red: 0.36, green: 0.40, blue: 0.47), in: RoundedRectangle(cornerRadius: 2))
                            }
                        }
                    }
                }.rotationEffect(.degrees(25)).position(x: 127, y: 126)
            } else {
                Capsule().fill(LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom))
                    .frame(width: 11, height: 28).rotationEffect(.degrees(43)).position(x: 117, y: 150)
            }
        }.frame(width: 188, height: 190).rotationEffect(.degrees(-5))
            .accessibilityLabel(sidePanel ? "Mouse with twelve side buttons" : "Mouse illustration")
    }
}
