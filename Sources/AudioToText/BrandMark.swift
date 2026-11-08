import SwiftUI

struct BrandMark: View {
    var size: CGFloat = 52

    private let heights: [CGFloat] = [0.28, 0.5, 0.8, 0.58, 0.94, 0.64, 0.38]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                .fill(AppTheme.ink)

            HStack(alignment: .center, spacing: size * 0.045) {
                ForEach(Array(heights.enumerated()), id: \.offset) { _, height in
                    Capsule()
                        .fill(.white)
                        .frame(width: size * 0.055, height: size * height * 0.48)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
