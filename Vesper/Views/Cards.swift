import SwiftUI

// MARK: - Fortune card

struct FortuneCard: View {
    let text: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text("✦")
                .font(.system(size: 15))
                .foregroundColor(Color(red: 214/255, green: 204/255, blue: 230/255).opacity(0.85))
            Text(text)
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
        .onTapGesture { onDismiss() }
        .transition(.opacity.combined(with: .scale(scale: 0.94)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Fortune: \(text)")
        .accessibilityHint("Tap to dismiss")
    }
}

// MARK: - Done card

struct DoneCard: View {
    let count: Int
    let sessionPoints: Int
    let lifetimePops: Int
    let onRestart: () -> Void

    var body: some View {
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

                Text("You cleared all \(count) orbs.\nNothing left to worry about — for now.")
                    .font(.system(size: 13.5))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .foregroundColor(Color(red: 155/255, green: 149/255, blue: 178/255))
                    .padding(.bottom, 10)

                Text("+\(sessionPoints.formatted()) pop points")
                    .font(.system(size: 12, design: .serif))
                    .italic()
                    .monospacedDigit()
                    .foregroundColor(Color(red: 195/255, green: 175/255, blue: 220/255).opacity(0.9))
                    .padding(.bottom, lifetimePops > count ? 6 : 24)

                if lifetimePops > count {
                    Text("\(lifetimePops.formatted()) set free, all time.")
                        .font(.system(size: 11, design: .serif))
                        .italic()
                        .foregroundColor(Color(red: 139/255, green: 134/255, blue: 163/255).opacity(0.8))
                        .padding(.bottom, 24)
                }

                Button(action: onRestart) {
                    Text("GO AGAIN")
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(2)
                        .foregroundColor(Color(red: 18/255, green: 17/255, blue: 26/255))
                        .padding(.horizontal, 30).padding(.vertical, 13)
                        .background(Color(red: 233/255, green: 230/255, blue: 244/255))
                        .clipShape(RoundedRectangle(cornerRadius: 11))
                }
                .accessibilityLabel("Go again")
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
