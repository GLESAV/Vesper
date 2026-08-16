import SwiftUI

// A quiet settings sheet in the app's own palette: two toggles, the lifetime
// stats, and a credit line. Nothing to configure means nothing to worry about.
struct SettingsSheet: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var progression = ProgressionStore.shared
    @Environment(\.dismiss) private var dismiss

    private let heading = Color(red: 236/255, green: 234/255, blue: 244/255)
    private let muted = Color(red: 155/255, green: 149/255, blue: 178/255)
    private let accent = Color(red: 195/255, green: 175/255, blue: 220/255)

    var body: some View {
        ZStack {
            Color(red: 16/255, green: 15/255, blue: 24/255).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 26) {
                HStack {
                    Text("Settings")
                        .font(.system(size: 22, weight: .light, design: .serif))
                        .foregroundColor(heading)
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(muted)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Close settings")
                }

                toggleRow(title: "Sound",
                          subtitle: "Soft pops and a chime",
                          isOn: $settings.soundEnabled)
                toggleRow(title: "Haptics",
                          subtitle: "A gentle tap with every pop",
                          isOn: $settings.hapticsEnabled)
                toggleRow(title: "Point whispers",
                          subtitle: "Little +points that drift up from a pop",
                          isOn: $settings.pointWhispersEnabled)

                Divider().overlay(Color.white.opacity(0.08))

                VStack(alignment: .leading, spacing: 8) {
                    statRow(value: progression.popPoints, label: "pop points")
                    statRow(value: progression.lifetimePops, label: "orbs set free")
                    statRow(value: progression.fieldsCleared, label: "fields cleared")
                }

                Spacer()

                Text("Vesper · made by Kate Wu · collects nothing")
                    .font(.system(size: 10))
                    .tracking(1.2)
                    .foregroundColor(muted.opacity(0.6))
                    .frame(maxWidth: .infinity)
            }
            .padding(28)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func toggleRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15))
                    .foregroundColor(heading)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(muted)
            }
        }
        .tint(accent)
    }

    private func statRow(value: Int, label: String) -> some View {
        HStack(spacing: 8) {
            Text(value.formatted())
                .font(.system(size: 15, weight: .light, design: .serif))
                .monospacedDigit()
                .foregroundColor(heading)
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(muted)
        }
        .accessibilityElement(children: .combine)
    }
}
