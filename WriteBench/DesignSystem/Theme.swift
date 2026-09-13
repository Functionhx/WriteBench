import SwiftUI

enum WB {
    static let blue = Color(red: 0.19, green: 0.42, blue: 1.0)
    static let ink = Color(red: 0.09, green: 0.14, blue: 0.27)
    static let secondary = Color(red: 0.40, green: 0.46, blue: 0.60)
    static let canvas = Color(red: 0.975, green: 0.985, blue: 1.0)
    static let tint = Color(red: 0.93, green: 0.955, blue: 1.0)
    static let line = Color(red: 0.885, green: 0.915, blue: 0.965)
    static let green = Color(red: 0.17, green: 0.55, blue: 0.42)
    static let amber = Color(red: 0.67, green: 0.43, blue: 0.14)
    enum Space { static let xs: CGFloat = 8; static let sm: CGFloat = 12; static let md: CGFloat = 16; static let lg: CGFloat = 24; static let xl: CGFloat = 32 }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 24
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(padding).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(WB.line.opacity(0.75), lineWidth: 1))
            .shadow(color: Color(red: 0.3, green: 0.45, blue: 0.7).opacity(0.035), radius: 16, y: 7)
    }
}
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white).padding(.horizontal, 22).padding(.vertical, 13)
            .background(LinearGradient(colors: [WB.blue.opacity(hovered ? 0.86 : 0.95), WB.blue], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.15)))
            .shadow(color: WB.blue.opacity(enabled ? 0.18 : 0), radius: 7, y: 3)
            .opacity(enabled ? 1 : 0.4).scaleEffect(configuration.isPressed ? 0.98 : 1)
            .onHover { hovered = $0 }
    }
}
struct QuietButtonStyle: ButtonStyle {
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .medium))
            .foregroundStyle(WB.secondary).padding(.horizontal, 13).padding(.vertical, 9)
            .background(hovered ? WB.tint : WB.canvas, in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(WB.line))
            .opacity(configuration.isPressed ? 0.65 : 1).onHover { hovered = $0 }
    }
}
struct IconButton: View {
    let symbol: String
    let help: String
    var action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 16)).frame(width: 30, height: 30)
                .background(hovered ? WB.tint : .clear, in: RoundedRectangle(cornerRadius: 8)) }
            .buttonStyle(.plain).foregroundStyle(WB.secondary).help(help).accessibilityLabel(help).onHover { hovered = $0 }
    }
}
struct SectionHeading: View {
    var title: String
    var subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 28, weight: .semibold, design: .rounded)).foregroundStyle(WB.ink)
            Text(subtitle).font(.system(size: 14)).foregroundStyle(WB.secondary)
        }.padding(.bottom, 8)
    }
}
struct EmptyState: View {
    var symbol: String
    var title: String
    var detail: String
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol).font(.system(size: 34, weight: .light)).foregroundStyle(WB.blue).padding(22).background(WB.tint, in: RoundedRectangle(cornerRadius: 22))
            Text(title).font(.system(size: 20, weight: .semibold))
            Text(detail).font(.system(size: 14)).foregroundStyle(WB.secondary).multilineTextAlignment(.center).frame(maxWidth: 380)
        }.frame(maxWidth: .infinity, minHeight: 300).padding(32)
    }
}

struct NavigationButtonStyle: ButtonStyle {
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(hovered ? WB.blue.opacity(0.045) : .clear, in: RoundedRectangle(cornerRadius: 13)).opacity(configuration.isPressed ? 0.75 : 1).onHover { hovered = $0 }
    }
}
