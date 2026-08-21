import SwiftUI

struct ContentView: View {
    @StateObject private var model = GameViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var pulse = false
    @State private var showSettings = false
    @State private var showJourney = false
    @State private var showPath = false

    private let renderer = SceneRenderer()

    var body: some View {
        ZStack {
            background

            // animation canvas — purely visual, never intercepts touches
            TimelineView(.animation(minimumInterval: nil, paused: model.renderingPaused)) { timeline in
                Canvas { ctx, size in
                    model.frame(date: timeline.date, size: size)
                    renderer.draw(model.sim, into: &ctx, size: size)
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
                // The field is a drawn surface, so there is no accessibility
                // element per orb and there must not be one: an orb lives for
                // seconds and a rotor filling with and emptying of them would
                // make the pop a two-step activation, which is not what
                // popping is. One direct-interaction region instead — the
                // touch itself is the pop — and the label is the only place
                // anything about the field can be SAID, which is where the
                // balloon animal gets named.
                .accessibilityElement()
                .accessibilityLabel(Text(model.fieldAccessibilityLabel))
                .accessibilityHint(Text(Strings.fieldDirectTouchHint))
                .accessibilityAddTraits(.allowsDirectInteraction)

            // HUD text — non-interactive so it can never swallow a tap
            hud
                .allowsHitTesting(false)

            // buttons live in their own layer so they stay tappable
            topBar

            if model.showFortune {
                FortuneCard(text: model.fortuneText, onDismiss: model.dismissFortune)
            }

            if model.showDone {
                DoneCard(count: model.count,
                         sessionPoints: model.sessionPoints,
                         lifetimePops: model.progression.lifetimePops,
                         onRestart: model.restart)
            }
        }
        .onChange(of: model.count) { _, _ in
            withAnimation(.spring(response: 0.28, dampingFraction: 0.5)) { pulse = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.easeOut(duration: 0.15)) { pulse = false }
            }
        }
        .onAppear { model.sim.reduceMotion = reduceMotion }
        .onChange(of: reduceMotion) { _, value in model.sim.reduceMotion = value }
        .sheet(isPresented: $showSettings) {
            SettingsSheet()
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showJourney) {
            JourneySheet(model: model)
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showPath) {
            PathSheet(model: model)
                .preferredColorScheme(.dark)
        }
    }

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

    private var hud: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("\(model.count)")
                    .font(.system(size: 62, weight: .light, design: .serif))
                    .monospacedDigit()
                    .foregroundColor(Color(red: 244/255, green: 242/255, blue: 250/255))
                    .scaleEffect(pulse ? 1.1 : 1)
                    .accessibilityLabel("\(model.count) orbs popped")
                Text("DETONATED")
                    .font(.system(size: 9, weight: .medium))
                    .tracking(4)
                    .foregroundColor(Color(red: 139/255, green: 134/255, blue: 163/255))
                    .accessibilityHidden(true)
                if model.sessionPoints > 0 {
                    Text("\(model.sessionPoints) pop points")
                        .font(.system(size: 9))
                        .tracking(1.5)
                        .monospacedDigit()
                        .foregroundColor(Color(red: 139/255, green: 134/255, blue: 163/255).opacity(0.8))
                        .padding(.top, 2)
                        .transition(.opacity)
                }
                if let note = model.chainNote {
                    Text(note)
                        .font(.system(size: 11, design: .serif))
                        .italic()
                        .foregroundColor(Color(red: 195/255, green: 175/255, blue: 220/255).opacity(0.75))
                        .transition(.opacity)
                        .padding(.top, 4)
                }
                if let note = model.pathNote {
                    Text(note)
                        .font(.system(size: 11, design: .serif))
                        .italic()
                        .foregroundColor(Color(red: 195/255, green: 175/255, blue: 220/255).opacity(0.8))
                        .transition(.opacity)
                        .padding(.top, 6)
                }
                if let note = model.unlockNote {
                    Text("✦ \(note)")
                        .font(.system(size: 11, design: .serif))
                        .italic()
                        .foregroundColor(Color(red: 214/255, green: 204/255, blue: 230/255).opacity(0.9))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color(red: 24/255, green: 22/255, blue: 34/255).opacity(0.85))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        .padding(.top, 10)
                }
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

    private var topBar: some View {
        VStack {
            HStack {
                glassButton(systemName: "gearshape", label: "Settings") {
                    showSettings = true
                }
                glassButton(systemName: "point.3.connected.trianglepath.dotted", label: "The path") {
                    showPath = true
                }
                Spacer()
                glassButton(systemName: "sparkles", label: "The journey") {
                    showJourney = true
                }
                glassButton(systemName: "arrow.clockwise", label: "Start over") {
                    model.restart()
                }
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
    }

    private func glassButton(systemName: String, label: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(Color(red: 236/255, green: 234/255, blue: 244/255))
                .frame(width: 44, height: 44)
                .background(Color(red: 20/255, green: 18/255, blue: 32/255).opacity(0.55))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .accessibilityLabel(label)
    }
}
