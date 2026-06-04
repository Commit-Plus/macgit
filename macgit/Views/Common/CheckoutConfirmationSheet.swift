//
//  CheckoutConfirmationSheet.swift
//  macgit
//

import SwiftUI

struct CheckoutConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let branchName: String
    let onConfirm: (Bool) -> Void

    @State private var stashLocalChanges = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    // Icon
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.blue)
                        .frame(width: 56, height: 56)
                        .overlay(
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 28))
                                .foregroundStyle(.white)
                        )

                    Text("Confirm Branch Switch")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Are you sure you want to switch your working copy to the branch '\(branchName)'")
                        .font(.system(size: 13))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)

                    Toggle("Stash local changes", isOn: $stashLocalChanges)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 13))
                        .frame(maxWidth: 320, alignment: .leading)
                }
                .padding(.top, 24)
                .padding(.horizontal, 24)
            }

            // Buttons
            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("OK") {
                    dismiss()
                    onConfirm(stashLocalChanges)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(GlassProminentButtonStyle(tint: .blue, fontSize: 13))
            }
            .padding([.horizontal, .bottom], 24)
        }
        .frame(minWidth: 400, idealWidth: 420, maxWidth: 420)
        .frame(minHeight: 300, idealHeight: 320)
    }
}

#Preview {
    CheckoutConfirmationSheet(branchName: "feat/test-new-branch") { _ in }
}
