import SwiftUI
import UIKit

// MARK: - Tap catcher

// A UIKit-backed tap recognizer. SwiftUI's own `.gesture(DragGesture(...))`
// can be unreliable when layered over a continuously-redrawing
// TimelineView/Canvas — taps sometimes never reach the gesture at all.
// UITapGestureRecognizer doesn't share that failure mode.
struct TapCatcherView: UIViewRepresentable {
    var onTap: (CGPoint) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let recognizer = UITapGestureRecognizer(target: context.coordinator,
                                                 action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(recognizer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onTap = onTap
    }

    func makeCoordinator() -> Coordinator { Coordinator(onTap: onTap) }

    final class Coordinator: NSObject {
        var onTap: (CGPoint) -> Void
        init(onTap: @escaping (CGPoint) -> Void) { self.onTap = onTap }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            onTap(recognizer.location(in: recognizer.view))
        }
    }
}

// MARK: - Palette

struct Paint {
    let fill: Color
    let glow: Color
}

let palette: [Paint] = [
    Paint(fill: Color(red: 233/255, green: 230/255, blue: 242/255),
          glow: Color(red: 223/255, green: 220/255, blue: 238/255)), // off-white
    Paint(fill: Color(red: 231/255, green: 213/255, blue: 192/255),
          glow: Color(red: 220/255, green: 190/255, blue: 160/255)), // sand
    Paint(fill: Color(red: 217/255, green: 201/255, blue: 230/255),
          glow: Color(red: 195/255, green: 175/255, blue: 220/255)), // lilac
    Paint(fill: Color(red: 198/255, green: 220/255, blue: 216/255),
          glow: Color(red: 175/255, green: 205/255, blue: 198/255)), // sage
    Paint(fill: Color(red: 230/255, green: 205/255, blue: 212/255),
          glow: Color(red: 220/255, green: 180/255, blue: 190/255)), // dusty rose
]

// MARK: - Entities

struct Orb {
    var pos: CGPoint
    var vel: CGVector
    var r: CGFloat
    var baseR: CGFloat
    var paint: Paint
    var phase: CGFloat
    var alive: Bool = true
    var spawn: CGFloat = 0
    var isFortune: Bool = false
}

struct Particle {
    var pos: CGPoint
    var vel: CGVector
    var life: CGFloat
    var decay: CGFloat
    var size: CGFloat
    var glow: Color
}

struct Ring {
    var pos: CGPoint
    var r: CGFloat
    var maxR: CGFloat
    var life: CGFloat
    var glow: Color
    var popped: Bool
}

// MARK: - Model

final class GameModel: ObservableObject {
    @Published var count: Int = 0
    @Published var showDone: Bool = false
    @Published var showFortune: Bool = false
    @Published var fortuneText: String = ""

    var completed = false
    var started = false

    private var orbs: [Orb] = []
    private var particles: [Particle] = []
    private var rings: [Ring] = []

    private var size: CGSize = .zero
    private var lastTime: TimeInterval? = nil
    private var fortuneDismissWork: DispatchWorkItem?

    private let fortuneMessages: [String] = [
        "Whatever you just popped, it wasn't real anyway.",
        "The thing you're avoiding is smaller than you think.",
        "Small relief still counts as relief.",
        "You didn't need that thought. Good riddance.",
        "Not everything deserves your attention. This didn't.",
        "Some things are meant to be let go, quietly.",
        "That was never as heavy as it looked.",
        "One less thing. That's the whole trick.",
        "Nothing is actually keeping score but you.",
        "The quiet after is the point.",
        "You can always make more worries. Try not to.",
        "This one was hiding something nice: you found it.",
        "Popped, gone, forgotten. As it should be.",
        "You're allowed to enjoy something this small.",
        "Somewhere, a tiny weight just lifted.",
        "It only felt important while it was still whole.",
        "Breathe. That part's over now.",
        "Even a bubble knows when it's time to go."
    ]

    private func rnd(_ a: CGFloat, _ b: CGFloat) -> CGFloat { CGFloat.random(in: a...b) }

    private func targetOrbs() -> Int {
        Int.random(in: 7..<20)
    }

