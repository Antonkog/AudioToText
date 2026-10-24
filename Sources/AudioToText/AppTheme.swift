import SwiftUI

enum AppTheme {
    static let ink = Color(red: 0.08, green: 0.10, blue: 0.14)
    static let mutedInk = Color(red: 0.38, green: 0.42, blue: 0.49)
    static let paper = Color(red: 0.965, green: 0.96, blue: 0.94)
    static let card = Color.white.opacity(0.82)
    static let accent = Color(red: 0.91, green: 0.33, blue: 0.22)
    static let accentSoft = Color(red: 1.0, green: 0.86, blue: 0.79)
    static let teal = Color(red: 0.12, green: 0.50, blue: 0.48)
}

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(AppTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.9), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.06), radius: 22, y: 8)
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }
}
