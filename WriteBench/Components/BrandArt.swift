import SwiftUI

struct BrandMark: View {
    var size: CGFloat = 38
    var body: some View {
        ZStack {
            Capsule().fill(LinearGradient(colors: [Color(red: 0.55, green: 0.5, blue: 1), WB.blue], startPoint: .top, endPoint: .bottom)).frame(width: size * 0.22, height: size * 0.76).rotationEffect(.degrees(-23)).offset(x: -size * 0.32)
            Capsule().fill(LinearGradient(colors: [WB.blue, Color(red: 0.64, green: 0.79, blue: 1)], startPoint: .top, endPoint: .bottom)).frame(width: size * 0.22, height: size * 0.76).rotationEffect(.degrees(23)).offset(x: -size * 0.10)
            Capsule().fill(LinearGradient(colors: [WB.blue, Color(red: 0.48, green: 0.63, blue: 1)], startPoint: .top, endPoint: .bottom)).frame(width: size * 0.22, height: size * 0.76).rotationEffect(.degrees(-23)).offset(x: size * 0.11)
            Capsule().fill(LinearGradient(colors: [Color(red: 0.77, green: 0.79, blue: 1), WB.blue.opacity(0.6)], startPoint: .top, endPoint: .bottom)).frame(width: size * 0.22, height: size * 0.76).rotationEffect(.degrees(23)).offset(x: size * 0.33)
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}
struct Landscape: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                Path { p in p.move(to: .init(x: 0, y: h * 0.9)); p.addCurve(to: .init(x: w, y: h * 0.35), control1: .init(x: w * 0.5, y: h * 1.2), control2: .init(x: w * 0.7, y: 0)); p.addLine(to: .init(x: w, y: h)); p.addLine(to: .init(x: 0, y: h)) }.fill(Color(red: 0.83, green: 0.89, blue: 1))
                Path { p in p.move(to: .init(x: 0, y: h)); p.addCurve(to: .init(x: w, y: h * 0.88), control1: .init(x: w * 0.47, y: h * 0.18), control2: .init(x: w * 0.45, y: h * 0.93)); p.addLine(to: .init(x: w, y: h)) }.fill(Color(red: 0.75, green: 0.86, blue: 0.99).opacity(0.75))
                Path { p in p.move(to: .init(x: w * 0.48, y: h)); p.addCurve(to: .init(x: w, y: h * 0.63), control1: .init(x: w * 0.8, y: h * 0.82), control2: .init(x: w * 0.77, y: h * 0.5)); p.addLine(to: .init(x: w, y: h)) }.fill(Color(red: 0.58, green: 0.78, blue: 0.89).opacity(0.75))
            }
        }.accessibilityHidden(true)
    }
}
