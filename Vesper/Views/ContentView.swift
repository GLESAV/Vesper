import SwiftUI

struct ContentView: View {
    @StateObject private var model = GameViewModel()
    @ObservedObject private var settings = SettingsStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var pulse = false
    @State private var showSettings = false

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
                         lifetimePops: settings.lifetimePops,
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
                if let note = model.chainNote {
                    Text(note)
                        .font(.system(size: 11, design: .serif))
                        .italic()
                        .foregroundColor(Color(red: 195/255, green: 175/255, blue: 220/255).opacity(0.75))
                        .transition(.opacity)
                        .padding(.top, 4)
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
                Spacer()
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