    func seed() {
        orbs.removeAll()
        guard size.width > 0 else { return }
        for _ in 0..<targetOrbs() {
            let r = rnd(18, 34)
            var o = Orb(
                pos: CGPoint(x: rnd(r + 24, size.width - r - 24),
                             y: rnd(r + 100, size.height - r - 24)),
                vel: CGVector(dx: rnd(-0.18, 0.18), dy: rnd(-0.18, 0.18)),
                r: r, baseR: r,
                paint: palette.randomElement()!,
                phase: rnd(0, .pi * 2)
            )
            o.spawn = 1
            orbs.append(o)
        }
        if let idx = orbs.indices.randomElement() {
            orbs[idx].isFortune = true
        }
    }

    func restart() {
        particles.removeAll()
        rings.removeAll()
        count = 0
        completed = false
        started = false
        dismissFortune()
        withAnimation(.easeInOut(duration: 0.35)) { showDone = false }
        seed()
    }

    func dismissFortune() {
        fortuneDismissWork?.cancel()
        fortuneDismissWork = nil
        withAnimation(.easeInOut(duration: 0.3)) { showFortune = false }
    }

    private func triggerFortune() {
        fortuneText = fortuneMessages.randomElement() ?? ""
        withAnimation(.easeOut(duration: 0.4)) { showFortune = true }
        fortuneDismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.easeInOut(duration: 0.4)) { self?.showFortune = false }
        }
        fortuneDismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.6, execute: work)
    }

    func tap(at p: CGPoint) {
        guard !completed else { return }
        for i in stride(from: orbs.count - 1, through: 0, by: -1) {
            guard orbs[i].alive else { continue }
            let dx = p.x - orbs[i].pos.x, dy = p.y - orbs[i].pos.y
            // a touch of extra tolerance so small orbs are easy to hit
            let rr = orbs[i].r + 12
            if dx * dx + dy * dy <= rr * rr {
                detonate(index: i, chained: false)
                return
            }
        }
    }

    private func detonate(index: Int, chained: Bool) {
        guard orbs[index].alive else { return }
        orbs[index].alive = false
        started = true
        count += 1

        let orb = orbs[index]
        let strength = orb.baseR / 34

        let pitch = 1 - Double((orb.baseR - 18) / (34 - 18))
        PopSoundEngine.shared.playPop(pitch: pitch)

        if orb.isFortune {
            triggerFortune()
        }

        let n = 18 + Int(orb.baseR)
        for _ in 0..<n {
            let a = rnd(0, .pi * 2)
            let sp = rnd(1.2, 6) * (0.7 + strength)
            particles.append(Particle(
                pos: orb.pos,
                vel: CGVector(dx: cos(a) * sp, dy: sin(a) * sp - rnd(0, 0.8)),
                life: 1, decay: rnd(0.01, 0.024),
                size: rnd(1.2, 3.4), glow: orb.paint.glow))
        }
        rings.append(Ring(pos: orb.pos, r: orb.baseR * 0.5,
                          maxR: 110 + orb.baseR * 2.6,
                          life: 1, glow: orb.paint.glow, popped: chained))

        if started && !completed && orbs.allSatisfy({ !$0.alive }) {
            completed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { [weak self] in
                guard let self, self.completed else { return }
                withAnimation(.easeOut(duration: 0.5)) { self.showDone = true }
            }
        }
    }

    // MARK: Step

    func update(date: Date, size: CGSize) {
        self.size = size
        if orbs.isEmpty && !completed { seed() }

        let t = date.timeIntervalSinceReferenceDate
        var f: CGFloat = 1
        if let last = lastTime {
            f = CGFloat(min(max(t - last, 0), 0.05) * 60)
        } else {
            f = 0
        }
        lastTime = t
        if f == 0 { return }

        // orbs
        for i in orbs.indices where orbs[i].alive {
            if orbs[i].spawn < 1 { orbs[i].spawn = min(1, orbs[i].spawn + 0.05 * f) }
            orbs[i].pos.x += orbs[i].vel.dx * f
            orbs[i].pos.y += orbs[i].vel.dy * f
            orbs[i].phase += 0.02 * f
            let r = orbs[i].r
            if orbs[i].pos.x < r || orbs[i].pos.x > size.width - r { orbs[i].vel.dx *= -1 }
            if orbs[i].pos.y < r + 70 || orbs[i].pos.y > size.height - r { orbs[i].vel.dy *= -1 }
            orbs[i].r = orbs[i].baseR * (1 + sin(orbs[i].phase) * 0.03) * orbs[i].spawn
        }

        // rings + chain reactions
        let rc = rings.count
        for i in 0..<rc {
            rings[i].r += (rings[i].maxR - rings[i].r) * 0.1 * f + 1.5 * f
            rings[i].life -= 0.03 * f
            if !rings[i].popped && rings[i].r > 18 {
                let rr = rings[i].r
                for j in orbs.indices where orbs[j].alive {
                    let d = hypot(orbs[j].pos.x - rings[i].pos.x, orbs[j].pos.y - rings[i].pos.y)
                    if d < rr + orbs[j].r && d > rr - 24 {
                        detonate(index: j, chained: true)
                    }
                }
                if rings[i].r > rings[i].maxR * 0.5 { rings[i].popped = true }
            }
        }
        rings.removeAll { $0.life <= 0 }

        // particles
        for i in particles.indices {
            particles[i].vel.dy += 0.07 * f
            let damp = pow(0.986, f)
            particles[i].vel.dx *= damp
            particles[i].vel.dy *= damp
            particles[i].pos.x += particles[i].vel.dx * f
            particles[i].pos.y += particles[i].vel.dy * f
            particles[i].life -= particles[i].decay * f
        }
        particles.removeAll { $0.life <= 0 }
    }

    // MARK: Draw

    func draw(context: inout GraphicsContext, size: CGSize) {
        var glow = context
        glow.blendMode = .plusLighter

        // orbs: faint halo (additive) + flat solid disc
        for o in orbs where o.alive {
            let R = o.r
            let haloRect = CGRect(x: o.pos.x - R * 2.2, y: o.pos.y - R * 2.2,
                                  width: R * 4.4, height: R * 4.4)
            let grad = Gradient(stops: [
                .init(color: o.paint.glow.opacity(0.18), location: 0),
                .init(color: o.paint.glow.opacity(0), location: 1)
            ])
            glow.fill(Path(ellipseIn: haloRect),
                      with: .radialGradient(grad, center: o.pos,
                                            startRadius: R * 0.6, endRadius: R * 2.2))

            let bodyRect = CGRect(x: o.pos.x - R, y: o.pos.y - R, width: R * 2, height: R * 2)
            context.fill(Path(ellipseIn: bodyRect), with: .color(o.paint.fill))
        }

        // shockwave rings
        for r in rings {
            let rect = CGRect(x: r.pos.x - r.r, y: r.pos.y - r.r, width: r.r * 2, height: r.r * 2)
            glow.stroke(Path(ellipseIn: rect),
                        with: .color(r.glow.opacity(Double(max(0, r.life) * 0.4))),
                        lineWidth: 1 + r.life * 2)
        }

        // particles
        for p in particles {
            let a = max(0, p.life)
            let s = p.size * (0.5 + a * 0.5)
            let rect = CGRect(x: p.pos.x - s, y: p.pos.y - s, width: s * 2, height: s * 2)
            glow.fill(Path(ellipseIn: rect), with: .color(p.glow.opacity(Double(a))))
        }
    }
}

