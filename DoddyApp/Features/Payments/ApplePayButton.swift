import SwiftUI
import UIKit

/// Apple's own "Buy with Apple Pay" button on the Buy card (ADR-530). The control itself comes
/// from ApplePayPresenter.swift; this file wraps it for SwiftUI and must not import PassKit (see
/// the note at the top of ApplePayPresenter.swift).
struct ApplePayButton: View {
    let action: () -> Void

    var body: some View {
        ApplePayControl(action: action)
            .frame(height: 48)
            .accessibilityIdentifier("purchase.applePay")
    }
}

private struct ApplePayControl: UIViewRepresentable {
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeUIView(context: Context) -> UIControl {
        let control = ApplePayButtonFactory.make()
        control.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .touchUpInside)
        return control
    }

    func updateUIView(_ control: UIControl, context: Context) {
        context.coordinator.action = action
    }

    @MainActor
    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func tapped() {
            action()
        }
    }
}
