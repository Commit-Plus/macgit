//
//  ToolbarButton.swift
//  macgit
//

import SwiftUI

struct ToolbarButtonLabel: View {
    let icon: String
    let label: String

    var body: some View {
        VStack(spacing: 1) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
            Text(label)
                .font(.system(size: 9))
        }
        .frame(minWidth: 44)
    }
}

func toolbarButton(icon: String, label: String, isLoading: Bool = false, disabled: Bool = false, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        ZStack {
            ToolbarButtonLabel(icon: icon, label: label)
                .opacity(isLoading ? 0.3 : 1.0)

            if isLoading {
                ProgressView()
                    .scaleEffect(0.6)
            }
        }
    }
    .help(label)
    .disabled(disabled || isLoading)
}