// MARK: - View

struct ContentView: View {
    @StateObject private var model = GameModel()
    @State private var pulse = false

    var body: some View {
        ZStack {
            // background
            RadialGradient(
                gradient: Gradient(colors: [
                    Color(red: 22/255, green: 21/255, blue: 31/255),
                    Color(red: 16/255, green: 15/255, blue: 24/255),
                    Color(red: 9/255, green: 8/255, blue: 14/255)
                ]),
                center: UnitPoint(x: 0.5, y: 0.3), startRadius: 0, endRadius: 700
            )
            .ignoresSafeArea()

            // animation canvas — purely visual, never intercepts touches
            TimelineView(.animation) { timeline in
                Canvas { ctx, size in
                    model.update(date: timeline.date, size: size)
                    model.draw(context: &ctx, size: size)
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // dedicated, STABLE tap layer.
            // Kept separate from the TimelineView so it isn't rebuilt every
            // frame — that rebuild was cancelling some taps mid-recognition.
            // UIKit-backed (not a SwiftUI .gesture) so it isn't subject to
            // SwiftUI's gesture-arena flakiness over a Canvas/TimelineView.
            TapCatcherView { p in model.tap(at: p) }
                .ignoresSafeArea()

            // HUD text — non-interactive so it can never swallow a tap
            hud
                .allowsHitTesting(false)

            // reset button lives in its own layer so it stays tappable
            resetButton

            if model.showFortune { fortuneCard }

            if model.showDone { doneCard }
        }
        .onChange(of: model.count) { _ in
            withAnimation(.spring(response: 0.28, dampingFraction: 0.5)) { pulse = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.easeOut(duration: 0.15)) { pulse = false }
            }
        }
    }

    private var hud: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("\(model.count)")
                    .font(.system(size: 62, weight: .light, design: .serif))
                    .monospacedDigit()
                    .foregroundColor(Color(red: 244/255, green: 242/255, blue: 250/255))
                    .scaleEffect(pulse ? 1.1 : 1)
                Text("DETONATED")
                    .font(.system(size: 9, weight: .medium))
                    .tracking(4)
                    .foregroundColor(Color(red: 139/255, green: 134/255, blue: 163/255))
            }
            .padding(.top, 8)

