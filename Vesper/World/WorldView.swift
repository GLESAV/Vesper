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
//      and its position in the tree never depends on `place`. It sits BELOW
//      the body in the stack (the Director's hit-testing ruling, written out
//      at `composition`) — a z-order is not an identity, and that is the
//      whole of what the ruling moved. When the view
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
// WHAT IS COMPOSED HERE. All three places are real now. The FIELD is the
// game, rendered exactly as `ContentView` renders it; the sky is `SkyView`
// (W09, Tomás) and the journal is `JournalView` (W11, Lena). This file
// positions them and knows nothing else about them — each fills one screen,
// each reads what it needs from `WorldModel.game` and the shared stores, and
// neither of them knows the camera exists. The honest placeholders that stood
// in for them are gone; nothing here pretends on their behalf any more.
//
// The wayfinding whispers (W06, Lena's `WhisperLabel`) are wired HERE, as
// siblings of the moving body — see §3 of `composition`. They are the PRIMARY
// way through the world (R-SPIKE ruling 7) and the swipe is the enhancement,
// which is why their position in this stack is structural too.

// MARK: - Root

// Owns the world for the lifetime of the scene, and does nothing else.
//
// The split exists for one reason: `WorldModel` publishes `place`,
// `worldMoving` and `worldAwake` AND NOTHING ELSE (a blocking acceptance
// condition; the third is W05c splitting "keep rendering" out of "the world is
// moving" — see that file's header), so the
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

    // THE FIELD'S LAYOUT CONTRACT (see `FieldLayout`). The safe insets come
    // from UIKit through the input layer, because this world ignores the safe
    // area and SwiftUI's geometry inside it therefore reports zero. The
    // default is the largest inset any supported iPhone has, so the very
    // first frame is never too tight — it can only get roomier when the truth
    // arrives, never suddenly collide.
    @State private var safeTop: CGFloat = 59
    @State private var safeBottom: CGFloat = 34

    // The whisper's target grows with Dynamic Type, so the band it needs is
    // measured rather than assumed. Assuming 44 is how this collision comes
    // back at accessibility sizes, for the people least able to absorb it.
    @ScaledMetric(relativeTo: .footnote)
    private var scaledWhisperBand: CGFloat = WhisperPresentation.minimumHitEdge

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
        // THE ONWARD SEQUENCE (owner: on completion, go to the sky and
        // auto-progress). Navigation lives here and nowhere else, so the game
        // asks by incrementing a counter and this view is what actually
        // moves — `go` is the same commit a whisper tap makes, so the camera,
        // the dimming and the ground's colour all behave exactly as they do
        // when she travels herself. Nothing about this is a special case
        // downstream of here.
        .onChange(of: game.skyRequest) { _, _ in go(.up) }
        .onChange(of: game.fieldRequest) { _, _ in go(.down) }
        // Kept from v1.2: the counter answers a pop.
        .onChange(of: game.count) { _, _ in
            withAnimation(.spring(response: 0.28, dampingFraction: 0.5)) { pulse = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.easeOut(duration: 0.15)) { pulse = false }
            }
        }
    }

    private func layout(_ size: CGSize) -> FieldLayout {
        FieldLayout(size: size, safeTop: safeTop, safeBottom: safeBottom,
                    whisperBand: scaledWhisperBand)
    }

    private func applyReduceMotion(_ value: Bool) {
        model.camera.reduceMotion = value
        game.sim.reduceMotion = value
    }

    // MARK: - Composition

    private func composition(size: CGSize) -> some View {
        ZStack {
            background

            // ── THE HIT-TESTING ORDER (the Director's ruling, W12) ──────
            //
            // THE MOVING BODY SITS ABOVE THE INPUT LAYER AND IS HIT-TESTABLE.
            // The input layer sits underneath it. That ordering is the whole
            // of how this world became operable: with the body below and
            // carrying `.allowsHitTesting(false)`, `SkyView`'s stars and
            // `JournalView`'s rows and toggles received no touches at all —
            // the world rendered in three places and could be worked in one.
            //
            // IT COSTS THE FIELD NOTHING. SwiftUI hit-tests topmost-first and
            // passes a point it has no interactive content at straight through
            // to the sibling beneath. The field's own layer is
            // `.allowsHitTesting(false)` — `Canvas` and HUD together — so at
            // the field EVERY touch still falls through to the arbiter,
            // untouched: pop-on-touch-down and the pan behave exactly as they
            // did before this line moved. At the sky and the journal only the
            // controls claim their ≥44 pt targets; every other point falls
            // through, so the swipe still works from all three places.
            //
            // IT IS NOT A RULING 8 VIOLATION. Ruling 8 constrains the input
            // layer's IDENTITY and STABILITY, not its z-order. It is still one
            // view at a fixed position in the tree — never rebuilt, never
            // given the offset or a transform, never `.id()`'d, never
            // conditional on `place` or on any per-frame value. Swapping two
            // siblings in a `ZStack` changes none of those things.
            //
            // WHAT WAS REJECTED: disabling the input layer off the field
            // (`.allowsHitTesting(model.place == .field)`, or the same idea
            // spelled as a conditional layer). It would delete the swipe
            // everywhere except the field and leave navigation to the whispers
            // alone — the opposite of one continuous world, and it would buy
            // nothing this ordering does not already give.
            //
            // Where a place STOPS answering — she is not in it, or the world
            // is in flight — is one line, in `placed`, and it is written there
            // because it belongs to the place rather than to the stack.

            // ── 1. THE STABLE INPUT SIBLING ─────────────────────────────
            //
            // A SIBLING OF THE MOVING BODY, NOT A CHILD OF IT (ruling 8).
            // Nothing about this line may become conditional on `place`, and
            // no camera value may reach it: SwiftUI would then rebuild the
            // hosted UIView during a swipe and UIKit would cancel the touch
            // in flight — the exact failure v1.2 blames for cancelled taps.
            // Being first in the stack rather than second is the only thing
            // about it that the ruling changed.
            //
            // `isFieldAtRest` is a LIVE CLOSURE, never a pushed Bool:
            // SwiftUI's update pass is not ordered against UIKit touch
            // delivery, so a snapshot is wrong for about a frame at each end
            // of every settle, and being wrong there costs a pop. It is
            // `camera.isAtRest && camera.place == .field`, not `isAtRest`
            // alone — otherwise a touch-down while resting at the sky pops an
            // orb on a field she cannot see.
            WorldInputLayer(isFieldAtRest: { model.simActive },
                            onPointer: { game.pointerMoved(to: $0) },
                            onSafeArea: { top, bottom in
                                if safeTop != top { safeTop = top }
                                if safeBottom != bottom { safeBottom = bottom }
                            },
                            onOutcome: { model.handle($0) })

            // ── 2. THE MOVING WORLD ─────────────────────────────────────
            //
            // THE PAUSE PREDICATE (H3, and a blocking acceptance condition):
            // the field's quiescence OR her absence from it, AND the
            // published `worldAwake` — which is `worldMoving` plus the one
            // other thing the camera steps per frame without translating (the
            // end-of-axis acknowledgement, W05c).
            //
            // RULED, NOT IMPROVISED. The off-field half of this line is a
            // Director ruling on a defect raised from this file, and it is
            // written down because a later reader will see a longer predicate
            // than H3's example and be tempted to shorten it back.
            //
            // THE DEFECT. `renderingPaused` is `sim.isQuiescent`, published —
            // and `GameViewModel.frame(date:size:)` takes an early return
            // whenever `simActive` is false. The instant she leaves the field
            // the sim stops being stepped, so that mirror FREEZES at whatever
            // it last was: `false`, for any field with an orb still on it.
            // The old predicate would then have rendered the world at the
            // full frame rate for as long as she sat reading the journal,
            // with nothing moving on the glass — heat and battery spent in
            // the one place the product promises quiet.
            //
            // WHAT WAS REFUSED, AND WHY:
            //
            //   * NOT `camera.isAtRest` / `camera.place`, alone or added
            //     here. Ruling 7 keeps the camera non-observable, so a
            //     predicate naming it never re-evaluates: once true, the
            //     TimelineView stays paused, `step(dt:)` stops being called
            //     (H2), and the next commit begins a settle that is never
            //     stepped. The world would not freeze from being paused too
            //     eagerly — it would freeze because the one thing that could
            //     un-pause it is invisible to SwiftUI. Naming
            //     `sim.isQuiescent` raw instead of its published mirror has
            //     the identical defect, for the identical reason.
            //   * NOT A VALUE DERIVED FROM THE PUBLISHED ONES — an
            //     `offField`, a `worldPaused`, a published `simActive`. A flag
            //     computed from `place` and the others is stale against them
            //     for about a frame at each end of every settle, which is
            //     exactly the window that costs a pop. `worldAwake` is not
            //     that: it is mirrored from `camera.isIdle` in the same touch
            //     handler as `worldMoving` and carries information neither of
            //     the other two has — W05c splitting one flag into the two
            //     questions it always was, not a fourth value bolted on.
            //   * NOT `place != .field` ON ITS OWN. `place` flips at the
            //     COMMIT instant — the start of the travel, not the end — so
            //     on its own it would pause the world in the middle of the
            //     settle she just asked for. `!worldAwake` is the term that
            //     keeps a settle alive; it is cleared only once the camera
            //     has actually arrived (`worldQuietened`, deferred).
            //   * NOT `!worldMoving`, WHICH IS WHAT THIS LINE SAID UNTIL
            //     W05c. The two flags mean different things now: `worldMoving`
            //     is "the world is travelling" and gates hit-testing;
            //     `worldAwake` is "the camera still has per-frame state to
            //     step" and is this line's term. The case that separates them
            //     is a flick at the end of the axis — the camera stays AT REST
            //     and answers with an envelope of light instead — and with
            //     `worldMoving` here the world would pause over it and freeze
            //     the glow part-lit. `worldMoving` implies `worldAwake`, so
            //     this is strictly weaker than what it replaced and cannot
            //     pause anything the W04 predicate kept alive.
            //
            // Both terms are PUBLISHED, so both can wake it, and every route
            // back into motion — swipe or whisper tap — goes through
            // `WorldModel.handle`, which sets them in the same touch
            // callback. At the field the added term is false, so this is
            // exactly the predicate v1.2 pauses on and nothing about the
            // field's own behaviour changes.
            //
            // The resume is lurch-free by construction: the first frame after
            // an un-pause is always a frame with the camera in flight, so
            // `simActive` is false and `frame(date:size:)` takes its early
            // return — which advances `lastFrameDate` without stepping the
            // sim. The minute she spent in the journal never arrives at the
            // field as one enormous dt.
            //
            // Pausing stops the timeline's ticks, not the places: a journal
            // page still redraws when its own state changes, because that is
            // an ordinary SwiftUI invalidation and does not need a clock.
            TimelineView(.animation(minimumInterval: nil,
                                    paused: (model.place != .field || game.renderingPaused)
                                        && !model.worldAwake)) { timeline in
                movingBody(at: timeline.date, size: size)
            }
            // The places answer for themselves from here — the ruling
            // above, and the one line in `placed` that decides which of them
            // is answering. Nothing on this side of the stack may re-acquire
            // a blanket veto: that is what made the sky and the journal
            // pictures of themselves.

            // ── 3. THE WAYFINDING WHISPERS ──────────────────────────────
            //
            // Stable siblings, stacked ABOVE the input layer so they can be
            // tapped at all, and below the cards so a fortune is never
            // fighting one for a touch. The whole of the reasoning is on
            // `whispers`.
            whispers(size: size)

            // ── 4. WORLD-LEVEL OVERLAYS THAT SURVIVE TRANSIT ────────────
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

        // W05b, THE TWO TRAVEL-ONLY RENDER CUES, read here with everything
        // else and for the same reason: they are per-frame scalars, so they
        // are taken from the camera at the moment they are needed and handed
        // straight to the views that draw with them. Neither is mirrored into
        // `@State`, neither is given to `withAnimation`, and neither is
        // published — they are functions of a camera position that is already
        // animating, and a SwiftUI curve laid over them would be the second
        // curve in a fight over one number.
        //
        // Both are pure functions of camera state and both are the identity
        // at rest — zero displacement, unity luminance — so a paused world
        // draws precisely the picture it drew before any of this existed. See
        // `WorldRender` for the arithmetic and for why 0.30 and 0.05.
        let parallax = WorldRender.moteParallax(offset: offset,
                                                travelPerPlace: camera.config.travelPerPlace,
                                                viewHeight: h)

        // BARRIER CONDITION 14. `isTransitioning` is the single question —
        // never `flow`, never `exceedsTransitFlow` (the R-ARCH carry-forward
        // onto W05): those are derived from translation, and under Reduce
        // Motion there is none, so they would leave the accessible path — two
        // whole places crossfading through each other — as the one transit
        // where the light never takes its turn.
        let luminance = WorldRender.transitLuminance(isTransitioning: camera.isTransitioning,
                                                     crossfade: camera.transition.t)

        // W05c, THE END-OF-AXIS ACKNOWLEDGEMENT, read here with the rest and
        // for the same reason. `nil` on all but a fraction of a second in any
        // evening, and `nil` is a view that is not built at all rather than a
        // transparent one — a full-screen container above the input layer is
        // not something to leave lying around even at zero opacity.
        //
        // It is the one per-frame value here that is NOT a function of the
        // camera's position: it is a time envelope the camera steps, which is
        // why the pause predicate above now reads `worldAwake` rather than
        // `worldMoving`. If this line ever draws nothing on a device where the
        // glow should be visible, that predicate is the first place to look.
        let acknowledgement = camera.edgeAcknowledgement

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

        // The two places are composed by value and nothing else is handed to
        // them: they take the model, they fill the screen they are given, and
        // they are positioned from out here. Neither is told where the camera
        // is, which is what keeps this file the only one that has to be
        // right about the axis.
        //
        // THE DIM IS APPLIED TO THE PLACES AND ONLY TO THE PLACES. All three
        // take it, uniformly, so nothing changes its relationship to anything
        // else while the world moves — only the level does, which is the calm
        // way to spend condition 14 and covers the pop and chain flash it
        // names along with everything around them. The whispers and the cards
        // are siblings out in `composition` and keep their full light on
        // purpose: the signage may never dim (W06), and a fortune revealed on
        // the way to the sky must stay readable while she travels (§7 ruling
        // 9). The background is a sibling too, so the places dim toward the
        // ground rather than the ground dimming with them.
        return ZStack {
            placed(SkyView(model: model), as: .sky,
                   y: y(.sky), alpha: alpha(.sky), luminance: luminance, size: size)
            placed(field(at: date, size: size, moteParallax: parallax), as: .field,
                   y: y(.field), alpha: alpha(.field), luminance: luminance, size: size)
            placed(JournalView(model: model), as: .journal,
                   y: y(.journal), alpha: alpha(.journal), luminance: luminance, size: size)

            // ABOVE THE PLACES, AND NOT ONE OF THEM. It is the edge of the
            // WORLD catching light, not the edge of whichever place happens to
            // be under it, so it takes no `y`, no `alpha` and no `luminance`:
            // it does not travel, it does not crossfade, and it is not dimmed
            // by condition 14 (which is moot anyway — the camera is at rest
            // while this plays, so `isTransitioning` is false and `luminance`
            // is exactly 1).
            //
            // Still inside the moving body rather than out in `composition`
            // because it reads a per-frame camera scalar, and those are read
            // inside the frame closure and nowhere else (ruling 7). It sits
            // below the whispers and the cards, which keep their own light.
            edgeAcknowledgement(acknowledgement, size: size)
        }
        .frame(width: size.width, height: size.height)
    }

    // MARK: - The end of the axis, answered (W05c)

    // She flicked at the ceiling. The gesture passed both of the arbiter's
    // commit gates, the camera resolved it — correctly — to the place she is
    // already standing in, and before this existed the world did nothing at
    // all. It answers now: a soft brightening at the leading edge, the edge she
    // tried to travel toward, rising and settling back.
    //
    // LIGHT, NOT MOVEMENT, and that is a Director's ruling rather than a
    // choice made here. The whole of the reasoning — and the four grounds on
    // which an iOS-style rubber-band was refused — is on
    // `WorldCamera.Config.acknowledgementRise`. What matters at this site is
    // the consequence: THERE IS NO REDUCE MOTION BRANCH BELOW, because there
    // is nothing to branch. The behaviour is identical with the setting on and
    // off, and both produce zero translation, so there is no second path here
    // to keep honest.
    //
    // `.allowsHitTesting(false)` IS LOAD-BEARING, not hygiene. Since the
    // hit-testing ruling the moving body sits ABOVE the input layer, so a
    // full-screen container in this subtree that answered touches would eat
    // every pop and every swipe for as long as it existed. It exists for about
    // 0.6 s after every flick at an end of the axis, which is to say: at
    // exactly the moment she is most likely to try again.
    @ViewBuilder
    private func edgeAcknowledgement(_ answer: (edge: WorldDirection, level: CGFloat)?,
                                     size: CGSize) -> some View {
        if let answer {
            let up = answer.edge == .up
            LinearGradient(
                stops: [
                    // Three stops rather than two: a straight linear ramp over
                    // 152 pt bands visibly on an OLED at these levels, and a
                    // band in a soft glow reads as a defect. The middle stop
                    // pulls the falloff toward the edge so most of the depth
                    // is spent near nothing, which is also what keeps the
                    // average alpha across the band around a third of its peak.
                    .init(color: Palette.edgeLight, location: 0),
                    .init(color: Palette.edgeLight.opacity(0.34), location: 0.45),
                    .init(color: Palette.edgeLight.opacity(0), location: 1)
                ],
                startPoint: up ? .top : .bottom,
                endPoint: up ? .bottom : .top
            )
            .frame(height: WorldRender.edgeAcknowledgementDepth * size.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity,
                   alignment: up ? .top : .bottom)
            // The renderer decides what one unit of the camera's envelope
            // looks like; the camera decides the envelope. One multiply, no
            // second curve — and no `.animation` anywhere near it, for the
            // reason ruling 7 gives: this level IS the animation.
            .opacity(WorldRender.edgeAcknowledgementOpacity(level: answer.level))
            .allowsHitTesting(false)
            // A NICETY, NEVER THE ONLY SIGNAL, so nothing here is announced
            // and nothing here carries meaning VoiceOver cannot reach. The
            // accessible answer to "there is nothing above the sky" is
            // structural and already shipped: the whisper that would name the
            // place she is already in is simply not there, at that end, ever
            // (see `wayfindingWhisper`). A person who never sees this light is
            // told the same thing by the signage, which is the right way round.
            .accessibilityHidden(true)
        }
    }

    // Each place is a full screen of world, translated along the one axis.
    // Its frame is the PINNED size at every camera position — the movement is
    // an `.offset`, which moves a view without resizing it (rule 3).
    private func placed<Content: View>(_ content: Content,
                                       as place: Place,
                                       y: CGFloat,
                                       alpha: Double,
                                       luminance: Double,
                                       size: CGSize) -> some View {
        content
            .frame(width: size.width, height: size.height)
            .offset(y: y)
            // TWO FACTORS, ONE MODIFIER, AND THEY MEAN DIFFERENT THINGS.
            // `alpha` is how much of this place is on screen — the Reduce
            // Motion crossfade, and the whole of the navigation on that path.
            // `luminance` is barrier condition 14's attenuation while the
            // world travels: exactly 1 at rest, so at rest this line is
            // exactly the line it was before W05b. Multiplied rather than
            // stacked as a second `.opacity` so there is one composite per
            // place per frame instead of two.
            .opacity(alpha * luminance)
            // THE PLACE SHE IS IN IS THE ONE THAT ANSWERS. The counterpart to
            // the hit-testing ruling in `composition`: the body is touchable
            // now, so a place must say when it is NOT.
            //
            // The world keeps all three mounted at all times, and under Reduce
            // Motion all three sit at offset zero — the two she is not in are
            // stacked over the field at zero opacity, where a SwiftUI control
            // still takes a touch. An invisible star answering a tap meant for
            // an orb is precisely the pop this ruling exists to protect.
            // (`JournalView` already says this for itself; the sky does not,
            // and this is one line rather than an edit in two other owners'
            // files.)
            //
            // `!worldMoving` is the second term and it is what keeps a grab
            // mid-transit reaching the arbiter: `place` flips at the COMMIT
            // instant, so without it the destination's controls would be live
            // while the world is still flying toward them, and a hand landing
            // on the glass to catch the world could catch a star instead.
            //
            // AND IT IS `worldMoving`, NOT `worldAwake` — the two are
            // different questions since W05c and this is the moving one. The
            // acknowledgement plays with the camera AT REST, at the sky or the
            // journal, which is precisely where the ≥ 44 pt star and row
            // targets live: gating this line on the awake flag instead would
            // take her controls away for a third of a second every time she
            // flicked at the end of the axis, which is exactly when she is
            // most likely to reach for one.
            //
            // BOTH TERMS ARE PUBLISHED and change at most once per commit —
            // no camera value is named (ruling 7), so this is not a per-frame
            // invalidation, and it cannot latch: `worldMoving == true` implies
            // `worldAwake == true`, which forces the timeline UNPAUSED by the
            // predicate above, so the frame closure keeps running and
            // `worldSettled` always clears it.
            //
            // Nothing here reaches the input layer. It is a sibling of this
            // whole subtree and is never given a predicate of any kind.
            .allowsHitTesting(model.place == place && !model.worldMoving)
            // Ruling 12: accessibility is co-authored, never retrofitted.
            // `.contain` keeps the counter reachable inside the field rather
            // than flattening it into one label.
            .accessibilityElement(children: .contain)
            .accessibilityLabel(placeLabel(for: place))
            // A place that is not on screen is not in the rotor either. Only
            // ever true under Reduce Motion, where the crossfade is the whole
            // of the navigation; with translation on, the neighbouring places
            // really are partly visible and belong in the rotor.
            //
            // `alpha` ALONE, not the dimmed product: what is on screen is a
            // fact about the world, and how brightly the world is lit while it
            // travels may not be allowed to change what VoiceOver can reach.
            //
            // R-A11Y BLOCKER B2, THE SECOND TERM. `alpha` alone was not
            // enough, and the way it failed was inverted: with Reduce Motion
            // ON the crossfade drives `alpha` to ~0 for the places she is not
            // in, so this was correct there — but with Reduce Motion OFF,
            // `alpha` is LITERALLY THE CONSTANT 1 for all three places, since
            // they are separated by translation rather than by opacity. So
            // nothing was ever hidden on the DEFAULT path. Standing in the
            // field, a VoiceOver swipe walked off the counter and into every
            // star on the map, a full screen height off-glass.
            // `JournalView` guards itself; the sky did not.
            //
            // `allowsHitTesting` above does not cover this: it gates touches,
            // and accessibility activation is a separate path — which is
            // precisely how a phantom star could be double-tapped into
            // re-seeding her field and landing her somewhere she never chose.
            //
            // `!worldMoving` preserves the stated intent above: mid-transit
            // the neighbouring places really are partly on screen and belong
            // in the rotor. Both new terms are published and change once per
            // commit, so this adds no per-frame invalidation — ruling 7 is
            // untouched.
            .accessibilityHidden(alpha < 0.01
                                 || (model.place != place && !model.worldMoving))
    }

    private func placeLabel(for place: Place) -> String {
        switch place {
        case .sky:     return Strings.skyA11y
        case .field:   return Strings.fieldA11y
        case .journal: return Strings.journalA11y
        }
    }

    // MARK: - The field (the real game)

    // `moteParallax` is the dust layer's drawing-time translation for this
    // frame (W05b), computed out in `movingBody` from the camera's offset and
    // passed down rather than read here: this function is inside a `Canvas`
    // draw closure, and a draw closure is the one place in the app that may
    // not go looking for state.
    private func field(at date: Date, size: CGSize, moteParallax: CGFloat) -> some View {
        ZStack {
            Canvas { ctx, _ in
                // RULE 3, THE LINE IT LIVES ON. The pinned `size` from the
                // outer `GeometryReader` — never the Canvas's own reported
                // size, and never anything derived from the camera.
                // `GameSimulation.layout(size:)` re-seeds every mote when
                // this argument changes, so it must be constant at every
                // camera position or the field is scrambled mid-play.
                game.frame(date: date, size: size)
                renderer.draw(game.sim, into: &ctx, size: size,
                              moteParallax: moteParallax)
            }

            // The counter belongs to the FIELD, not to the app: it travels
            // with the world and leaves the screen when she does, which is
            // most of what makes this a place rather than a screen.
            hud(size: size)
        }
        // THE SIMULATION'S HALF OF THE COLLISION FIX. Orbs bounce off the
        // bands instead of drifting behind the signage — and the signage is a
        // Button in a layer ABOVE the input layer, so an orb under "the sky"
        // does not merely look wrong: its tap is taken by the whisper and the
        // world travels when she meant to pop. Applied on layout, never per
        // frame; `applyFieldBands` writes nothing published.
        .onAppear {
            let bands = layout(size)
            game.applyFieldBands(top: bands.simTopInset, bottom: bands.simBottomInset)
        }
        .onChange(of: layout(size)) { _, bands in
            game.applyFieldBands(top: bands.simTopInset, bottom: bands.simBottomInset)
        }
        // NON-INTERACTIVE, AND SINCE THE REORDER THIS IS THE LINE THE FIELD
        // DEPENDS ON. The moving body is above the input layer now, so this
        // veto — `Canvas` and HUD together — is the reason every touch at the
        // field falls straight through to the arbiter and pops on touch-down.
        // The HUD is deliberately inside it: a counter that swallows a tap is
        // a v1.2 lesson written into `ContentView`'s own comments, and it is
        // now one modifier away from being relearned.
        .allowsHitTesting(false)
        // R-A11Y BLOCKER B1. This veto is what makes the field work for a
        // sighted finger, and it is ALSO what made the game unplayable with
        // VoiceOver on: the orbs are drawn into a `Canvas`, so there is no
        // accessibility element per orb, and the layer that actually takes
        // touches is a bare `UIView` that is not one either. VoiceOver
        // intercepts direct touches and delivers only ACTIVATIONS, to
        // elements. There was nothing here to activate. Not "harder to play" —
        // no game at all.
        //
        // `.allowsDirectInteraction` is the trait for exactly this case: a
        // drawn surface where the touch itself IS the interaction rather than
        // a proxy for one. It hands this region's raw touches back to the app,
        // which hit-tests them normally — and normal hit-testing is the line
        // above, so they fall through to the arbiter and pop on touch-down by
        // the same path a sighted touch takes.
        //
        // ONE REGION, NOT ONE ELEMENT PER ORB, deliberately: an orb is a
        // moving target that lives for seconds, and a rotor filling with and
        // emptying of them would be worse than useless — it would also make
        // the pop a two-step activation, which is not what popping is.
        //
        // The pop already answers without sight — a tone from `PopSoundEngine`
        // and an impact from `HapticsEngine` per pop, success on clear — so
        // once the touch can land, the loop is conveyed.
        .accessibilityElement()
        .accessibilityLabel(Text(Strings.fieldA11y))
        .accessibilityHint(Text(Strings.fieldDirectTouchHint))
        .accessibilityAddTraits(.allowsDirectInteraction)
    }

    private func hud(size: CGSize) -> some View {
        let bands = layout(size)
        return VStack(spacing: 0) {
            // DECLUTTERED (owner: "the UI at the top is cluttered and ugly").
            //
            // What was here: a 62 pt counter, a tracked all-caps `SET FREE`
            // beneath it, a running points line, and then up to three
            // transient notes stacked under those — six things competing at
            // the top of a screen whose whole proposition is quiet.
            //
            // What is here now: the number, and one thing at a time under it.
            //
            //   * The `SET FREE` caption is gone. A number that changes when
            //     she pops something needs no label, and a tracked capital
            //     caption is the loudest typographic gesture in the app.
            //   * The running points line is gone from the FIELD. Points are
            //     not lost — they whisper up from each pop, they are on the
            //     done card, and they are in the journal. They were the third
            //     number in a column of numbers.
            //   * The counter drops 62 → 40 pt. Still the largest thing on
            //     screen and still the answer to a pop, without being the
            //     subject of the screen. The orbs are the subject.
            //   * The three note kinds share ONE slot and never stack, so the
            //     top of the field can only ever hold two things.
            VStack(spacing: 6) {
                Text("\(game.count)")
                    .font(.system(size: 30, weight: .light, design: .serif))
                    .monospacedDigit()
                    .foregroundColor(Palette.bright.opacity(0.9))
                    // Orbs may pass behind the counter now (see
                    // `FieldLayout.orbCeiling`), so it carries its own
                    // separation rather than taking a band of the field for it.
                    .shadow(color: .black.opacity(0.55), radius: 6)
                    .scaleEffect(pulse ? 1.08 : 1)
                    .accessibilityLabel("\(game.count) \(Strings.setFreeA11y)")

                // ONE SLOT. Rarest wins: an unlock is a thing that happened
                // once, a chain is a thing that happens often.
                Group {
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
                    } else if let note = game.pathNote {
                        whisper(note)
                    } else if let note = game.chainNote {
                        whisper(note)
                    }
                }
                .frame(minHeight: 18)
            }
            .padding(.top, bands.hudTop)

            Spacer()

            if !game.started {
                Text(Strings.firstHint)
                    // R-A11Y C4. This is the only instruction in the product,
                    // and it was the field's least legible text: `dim` at 0.85
                    // measures Lc 30 / 4.26:1 on the field's ground, under the
                    // 4.5:1 bar for 13 pt, at a FIXED 12 pt that never scaled
                    // — so someone who sets large text got a 12 pt sentence
                    // telling them how to play, forever.
                    //
                    // `.footnote` scales; `soft` at full opacity measures Lc
                    // 66 / 7.4:1 and is already in the muted pastel set, so
                    // nothing brightens and nothing saturates. The counter's
                    // 62 pt display face is deliberately left alone — it is
                    // R-CRAFT S4 / item 11, an after-playtest change to the
                    // field's most-looked-at element.
                    .font(.system(.footnote, design: .serif))
                    .italic()
                    .foregroundColor(Palette.soft)
                    .padding(.bottom, bands.hintBottomInset)
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

    // MARK: - Wayfinding

    // THE PRIMARY WAY THROUGH THE WORLD (R-SPIKE ruling 7), and therefore a
    // stable sibling of the moving body rather than anything inside it. Two
    // reasons, both structural:
    //
    //   * ABOVE EVERYTHING ELSE THAT TAKES A TOUCH. `WorldInputView` is a
    //     full-screen UIView that answers every touch reaching it, so a
    //     whisper composed below it is a picture of a whisper; and since the
    //     hit-testing ruling the places take touches too. Stacked last of the
    //     three, these win any point they share with either — which is what
    //     the five-second mute target rides on.
    //   * OUTSIDE THE MOVING BODY. A whisper that travelled with a place
    //     would slide off the screen exactly when she needs it, and would be
    //     rebuilt every frame of every swipe — rule 2's cancelled-touch
    //     failure, applied to the one control that may never miss.
    //
    // The cost is stated plainly rather than hidden: these two ≥44 pt regions
    // are the only parts of the screen where a touch does not reach the field
    // or the pan. That is ruling 7's own trade — the whispers are the primary
    // path — and it is why they are small and at the extreme edges.
    //
    // Where they point is asked of the camera's own table
    // (`destination(from:moving:)`), never re-derived here; its header names
    // re-deriving as the bug. The table is pure in its arguments and the
    // argument is the PUBLISHED `place`, so nothing on this path reads
    // mutable camera state and nothing here needs the camera to be
    // observable.
    //
    // At the ends of the axis that table clamps — `.up` from the sky is the
    // sky — and a whisper naming the place she is already standing in would
    // be a lie, so that end simply carries no whisper. She is still never
    // without a way back: from the sky the foot reads `the field`, from the
    // journal the head does.
    //
    // THE HANDOFF IS DONE: `SkyView` and `JournalView` each carried a `the
    // field` whisper of their own, from before this pair existed, and their
    // owners have deleted both. These two are now the only way-home signage
    // in the world, which is why they are composed out here rather than
    // anywhere inside the moving body — and why nothing in either place may
    // grow one back. A whisper inside a place travels off screen exactly when
    // she needs it, and is rebuilt every frame of every swipe.
    private func whispers(size: CGSize) -> some View {
        let bands = layout(size)
        return VStack(spacing: 0) {
            wayfindingWhisper(going: .up, edge: .top, inset: bands.headWhisperTop)
            Spacer(minLength: 0)
            wayfindingWhisper(going: .down, edge: .bottom, inset: bands.footWhisperInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // `place` is published and changes at most once per commit, so this
        // is not the per-frame value ruling 7 bars from `.animation` — the
        // camera is nowhere in it. The signage crosses over while the world
        // travels instead of snapping at the instant she lets go.
        .animation(.easeInOut(duration: 0.35), value: model.place)
    }

    // The inset is applied INSIDE the condition, so the end of the axis that
    // carries no whisper contributes no layout either.
    @ViewBuilder
    private func wayfindingWhisper(going direction: WorldDirection,
                                   edge: Edge.Set,
                                   inset: CGFloat) -> some View {
        let here = model.place
        let there = model.camera.destination(from: here, moving: direction)
        if there != here {
            whisperLabel(to: there, going: direction)
                .padding(edge, inset)
                // Read after the place she is in: the way out is the thing
                // she already knows how to find.
                .accessibilitySortPriority(-1)
                .transition(.opacity)
        }
    }

    private func whisperLabel(to place: Place, going direction: WorldDirection) -> WhisperLabel {
        switch place {
        case .sky:
            return WhisperLabel.sky(hint: Strings.skyWhisperHint,
                                    isPlaying: fieldIsInPlay,
                                    onTap: { go(direction) })
        case .journal:
            return WhisperLabel.journal(hint: Strings.journalWhisperHint,
                                        isPlaying: fieldIsInPlay,
                                        onTap: { go(direction) })
        case .field:
            // The way home, which is only ever shown from somewhere that is
            // not the field — so it is never dimmed: her hands are not busy
            // here, and the one thing she may be looking for is this.
            return WhisperLabel(text: Strings.fieldWhisper,
                                accessibilityLabel: Strings.fieldA11y,
                                hint: Strings.fieldWhisperHint,
                                isPlaying: false,
                                onTap: { go(direction) })
        }
    }

    // Navigation, and the whole of it. The same call the swipe makes, with no
    // flick behind it: velocity 0 means the camera times the settle from the
    // distance alone. `handle` is a touch callback — outside the render pass
    // — and it is what writes `place`, `worldMoving` and `worldAwake`, so this
    // tap also un-pauses the world it is about to move.
    //
    // It can never be an axis-gated commit: `wayfindingWhisper` above builds no
    // whisper at all at an end of the axis, so there is no control here to tap
    // that would ask for somewhere that does not exist. The end-of-axis
    // acknowledgement is therefore a swipe-only answer, which is the right way
    // round — the swipe is the path on which she can ask an impossible
    // question, and the signage is the path that never lets her.
    private func go(_ direction: WorldDirection) {
        model.handle([.commit(direction, velocity: 0)])
    }

    // The only input to the whispers' dim (`WhisperPresentation`): orbs on
    // screen, hands busy.
    //
    // EVERY TERM IS PUBLISHED — `place`, `started`, `renderingPaused` — so
    // the dim is not a snapshot of whenever SwiftUI last happened to run this
    // body. `simActive` is the more precise question and is deliberately not
    // asked: it reads the camera, and nothing about the camera can invalidate
    // a view (ruling 7), so the whisper would sit at the wrong brightness
    // until something unrelated redrew it.
    private var fieldIsInPlay: Bool {
        model.place == .field && game.started && !game.renderingPaused
    }

    // The world ignores the safe area, so the whispers keep their own
    // distance: clear of a Dynamic Island at the head, clear of the home
    // indicator at the foot, on every supported iPhone.
    // The head/foot insets that used to live here are gone: `FieldLayout`
    // owns every vertical band now, because two of them measured from the
    // screen edge in one file while the counter measured from it in another
    // is precisely how the signage and the counter came to overlap.

    // MARK: - Cards

    @ViewBuilder private var cards: some View {
        if game.showFortune {
            FortuneWhisper(text: game.fortuneText, at: game.fortuneAnchor)
        }
        if game.showDone {
            DoneCard(count: game.count,
                     sessionPoints: game.sessionPoints,
                     lifetimePops: game.progression.lifetimePops,
                     onRestart: game.restart,
                     verse: game.closingVerse)
        }
    }

    // MARK: - Background

    // One ground under all three places, so nothing seams as the world moves.
    // THE GROUND TELLS HER WHERE SHE IS (owner: on swipes out of the game,
    // "the background color should change to be indicative the user is on
    // another screen").
    //
    // KEYED ON `place`, NOT ON THE CAMERA, and that is not a shortcut. Ruling
    // 7 bars mirroring a camera value into anything SwiftUI diffs — a ground
    // colour interpolated per frame would invalidate this view at frame rate
    // and undo the whole reason the camera lives outside the view system.
    // `place` is published and changes exactly once per commit, so the colour
    // crossfades on ARRIVAL, over most of a second. That is also the better
    // reading of the request: she needs the ground to have changed when she
    // gets somewhere, not to smear continuously while she is travelling —
    // the parallax and the dimming already carry the travelling.
    //
    // All three grounds stay dark, muted and unsaturated (guardrail 4). The
    // sky goes cooler and deeper, the way a night sky is colder than a room;
    // the journal goes warmer and browner, the way paper under a lamp is.
    // Neither is a hue you would call blue or brown if asked — they are the
    // field's own charcoal, leaned.
    private var background: some View {
        RadialGradient(
            gradient: Gradient(colors: groundStops),
            center: UnitPoint(x: 0.5, y: 0.3), startRadius: 0, endRadius: 700
        )
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.75), value: model.place)
    }

    private var groundStops: [Color] {
        switch model.place {
        case .field:
            return [Color(red: 22/255, green: 21/255, blue: 31/255),
                    Color(red: 16/255, green: 15/255, blue: 24/255),
                    Color(red: 9/255, green: 8/255, blue: 14/255)]
        case .sky:
            return [Color(red: 17/255, green: 21/255, blue: 34/255),
                    Color(red: 11/255, green: 15/255, blue: 26/255),
                    Color(red: 5/255, green: 8/255, blue: 16/255)]
        case .journal:
            return [Color(red: 28/255, green: 24/255, blue: 29/255),
                    Color(red: 20/255, green: 17/255, blue: 22/255),
                    Color(red: 11/255, green: 9/255, blue: 13/255)]
        }
    }
}

// MARK: - Palette

// The muted tones the rest of the app already uses. Scoped to this file, and
// now only the FIELD's: the sky and the journal carry their own. Never
// saturated, never pure white.
private enum Palette {
    static let bright = Color(red: 244/255, green: 242/255, blue: 250/255)
    static let soft   = Color(red: 214/255, green: 204/255, blue: 230/255)
    // The one tone here that is not the field's: the end-of-axis
    // acknowledgement belongs to the world, not to a place. It is `soft`
    // rather than a new colour on purpose — the world already has a muted
    // pastel for "a little light", and the answer to a flick at the ceiling
    // is not the moment to introduce a second one.
    static let edgeLight = soft
    static let accent = Color(red: 195/255, green: 175/255, blue: 220/255)
    static let dim    = Color(red: 139/255, green: 134/255, blue: 163/255)
    static let card   = Color(red: 24/255, green: 22/255, blue: 34/255)
}

// The placeholder sky and journal that stood here through W04 are gone: the
// real `SkyView` (W09) and `JournalView` (W11) are composed in `movingBody`,
// and a placeholder kept beside finished work is how a playtest returns a
// confident answer to the wrong question.
