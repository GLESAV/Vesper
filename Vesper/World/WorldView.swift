import SwiftUI

// ONE CONTINUOUS PLACE: the sky above, the field centred, the journal below,
// all on the camera's single vertical axis. This is the first moment Vesper
// stops being a screen with buttons on it, and almost every rule below is
// structural rather than visual — where a view SITS in this tree decides
// whether a pop survives a swipe.
//
// ─────────────────────────────────────────────────────────────────────────
// THE THREE STRUCTURAL RULES (§6 ruling 8 + the R-ARCH blocking acceptance).
// Stated once here, and again at each site, because a later refactor that
// "tidies" any one of them reintroduces a bug that reads as flaky hardware.
//
//   1. THE MOVING BODY LIVES INSIDE THE `TimelineView`, and is the only
//      thing the camera offset ever touches. That closure is also the app's
//      single owner of `camera.step(dt:)` (host contract H1).
//
//   2. `WorldInputLayer` IS A STABLE ZSTACK SIBLING of that body — never
//      inside it, never `.id()`'d, never given the offset or a transform,
//      and its position in the tree never depends on `place`. When the view
//      hosting a touch is torn down and remade, UIKit cancels the touch;
//      the camera moves every frame, so anything downstream of it is remade
//      every frame of every swipe, and the pop dies mid-gesture.
//
//   3. THE FIELD `Canvas` IS PINNED to the size taken once from the outer
//      `GeometryReader`, at every camera position.
//      `GameSimulation.layout(size:)` re-seeds every mote on a size change,
//      so a canvas that resized as the world scrolled would scramble the
//      field under her hands mid-play.
// ─────────────────────────────────────────────────────────────────────────
//
// W04 SCOPE. The FIELD here is the real game, rendered exactly as
// `ContentView` renders it. The sky and the journal are honest placeholders:
// W09 (`SkyView`, Tomás) and W11 (`JournalView`, Lena) replace them
// wholesale. They exist so the world has three real places to travel between
// while those items are in flight — and so nothing here pretends the sky is
// finished. The wayfinding whispers are W06 (Lena) and land as siblings of
// the moving body, beside the input layer.

// MARK: - Root

// Owns the world for the lifetime of the scene, and does nothing else.
//
// The split exists for one reason: `WorldModel` publishes `place` and
// `worldMoving` AND NOTHING ELSE (a blocking acceptance condition), so the
// `GameViewModel` it owns is not observable through it. Rather than widen
// that published surface — or forward another object's changes through it,
// which comes to the same thing while being harder to review — the game is
// handed to the scene as its own `@ObservedObject`. Both objects are stable
// for the life of the scene, so the input layer's position in the tree never
// moves (rule 2).
//
// No explicit `@MainActor` on either view struct, deliberately: SwiftUI's
// `View` conformance already infers it, and that inferred form is the one
// `ContentView` has been compiling under since v1.2. Re-stating it by hand
// changes how the delayed `withAnimation` below is diagnosed, for a
// guarantee the conformance already gives.
struct WorldView: View {

    @StateObject private var model = WorldModel()

    var body: some View {
        WorldScene(model: model, game: model.game)
    }
}

// MARK: - Scene

private struct WorldScene: View {

    @ObservedObject private var model: WorldModel
    @ObservedObject private var game: GameViewModel

    init(model: WorldModel, game: GameViewModel) {
        self.model = model
        self.game = game
    }

    // BARRIER CONDITION 11 / host contract H4: observed live, both ways.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // The counter's pulse, kept from v1.2. `@State` is safe here — it is
    // driven by `.onChange`, outside the render pass, and never by a camera
    // value (ruling 7 bars mirroring those into anything SwiftUI diffs).
    @State private var pulse = false

    private let renderer = SceneRenderer()

