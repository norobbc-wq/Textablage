import SwiftUI
import UIKit

/// The system paste control requests text only after the person taps it.
@MainActor
struct ClipboardPasteButton: UIViewRepresentable {
    var onPaste: (String) -> Void
    var onFailure: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPaste: onPaste, onFailure: onFailure)
    }

    func makeUIView(context: Context) -> UIPasteControl {
        var configuration = UIPasteControl.Configuration()
        configuration.displayMode = .iconOnly
        configuration.cornerStyle = .medium
        configuration.baseBackgroundColor = UIColor(red: 0.79, green: 0.94, blue: 0.50, alpha: 1)
        configuration.baseForegroundColor = UIColor(red: 0.06, green: 0.09, blue: 0.06, alpha: 1)

        let control = UIPasteControl(configuration: configuration)
        control.target = context.coordinator
        control.accessibilityLabel = "Zwischenablage speichern"
        return control
    }

    func updateUIView(_ uiView: UIPasteControl, context: Context) {
        context.coordinator.onPaste = onPaste
        context.coordinator.onFailure = onFailure
        uiView.target = context.coordinator
    }

    @MainActor
    final class Coordinator: NSObject, UIPasteConfigurationSupporting {
        var pasteConfiguration: UIPasteConfiguration? = UIPasteConfiguration(forAccepting: NSString.self)
        var onPaste: (String) -> Void
        var onFailure: (String) -> Void
        private var isLoading = false

        init(onPaste: @escaping (String) -> Void, onFailure: @escaping (String) -> Void) {
            self.onPaste = onPaste
            self.onFailure = onFailure
        }

        func canPaste(_ itemProviders: [NSItemProvider]) -> Bool {
            itemProviders.contains { $0.canLoadObject(ofClass: NSString.self) }
        }

        func paste(itemProviders: [NSItemProvider]) {
            guard !isLoading else { return }
            guard let provider = itemProviders.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else {
                onFailure("Kein Text in der Zwischenablage.")
                return
            }
            isLoading = true
            provider.loadObject(ofClass: NSString.self) { [weak self] object, error in
                let text = (object as? NSString).map { $0 as String }
                let message = error?.localizedDescription ?? "Der Text konnte nicht eingefügt werden."
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isLoading = false
                    if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.onPaste(text)
                    } else {
                        self.onFailure(message)
                    }
                }
            }
        }
    }
}
