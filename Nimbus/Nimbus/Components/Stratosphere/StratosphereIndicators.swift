import SwiftUI

/// A provider's logo on a white tile, lifted off the backdrop. Wraps
/// `ProviderBadge`, which already picks the right logo or glyph.
struct LogoTile: View {
    enum Size: CGFloat {
        case small = 24, compact = 34, medium = 42, large = 64, hero = 92
    }

    let provider: String
    var size: Size = .medium

    var body: some View {
        ProviderBadge(provider: provider, size: size.rawValue)
            .shadow(color: .black.opacity(0.28), radius: size.rawValue * 0.12, y: size.rawValue * 0.05)
    }
}

/// A symbol on a coloured tile, the same size and shape as a small
/// `LogoTile`, for sidebar rows that aren't clouds.
struct IconTile: View {
    let systemImage: String
    let color: DesignSystem.Stratosphere.CloudColor
    var size: CGFloat = 24

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
            .fill(LinearGradient(colors: [color.start.color, color.end.color], startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: systemImage)
                    .resizable()
                    .scaledToFit()
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(width: size * 0.56, height: size * 0.56)
            }
            .shadow(color: .black.opacity(0.28), radius: size * 0.12, y: size * 0.05)
            .accessibilityHidden(true)
    }
}

/// Every cloud's share of total storage as one bar, a segment per cloud.
/// The remainder is free space.
struct SegmentBar: View {
    struct Segment: Identifiable {
        let id: String
        /// Share of the whole bar, 0...1.
        let fraction: Double
        let color: DesignSystem.Stratosphere.CloudColor
    }

    let segments: [Segment]
    var height: CGFloat = 6

    @Environment(\.stratosphere) private var palette

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 2
            let visible = segments.filter { $0.fraction > 0 }
            let usable = max(proxy.size.width - spacing * CGFloat(visible.count), 0)
            HStack(spacing: spacing) {
                ForEach(visible) { segment in
                    Capsule()
                        .fill(segment.color.start.color)
                        .frame(width: max(usable * segment.fraction, 2))
                }
                Capsule().fill(palette.track.color)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// How full a cloud is, in that cloud's colour.
struct UsageBar: View {
    /// 0...1. Values outside are clamped.
    let fraction: Double
    let color: DesignSystem.Stratosphere.CloudColor
    var height: CGFloat = 8

    @Environment(\.stratosphere) private var palette
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let clamped = min(max(fraction, 0), 1)
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.track.color)
                Capsule()
                    .fill(color.gradient)
                    .frame(width: max(proxy.size.width * clamped, clamped > 0 ? height : 0))
                    .shadow(color: color.start.color.opacity(colorScheme == .dark ? 0.7 : 0), radius: 6)
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Storage used")
        .accessibilityValue(Text(clamped, format: .percent.precision(.fractionLength(0))))
    }
}

/// One cloud's arc of a `StorageRing`. Outside the generic ring type so
/// callers can build a list of them without naming the ring's label.
struct StorageRingSegment: Identifiable {
    let id: String
    /// Share of the whole ring, 0...1.
    let fraction: Double
    let color: DesignSystem.Stratosphere.CloudColor
}

/// Storage across every cloud as one ring, a segment per cloud. The caller
/// supplies what goes in the middle and the spoken summary; the legend
/// beside it is the readable detail.
struct StorageRing<Label: View>: View {
    typealias Segment = StorageRingSegment

    let segments: [Segment]
    var lineWidth: CGFloat = 20
    let accessibilityLabel: Text
    @ViewBuilder let label: () -> Label

    @Environment(\.stratosphere) private var palette
    @Environment(\.colorScheme) private var colorScheme

    /// Space left between neighbouring segments, as a share of the ring.
    private let gap = 0.007

    var body: some View {
        ZStack {
            Circle().stroke(palette.track.color, lineWidth: lineWidth)
            ForEach(arcs, id: \.segment.id) { arc in
                Circle()
                    .trim(from: arc.from, to: arc.to)
                    .stroke(arc.segment.color.start.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: arc.segment.color.start.color.opacity(colorScheme == .dark ? 0.8 : 0), radius: 7)
            }
            label()
        }
        .padding(lineWidth / 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var arcs: [(segment: Segment, from: Double, to: Double)] {
        var start = 0.0
        var result: [(Segment, Double, Double)] = []
        for segment in segments where segment.fraction > 0 {
            let end = min(start + segment.fraction, 1)
            // A sliver thinner than the gap still gets a visible mark.
            let to = max(end - gap, start + 0.003)
            result.append((segment, start, to))
            start = end
        }
        return result.map { (segment: $0.0, from: $0.1, to: $0.2) }
    }
}

/// The four states a cloud, transfer or backup can be in. Always shown with
/// words or a glyph beside it; colour alone never carries the meaning.
enum StratosphereStatus {
    case ok, warning, muted, error

    func color(in palette: DesignSystem.Stratosphere.Palette) -> Color {
        switch self {
        case .ok: palette.ok.color
        case .warning: palette.warning.color
        case .muted: palette.muted.color
        case .error: palette.error.color
        }
    }
}

struct StatusDot: View {
    let status: StratosphereStatus
    @Environment(\.stratosphere) private var palette
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let color = status.color(in: palette)
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .shadow(color: color.opacity(colorScheme == .dark ? 0.9 : 0), radius: 4)
            .accessibilityHidden(true)
    }
}

/// A short fact about a thing: "Ran 6 hours ago", "214 files".
struct Chip: View {
    let text: Text
    var status: StratosphereStatus?
    /// A small symbol before the words, for chips that name a feature.
    var systemImage: String?

    @Environment(\.stratosphere) private var palette

    var body: some View {
        HStack(spacing: 5) {
            if let status { StatusDot(status: status) }
            if let systemImage {
                Image(systemName: systemImage)
                    .font(DesignSystem.Stratosphere.Typography.chip)
                    .foregroundStyle(palette.textSecondary.color)
                    .accessibilityHidden(true)
            }
            text
                .font(DesignSystem.Stratosphere.Typography.chip)
                .foregroundStyle(palette.textPrimary.color)
                .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 9)
        .frame(height: 21)
        .background(Capsule().fill(palette.chipFill.color))
    }
}
