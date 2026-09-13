import SwiftUI

enum ReviewSection: String, CaseIterable, Identifiable {
    case overview, feedback, examiners, corrections, improved, rewrite
    var id: String { rawValue }
    func title(isTranslation: Bool) -> String {
        switch self {
        case .overview: "总分与结论"
        case .feedback: "优点与不足"
        case .examiners: "评审意见"
        case .corrections: "逐句修改"
        case .improved: isTranslation ? "参考改译" : "改进作文"
        case .rewrite: "重写"
        }
    }
}

struct ReviewOutline: View {
    let selection: ReviewSection
    let isTranslation: Bool
    var onSelect: (ReviewSection) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("本篇目录").font(.system(size: 11, weight: .medium)).foregroundStyle(WB.secondary)
                .padding(.horizontal, 12).padding(.bottom, 13)
            ForEach(ReviewSection.allCases) { section in
                Button { onSelect(section) } label: {
                    Text(section.title(isTranslation: isTranslation))
                        .font(.system(size: 12, weight: selection == section ? .medium : .regular))
                        .foregroundStyle(selection == section ? WB.blue : WB.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(selection == section ? WB.tint : .clear, in: RoundedRectangle(cornerRadius: 9))
                        .contentShape(RoundedRectangle(cornerRadius: 9))
                }.buttonStyle(NavigationButtonStyle())
                    .accessibilityIdentifier("reviewJump_\(section.rawValue)")
                    .accessibilityAddTraits(selection == section ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }.padding(.horizontal, 12).padding(.top, 30).frame(width: 144)
            .background(.white.opacity(0.6))
            .overlay(alignment: .trailing) { WB.line.opacity(0.55).frame(width: 1) }
    }
}

struct ReviewSectionPositions: PreferenceKey {
    static let defaultValue: [ReviewSection: CGFloat] = [:]
    static func reduce(value: inout [ReviewSection: CGFloat], nextValue: () -> [ReviewSection: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
extension View {
    func reviewAnchor(_ section: ReviewSection) -> some View {
        id(section).background {
            GeometryReader { geometry in
                Color.clear.preference(key: ReviewSectionPositions.self,
                    value: [section: geometry.frame(in: .named("reviewReadingArea")).minY])
            }
        }
    }
}
