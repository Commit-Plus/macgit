//
//  CommitSheetView.swift
//  macgit
//

import SwiftUI

struct CommitSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var message: String = ""
    let onCommit: (String) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Commit Changes")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 8) {
                Text("Commit Message")
                    .font(.headline)
                TextField("Enter a commit message…", text: $message, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 400)
                    .lineLimit(3...6)
            }

            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Commit") {
                    onCommit(message)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(message.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(30)
        .frame(minWidth: 480)
    }
}