    var body: some View {
        GeometryReader { geo in
            composition(size: geo.size)
                // H4. The axis is normalized to screen heights, and until the
                // camera knows one it refuses every outcome (invariant D), so
                // this must land before her first touch does. Rotation and
                // Split View arrive through `onChange`; neither moves the
                // camera through the world, it only changes what a screen
                // height is worth.
                .onAppear { model.camera.viewHeight = geo.size.height }
                .onChange(of: geo.size.height) { _, h in model.camera.viewHeight = h }
        }
        .ignoresSafeArea()
        // BARRIER CONDITION 11 / H4. LIVE, NEVER READ ONCE AT LAUNCH — a
        // person who turns Reduce Motion on mid-evening gets a still world on
        // the next frame, not on the next launch. Under RM `camera.offset` is
        // identically zero and the places crossfade instead of translating.
        .onAppear { applyReduceMotion(reduceMotion) }
        .onChange(of: reduceMotion) { _, value in applyReduceMotion(value) }
        // Kept from v1.2: the counter answers a pop.
        .onChange(of: game.count) { _, _ in
            withAnimation(.spring(response: 0.28, dampingFraction: 0.5)) { pulse = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.easeOut(duration: 0.15)) { pulse = false }
            }
        }
    }

    private func applyReduceMotion(_ value: Bool) {
        model.camera.reduceMotion = value
        game.sim.reduceMotion = value
    }

    // MARK: - Composition

    private func composition(size: CGSize) -> some View {
        ZStack {
            background

            // ── 1. THE MOVING WORLD ─────────────────────────────────────
            //
            // THE PAUSE PREDICATE (H3, and a blocking acceptance condition):
            // the sim's quiescence AND the published `worldMoving`.
            //
            // IT MAY NEVER READ THE CAMERA. The camera is deliberately not
            // observable, so once a predicate naming it evaluated true the
            // body would never be re-evaluated: the TimelineView would stay
            // paused, `step(dt:)` would stop being called, and the next
            // commit would begin a settle that is never stepped. The world
            // would not freeze from being paused too eagerly — it would
            // freeze because the one thing that could un-pause it is
            // invisible to SwiftUI.
            //
            // `renderingPaused` IS `sim.isQuiescent`, published:
            // `GameSimulation` is not observable either, so naming the raw
            // flag here would have the identical defect. This is the same
            // mirror v1.2 pauses on.
            TimelineView(.animation(minimumInterval: nil,
                                    paused: game.renderingPaused && !model.worldMoving)) { timeline in
                movingBody(at: timeline.date, size: size)
            }
            // The world is scenery. Every touch belongs to the layer below.
            .allowsHitTesting(false)

            // ── 2. THE STABLE INPUT SIBLING ─────────────────────────────
            //
            // A SIBLING OF THE MOVING BODY, NOT A CHILD OF IT (ruling 8).
            // Nothing about this line may become conditional on `place`, and
            // no camera value may reach it: SwiftUI would then rebuild the
            // hosted UIView during a swipe and UIKit would cancel the touch
            // in flight — the exact failure v1.2 blames for cancelled taps.
            //
            // `isFieldAtRest` is a LIVE CLOSURE, never a pushed Bool:
            // SwiftUI's update pass is not ordered against UIKit touch
            // delivery, so a snapshot is wrong for about a frame at each end
            // of every settle, and being wrong there costs a pop. It is
            // `camera.isAtRest && camera.place == .field`, not `isAtRest`
            // alone — otherwise a touch-down while resting at the sky pops an
            // orb on a field she cannot see.
            WorldInputLayer(isFieldAtRest: { model.simActive },
                            onOutcome: { model.handle($0) })

            // ── 3. WORLD-LEVEL OVERLAYS THAT SURVIVE TRANSIT ────────────
            //
            // §7 ruling 9. Cards are siblings of the moving body, so a
            // fortune revealed on the way to the sky is still readable when
            // she gets there.
            //
            // They sit ABOVE the input layer, and that ordering is what makes
            // them consume their own touches: hit testing resolves
            // topmost-first, so a tap that lands on a card does not also pop
            // the field beneath it. Only the card's own bounds are covered —
            // the rest of the field stays poppable while a fortune is up,
            // exactly as in v1.2.
            cards
        }
        .frame(width: size.width, height: size.height)
    }

    // MARK: - The moving world

    // ONE CAMERA STEP PER FRAME, HERE AND NOWHERE ELSE IN THE APP (H1/H2).
    //
    // Deliberately NOT inside the field `Canvas`'s draw closure: a place at
    // zero opacity under Reduce Motion may never be drawn, and a camera that
    // stops being stepped does not drift — it FREEZES, mid-settle, halfway
    // between two places, holding her there.
    private func movingBody(at date: Date, size: CGSize) -> some View {
        model.advance(at: date)

        let camera = model.camera
        let h = size.height

        // Every per-frame scalar is read HERE, inside the frame closure, at
        // the moment it is needed, and none is mirrored into `@State` or
        // handed to `withAnimation` (ruling 7). This camera IS the animation;
        // layering SwiftUI's interpolation on top of it puts two curves in a
        // fight over one number, which is how overshoot re-enters a settle
        // that is provably monotone.
        let rm = camera.reduceMotion
        let offset = camera.offset

        // BARRIER CONDITION 11. Under Reduce Motion the world produces ZERO
        // translation and the places crossfade through each other instead.
        // `camera.offset` is already identically zero there; the `rm` branch
        // is written out anyway so the two behaviours read as one deliberate
        // decision rather than as a side effect of a value happening to be 0.
        func y(_ place: Place) -> CGFloat {
            rm ? 0 : (camera.restOffset(of: place) - offset) * h
        }
        func alpha(_ place: Place) -> Double {
            rm ? Double(camera.opacity(of: place)) : 1
        }

        return ZStack {
            placed(SkyPlace(), as: .sky, y: y(.sky), alpha: alpha(.sky), size: size)
            placed(field(at: date, size: size), as: .field,
                   y: y(.field), alpha: alpha(.field), size: size)
            placed(JournalPlace(), as: .journal,
                   y: y(.journal), alpha: alpha(.journal), size: size)
        }
        .frame(width: size.width, height: size.height)
    }

    // Each place is a full screen of world, translated along the one axis.
    // Its frame is the PINNED size at every camera position — the movement is
    // an `.offset`, which moves a view without resizing it (rule 3).
    private func placed<Content: View>(_ content: Content,
                                       as place: Place,
                                       y: CGFloat,
                                       alpha: Double,
                                       size: CGSize) -> some View {
        content
            .frame(width: size.width, height: size.height)
            .offset(y: y)
            .opacity(alpha)
            // Ruling 12: accessibility is co-authored, never retrofitted.
            // `.contain` keeps the counter reachable inside the field rather
            // than flattening it into one label.
            .accessibilityElement(children: .contain)
            .accessibilityLabel(placeLabel(for: place))
            // A place that is not on screen is not in the rotor either. Only
            // ever true under Reduce Motion, where the crossfade is the whole
            // of the navigation; with translation on, the neighbouring places
            // really are partly visible and belong in the rotor.
            .accessibilityHidden(alpha < 0.01)
    }

    private func placeLabel(for place: Place) -> String {
        switch place {
        case .sky:     return Strings.skyA11y
        case .field:   return Strings.fieldA11y
        case .journal: return Strings.journalA11y
        }
    }

    // MARK: - The field (the real game)

    private func field(at date: Date, size: CGSize) -> some View {
        ZStack {
            Canvas { ctx, _ in
                // RULE 3, THE LINE IT LIVES ON. The pinned `size` from the
                // outer `GeometryReader` — never the Canvas's own reported
                // size, and never anything derived from the camera.
                // `GameSimulation.layout(size:)` re-seeds every mote when
                // this argument changes, so it must be constant at every
                // camera position or the field is scrambled mid-play.
                game.frame(date: date, size: size)
                renderer.draw(game.sim, into: &ctx, size: size)
            }

            // The counter belongs to the FIELD, not to the app: it travels
            // with the world and leaves the screen when she does, which is
            // most of what makes this a place rather than a screen.
            hud
        }
        // Non-interactive, so it can never swallow a pop. The whole moving
        // body is already hit-test transparent; this states it locally too,
        // because the field is the layer someone would later be tempted to
        // make tappable.
        .allowsHitTesting(false)
    }

    private var hud: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("\(game.count)")
                    .font(.system(size: 62, weight: .light, design: .serif))
                    .monospacedDigit()
                    .foregroundColor(Palette.bright)
                    .scaleEffect(pulse ? 1.1 : 1)
                    .accessibilityLabel("\(game.count) \(Strings.setFreeA11y)")

                // `DETONATED` is gone from the build the owner sees (ruling
                // 14). Every user-facing string on this surface comes from
                // the catalog; nothing here is inlined.
                Text(Strings.setFreeLabel)
                    .font(.system(size: 9, weight: .medium))
                    .tracking(4)
                    .foregroundColor(Palette.dim)
                    .accessibilityHidden(true)

                if game.sessionPoints > 0 {
                    Text("\(game.sessionPoints) pop points")
                        .font(.system(size: 9))
                        .tracking(1.5)
                        .monospacedDigit()
                        .foregroundColor(Palette.dim.opacity(0.8))
                        .padding(.top, 2)
                        .transition(.opacity)
                }
                if let note = game.chainNote {
                    whisper(note)
                }
                if let note = game.pathNote {
                    whisper(note)
                }
                if let note = game.unlockNote {
                    Text("✦ \(note)")
                        .font(.system(size: 11, design: .serif))
                        .italic()
                        .foregroundColor(Palette.soft.opacity(0.9))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Palette.card.opacity(0.85))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        .padding(.top, 10)
                }
            }
            .padding(.top, 8)

            Spacer()

            if !game.started {
                Text(Strings.firstHint)
                    .font(.system(size: 12, design: .serif))
                    .italic()
                    .foregroundColor(Palette.dim.opacity(0.85))
                    .padding(.bottom, 30)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.5), value: game.started)
    }

    private func whisper(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, design: .serif))
            .italic()
            .foregroundColor(Palette.accent.opacity(0.78))
            .transition(.opacity)
            .padding(.top, 5)
    }

    // MARK: - Cards

    @ViewBuilder private var cards: some View {
        if game.showFortune {
            FortuneCard(text: game.fortuneText, onDismiss: game.dismissFortune)
        }
        if game.showDone {
            DoneCard(count: game.count,
                     sessionPoints: game.sessionPoints,
                     lifetimePops: game.progression.lifetimePops,
                     onRestart: game.restart)
        }
    }

    // MARK: - Background

    // One ground under all three places, so nothing seams as the world moves.
    private var background: some View {
        RadialGradient(
            gradient: Gradient(colors: [
                Color(red: 22/255, green: 21/255, blue: 31/255),
                Color(red: 16/255, green: 15/255, blue: 24/255),
                Color(red: 9/255, green: 8/255, blue: 14/255)
            ]),
            center: UnitPoint(x: 0.5, y: 0.3), startRadius: 0, endRadius: 700
        )
        .ignoresSafeArea()
    }
}

