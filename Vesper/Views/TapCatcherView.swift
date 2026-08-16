import SwiftUI
import UIKit

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
