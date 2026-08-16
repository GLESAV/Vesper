import SwiftUI

// The Path — the infinite pop map, drawn as stepping stones across dark
// water. Newest roads at the top, the fading past below. Every visible
// stone is playable; tapping one starts its field. The road behind
// dissolves after a few days (see MapStore.fadeAfter / docs/pop_map.md).
struct PathSheet: View {
    @ObservedObject var model: GameViewModel
    @ObservedObject private var map = MapStore.shared
    @Environment(\.dismiss) private var dismiss

    private let heading = Color(red: 236/255, green: 234/255, blue: 244/255)
    private let muted = Color(red: 155/255, green: 149/255, blue: 178/255)
    private let accent = Color(red: 195/255, green: 175/255, blue: 220/255)
    private let cardBg = Color(red: 24/255, green: 22/255, blue: 34/255)

    private let rowHeight: CGFloat = 128
    private let topPad: CGFloat = 70
    private let bottomPad: CGFloat = 60

    var body: some View {
        ZStack {
            Color(red: 16/255, green: 15/255, blue: 24/255).ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 24)
                    .padding(.top, 24)

                GeometryReader { geo in
                    ScrollView {
                        ZStack(alignment: .topLeading) {
                            Canvas { ctx, _ in
                                drawRoads(in: &ctx, width: geo.size.width)
                            }
                            .frame(height: contentHeight)

                            ForEach(map.stones) { stone in
                                stoneView(stone)
                                    .position(point(for: stone, width: geo.size.width))
                            }
                        }
                        .frame(height: contentHeight)
                    }
                }

                Text(map.stones.count == 1 && !map.stones[0].cleared
                     ? "step on the stone to begin"
                     : "the road behind fades after three days")
                    .font(.system(size: 11, design: .serif))
                    .italic()
                    .foregroundColor(muted.opacity(0.7))
                    .padding(.bottom, 20)
            }
        }
        .onAppear {
            map.ensureGenesis(unlocked: model.progression.unlockedNumbers())
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("The Path")
                    .font(.system(size: 24, weight: .light, design: .serif))
                    .foregroundColor(heading)
                Text("each stone is a field of its own pops")
                    .font(.system(size: 11))
                    .foregroundColor(muted)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(muted)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Close the path")
        }
    }

    // MARK: - Layout

    private var generationSpan: (min: Int, max: Int) {
        let gens = map.stones.map(\.generation)
        return (gens.min() ?? 0, gens.max() ?? 0)
    }

    private var contentHeight: CGFloat {
        let span = generationSpan
        return CGFloat(span.max - span.min + 1) * rowHeight + topPad + bottomPad
    }

    private func point(for stone: MapStone, width: CGFloat) -> CGPoint {
        let span = generationSpan
        let x = 34 + stone.lane * (width - 68)
        let y = topPad + CGFloat(span.max - stone.generation) * rowHeight
        return CGPoint(x: x, y: y)
    }

    private func drawRoads(in ctx: inout GraphicsContext, width: CGFloat) {
        for stone in map.stones {
            guard let parentID = stone.parentID,
                  let parent = map.stones.first(where: { $0.id == parentID }) else { continue }
            let from = point(for: parent, width: width)
            let to = point(for: stone, width: width)
            var path = Path()
            path.move(to: from)
            path.addCurve(to: to,
                          control1: CGPoint(x: from.x, y: from.y - rowHeight * 0.45),
                          control2: CGPoint(x: to.x, y: to.y + rowHeight * 0.45))
            let onward = parent.id == map.activeStoneID
            ctx.stroke(path,
                       with: .color(onward ? accent.opacity(0.35) : Color.white.opacity(0.12)),
                       style: StrokeStyle(lineWidth: 1, dash: [2, 6]))
        }
    }

    // MARK: - Stones

    private func stoneView(_ stone: MapStone) -> some View {
        let isActive = stone.id == map.activeStoneID
        let defs = stone.popNumbers.map { PopCatalog.definition(for: $0) }
        let names = defs.map(\.name).joined(separator: " · ")

        return Button {
            model.playStone(stone)
            dismiss()
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(cardBg.opacity(stone.cleared && !isActive ? 0.5 : 0.9))
                        .frame(width: 48, height: 48)
                        .overlay(Circle().stroke(
                            isActive ? accent : Color.white.opacity(stone.cleared ? 0.12 : 0.28),
                            lineWidth: isActive ? 2 : 1))
                        .shadow(color: isActive ? accent.opacity(0.35) : .clear, radius: 10)
                    HStack(spacing: 4) {
                        ForEach(Array(defs.enumerated()), id: \.offset) { _, def in
                            let paint = def.style.paints[0]
                            Circle()
                                .fill(Color(red: paint.fill.r, green: paint.fill.g, blue: paint.fill.b))
                                .frame(width: 8, height: 8)
                        }
                    }
                    if stone.cleared {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(muted.opacity(0.8))
                            .offset(y: 14)
                    }
                }
                Text(names)
                    .font(.system(size: 8.5))
                    .lineLimit(1)
                    .frame(maxWidth: 96)
                    .foregroundColor(stone.cleared && !isActive ? muted.opacity(0.6) : muted)
            }
            .opacity(stone.cleared && !isActive ? 0.55 : 1)
        }
        .accessibilityLabel(pathLabel(stone: stone, names: names, isActive: isActive))
    }

    private func pathLabel(stone: MapStone, names: String, isActive: Bool) -> String {
        var parts = ["Stone with \(names)"]
        if isActive { parts.append("you are here") }
        if stone.cleared { parts.append("cleared, tap to play again") }
        else { parts.append("tap to play") }
        return parts.joined(separator: ", ")
    }
}