// MARK: - Palette

// The muted tones the rest of the app already uses, named once so the world's
// three places cannot drift apart while W09 and W11 are written in parallel.
// Never saturated, never pure white.
private enum Palette {
    static let bright = Color(red: 244/255, green: 242/255, blue: 250/255)
    static let soft   = Color(red: 214/255, green: 204/255, blue: 230/255)
    static let accent = Color(red: 195/255, green: 175/255, blue: 220/255)
    static let dim    = Color(red: 139/255, green: 134/255, blue: 163/255)
    static let card   = Color(red: 24/255, green: 22/255, blue: 34/255)
}

// MARK: - Placeholder places

// HONEST PLACEHOLDERS, and they say so on the glass. W09 replaces the sky
// with the Path as a constellation over the existing `MapStore`; W11 replaces
// the journal with its pages. Neither is faked here — a placeholder dressed
// up as finished work is how a playtest returns a confident answer to the
// wrong question.
//
// The titles come from the catalog; only the one temporary line underneath is
// local, and it leaves when the placeholder does.
private struct SkyPlace: View {
    var body: some View {
        PlaceCard(title: Strings.skyWhisper,
                  subtitle: "the path of stones will be here.")
    }
}

private struct JournalPlace: View {
    var body: some View {
        PlaceCard(title: Strings.journalWhisper,
                  subtitle: "your evening, your collection, and \(Strings.quietThings).")
    }
}

private struct PlaceCard: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 12) {
            Text("✦")
                .font(.system(size: 15))
                .foregroundColor(Palette.soft.opacity(0.7))
            Text(title)
                .font(.system(size: 26, weight: .light, design: .serif))
                .foregroundColor(Palette.bright.opacity(0.9))
            Text(subtitle)
                .font(.system(size: 12, design: .serif))
                .italic()
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .foregroundColor(Palette.dim)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
