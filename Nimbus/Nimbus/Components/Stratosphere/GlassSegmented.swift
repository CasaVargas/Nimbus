import SwiftUI

/// A segmented choice on glass: a capsule track with the selected option
/// lifted on a lighter capsule. Used for a cloud's tabs and for small mode
/// choices such as Copy / Sync / Move.
struct GlassSegmented<Value: Hashable>: View {
    struct Option: Identifiable {
        let value: Value
        let title: String
        var systemImage: String?

        var id: Value { value }
    }

    let options: [Option]
    @Binding var selection: Value

    @Environment(\.stratosphere) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let isSelected = option.value == selection
                Button {
                    withAnimation(reduceMotion ? nil : DesignSystem.Motion.snappy) { selection = option.value }
                } label: {
                    HStack(spacing: 6) {
                        if let systemImage = option.systemImage {
                            Image(systemName: systemImage)
                        }
                        Text(verbatim: option.title)
                    }
                    .font(DesignSystem.Stratosphere.Typography.segment)
                    .foregroundStyle(isSelected ? palette.textPrimary.color : palette.textSecondary.color)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 14)
                    .frame(height: 26)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(palette.selection.color)
                                .matchedGeometryEffect(id: "selection", in: highlight)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(3)
        .glassSurface(radius: 16)
    }
}

extension View {
    /// The glass container a cloud's tab content sits in. Clips first so an
    /// AppKit table inside keeps the container's rounded corners.
    func glassContentSurface() -> some View {
        let radius = DesignSystem.Stratosphere.Radius.card
        return clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .glassSurface(radius: radius)
    }
}

#Preview {
    @Previewable @State var tab = "files"
    ZStack {
        StratosphereBackdrop()
        GlassSegmented(
            options: [.init(value: "files", title: "Files"), .init(value: "transfers", title: "Transfers"),
                      .init(value: "finder", title: "Finder"), .init(value: "settings", title: "Settings")],
            selection: $tab
        )
    }
    .frame(width: 520, height: 120)
}