            Spacer()

            if !model.started {
                Text("TAP AN ORB TO BLOW IT UP")
                    .font(.system(size: 11))
                    .tracking(2.2)
                    .foregroundColor(Color(red: 139/255, green: 134/255, blue: 163/255).opacity(0.75))
                    .padding(.bottom, 30)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.5), value: model.started)
    }

    private var resetButton: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: model.restart) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(Color(red: 236/255, green: 234/255, blue: 244/255))
                        .frame(width: 44, height: 44)
                        .background(Color(red: 20/255, green: 18/255, blue: 32/255).opacity(0.55))
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
    }

    private var fortuneCard: some View {
        VStack(spacing: 10) {
            Text("✦")
                .font(.system(size: 15))
                .foregroundColor(Color(red: 214/255, green: 204/255, blue: 230/255).opacity(0.85))
            Text(model.fortuneText)
                .font(.system(size: 15, design: .serif))
                .italic()
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .foregroundColor(Color(red: 232/255, green: 228/255, blue: 242/255))
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 24)
        .frame(maxWidth: 290)
        .background(Color(red: 24/255, green: 22/255, blue: 34/255).opacity(0.92))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.12), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.4), radius: 30, y: 12)
        .onTapGesture { model.dismissFortune() }
        .transition(.opacity.combined(with: .scale(scale: 0.94)))
    }

    private var doneCard: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            VStack(spacing: 0) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.3), lineWidth: 1)
                        .frame(width: 52, height: 52)
                    Image(systemName: "checkmark")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(Color(red: 236/255, green: 234/255, blue: 244/255))
                }
                .padding(.bottom, 22)

                Text("Nicely done.")
                    .font(.system(size: 30, weight: .light, design: .serif))
                    .foregroundColor(.white)
                    .padding(.bottom, 12)

                Text("You cleared all \(model.count) orbs.\nNothing left to worry about — for now.")
                    .font(.system(size: 13.5))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .foregroundColor(Color(red: 155/255, green: 149/255, blue: 178/255))
                    .padding(.bottom, 26)

                Button(action: model.restart) {
                    Text("GO AGAIN")
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(2)
                        .foregroundColor(Color(red: 18/255, green: 17/255, blue: 26/255))
                        .padding(.horizontal, 30).padding(.vertical, 13)
                        .background(Color(red: 233/255, green: 230/255, blue: 244/255))
                        .clipShape(RoundedRectangle(cornerRadius: 11))
                }
            }
            .padding(44)
            .frame(maxWidth: 340)
            .background(Color(red: 22/255, green: 20/255, blue: 32/255).opacity(0.9))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.1), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .shadow(color: .black.opacity(0.5), radius: 40, y: 20)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}
