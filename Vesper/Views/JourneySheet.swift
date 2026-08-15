import SwiftUI

// The collection and stats screen — the journey, outside the field itself.
// Shows pop points, records, the 100-pop collection, and lets the player
// feature a pop or drift among everything unlocked. All of it only ever
// counts up; locked pops show a kind hint, never a wall.
struct JourneySheet: View {
    @ObservedObject var model: GameViewModel
    @ObservedObject private var progression = ProgressionStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var lockedHint: String?

    private let heading = Color(red: 236/255, green: 234/255, blue: 244/255)
    private let muted = Color(red: 155/255, green: 149/255, blue: 178/255)
    private let accent = Color(red: 195/255, green: 175/255, blue: 220/255)
    private let cardBg = Color(red: 24/255, green: 22/255, blue: 34/255)

    private var unlocked: Set<Int> { progression.unlockedNumbers() }

    var body: some View {
        ZStack {
            Color(red: 16/255, green: 15/255, blue: 24/255).ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    pointsBlock
                    recordsBlock
                    nextUnlockBlock
                    collectionBlock
                }
                .padding(24)
            }

            if let hint = lockedHint {
                VStack {
                    Spacer()
                    Text(hint)
                        .font(.system(size: 12, design: .serif))
                        .italic()
                        .foregroundColor(heading)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(cardBg.opacity(0.95))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
                        .padding(.bottom, 24)
                }
                .transition(.opacity)
                .allowsHitTesting(false)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Text("The Journey")
                .font(.system(size: 24, weight: .light, design: .serif))
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
            .accessibilityLabel("Close the journey")
        }
    }

    private var pointsBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(progression.popPoints.formatted())
                .font(.system(size: 44, weight: .light, design: .serif))
                .monospacedDigit()
                .foregroundColor(heading)
            Text("POP POINTS")
                .font(.system(size: 9, weight: .medium))
                .tracking(4)
                .foregroundColor(muted)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(progression.popPoints) pop points")
    }

    private var recordsBlock: some View {
        HStack(spacing: 0) {
            record(progression.lifetimePops, "set free")
            record(progression.fieldsCleared, "fields")
            record(progression.fortunesFound, "fortunes")
            record(progression.bestChain, "best chain")
        }
        .padding(.vertical, 14)
        .background(cardBg.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    private func record(_ value: Int, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value.formatted())
                .font(.system(size: 17, weight: .light, design: .serif))
                .monospacedDigit()
                .foregroundColor(heading)
            Text(label)
                .font(.system(size: 9))
                .tracking(1)
                .foregroundColor(muted)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var nextUnlock: PopDefinition? {
        PopCatalog.all
            .filter { !unlocked.contains($0.number) }
            .min { a, b in
                // surface the nearest points-based unlock first; condition
                // unlocks sort by number
                switch (a.unlock, b.unlock) {
                case (.points(let x), .points(let y)): return x < y
                case (.points, _): return true
                case (_, .points): return false
                default: return a.number < b.number
                }
            }
    }

    @ViewBuilder
    private var nextUnlockBlock: some View {
        if let next = nextUnlock {
            VStack(alignment: .leading, spacing: 8) {
                Text("somewhere ahead")
                    .font(.system(size: 9, weight: .medium))
                    .tracking(3)
                    .foregroundColor(muted)
                HStack {
                    Text(next.name)
                        .font(.system(size: 14, design: .serif))
                        .italic()
                        .foregroundColor(heading)
                    Spacer()
                    Text(next.unlock.hint)
                        .font(.system(size: 11))
                        .foregroundColor(muted)
                }
                if case .points(let goal) = next.unlock, goal > 0 {
                    ProgressView(value: min(1, Double(progression.popPoints) / Double(goal)))
                        .tint(accent)
                }
            }
            .padding(16)
            .background(cardBg.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 1))
        }
    }

    private var collectionBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("collection")
                    .font(.system(size: 9, weight: .medium))
                    .tracking(3)
                    .foregroundColor(muted)
                Spacer()
                Text("\(unlocked.count) of \(PopCatalog.all.count)")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundColor(muted)
            }

            driftRow

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5),
                      spacing: 14) {
                ForEach(PopCatalog.all) { def in
                    popCell(def)
                }
            }
        }
    }

    private var driftRow: some View {
        Button {
            progression.featuredPop = nil
            model.leavePath()
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "wind")
                    .font(.system(size: 13))
                    .foregroundColor(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Drift")
                        .font(.system(size: 13))
                        .foregroundColor(heading)
                    Text("every field mixes all the pops you've found")
                        .font(.system(size: 10))
                        .foregroundColor(muted)
                }
                Spacer()
                if progression.featuredPop == nil {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(accent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(cardBg.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(progression.featuredPop == nil ? accent.opacity(0.5) : Color.white.opacity(0.08),
                        lineWidth: 1))
        }
        .accessibilityLabel("Drift: every field mixes all the pops you've found")
    }

    private func popCell(_ def: PopDefinition) -> some View {
        let isUnlocked = unlocked.contains(def.number)
        let isFeatured = progression.featuredPop == def.number
        let paint = def.style.paints[0]
        let fill = Color(red: paint.fill.r, green: paint.fill.g, blue: paint.fill.b)

        return Button {
            if isUnlocked {
                progression.featuredPop = def.number
                model.leavePath()
                dismiss()
            } else {
                withAnimation(.easeOut(duration: 0.25)) {
                    lockedHint = "\(def.name) · \(def.unlock.hint)"
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
                    withAnimation(.easeInOut(duration: 0.5)) { lockedHint = nil }
                }
            }
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(isUnlocked ? fill : Color.white.opacity(0.06))
                        .frame(width: 34, height: 34)
                    if !isUnlocked {
                        Image(systemName: "circle.dotted")
                            .font(.system(size: 15, weight: .light))
                            .foregroundColor(muted.opacity(0.5))
                    }
                    if def.rarity == .secret && !isUnlocked {
                        Text("?")
                            .font(.system(size: 12, design: .serif))
                            .foregroundColor(muted.opacity(0.7))
                    }
                }
                .overlay(Circle().stroke(isFeatured ? accent : .clear, lineWidth: 2)
                    .frame(width: 40, height: 40))
                Text(isUnlocked ? def.name : "· · ·")
                    .font(.system(size: 8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundColor(isUnlocked ? heading.opacity(0.85) : muted.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityLabel(isUnlocked
            ? "\(def.name), \(def.rarity.rawValue) pop, popped \(progression.popCounts[def.number] ?? 0) times"
            : "locked pop, \(def.unlock.hint)")
    }
}
