//
//  RemoteEditSheetView.swift
//  macgit
//

import SwiftUI

struct RemoteEditSheetView: View {
    @Environment(\.dismiss) private var dismiss

    let repositoryURL: URL
    let mode: RemoteEditMode
    let onSave: (String, String) -> Void

    @State private var name: String = ""
    @State private var url: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !url.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(mode.title)
                        .font(.title2)
                        .fontWeight(.semibold)

                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("Name")
                            .font(.system(size: 13))
                            .frame(width: 80, alignment: .trailing)

                        TextField("origin", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .disabled(mode.isNameEditable == false)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("URL")
                            .font(.system(size: 13))
                            .frame(width: 80, alignment: .trailing)

                        TextField("https://github.com/user/repo.git", text: $url)
                            .textFieldStyle(.roundedBorder)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 92)
                    }
                }
                .padding(.top, 24)
                .padding(.horizontal, 24)
                .frame(maxWidth: 420, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }

            HStack(spacing: 12) {
                Spacer()

                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(GlassProminentButtonStyle(tint: .accentColor, fontSize: 13))
                .disabled(!isValid || isLoading)
            }
            .padding([.horizontal, .bottom], 24)
        }
        .frame(minWidth: 420, idealWidth: 480, maxWidth: 520)
        .frame(minHeight: 220, idealHeight: 240)
        .task {
            if case .edit(let existingName, let existingURL) = mode {
                name = existingName
                url = existingURL
            }
        }
    }

    private func save() {
        guard isValid else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedURL = url.trimmingCharacters(in: .whitespaces)
        onSave(trimmedName, trimmedURL)
        dismiss()
    }
}

enum RemoteEditMode: Equatable {
    case add
    case edit(name: String, url: String)

    var title: String {
        switch self {
        case .add:
            return "Add Remote"
        case .edit:
            return "Edit Remote"
        }
    }

    var isNameEditable: Bool {
        switch self {
        case .add:
            return true
        case .edit:
            return false
        }
    }
}

#Preview {
    RemoteEditSheetView(
        repositoryURL: URL(fileURLWithPath: "/tmp"),
        mode: .add
    ) { _, _ in }
}
