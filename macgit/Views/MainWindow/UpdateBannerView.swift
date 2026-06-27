import SwiftUI

struct UpdateBannerView: View {
    struct Model: Equatable {
        let title: String
        let isEnabled: Bool
        let showsProgress: Bool

        static func make(for state: AppUpdateState) -> Self? {
            switch state {
            case .idle, .checking:
                return nil
            case .available:
                return .init(title: "Update", isEnabled: true, showsProgress: false)
            case .downloading:
                return .init(title: "Downloading…", isEnabled: false, showsProgress: true)
            }
        }
    }

    let model: Model
    let action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if model.showsProgress {
                ProgressView()
                    .controlSize(.small)
            }

            Button(model.title, action: action)
                .buttonStyle(.borderedProminent)
                .disabled(!model.isEnabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
}
