import SwiftUI

/// Edits a backup's exclude patterns: one per row, + and −, presets, and a
/// locked row for the versions folder when it lives inside the destination.
struct ExcludeListEditor: View {
    @Binding var patterns: [String]
    let lockedPattern: String?

    static let presets: [(title: LocalizedStringKey, patterns: [String])] = [
        ("Mac junk", BackupJob.macJunkExcludes),
        ("Temporary files", ["*.tmp", "~$*"]),
        ("Developer folders", ["node_modules/**", ".build/**", "DerivedData/**"]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            ForEach(patterns.indices, id: \.self) { index in
                HStack(spacing: DesignSystem.Spacing.s) {
                    TextField("Pattern", text: binding(at: index))
                        .textFieldStyle(.roundedBorder)
                        .font(DesignSystem.Typography.body.monospaced())
                    Button {
                        patterns.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove \(patterns[index])")
                }
            }
            if let lockedPattern {
                HStack(spacing: DesignSystem.Spacing.s) {
                    Text(verbatim: lockedPattern)
                        .font(DesignSystem.Typography.body.monospaced())
                        .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                    Spacer()
                    Image(systemName: "lock.fill")
                        .foregroundStyle(DesignSystem.Color.semantic.textTertiary)
                        .help("Versions are kept here, so they are never backed up or removed.")
                }
                .padding(.horizontal, DesignSystem.Spacing.xs)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(lockedPattern), always skipped: versions are kept here")
            }
            HStack(spacing: DesignSystem.Spacing.s) {
                Button {
                    patterns.append("")
                } label: {
                    Label("Add Pattern", systemImage: "plus")
                }
                Menu("Add Preset") {
                    ForEach(Self.presets.indices, id: \.self) { index in
                        Button(Self.presets[index].title) { addPreset(Self.presets[index].patterns) }
                    }
                }
                .fixedSize()
            }
            .controlSize(.small)
            Text("* matches within a name, ** matches across folders, a leading / means the top of the backed-up folder.")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Color.semantic.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func binding(at index: Int) -> Binding<String> {
        Binding(
            get: { patterns.indices.contains(index) ? patterns[index] : "" },
            set: { if patterns.indices.contains(index) { patterns[index] = $0 } }
        )
    }

    private func addPreset(_ preset: [String]) {
        for pattern in preset where !patterns.contains(pattern) {
            patterns.append(pattern)
        }
    }
}
