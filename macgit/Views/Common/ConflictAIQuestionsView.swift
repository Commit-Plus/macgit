//
//  macgit (Commit+) - a macOS Git client built with Swift and SwiftUI.
//  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//

import SwiftUI

struct ConflictAIQuestionsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var controller: ConflictAIResolutionController
    let onApplied: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(controller.pendingQuestions) { question in
                        questionCard(question)
                    }
                }
                .padding(20)
            }

            Divider()
            footer
        }
        .frame(minWidth: 620, idealWidth: 700, minHeight: 460, idealHeight: 560)
        .interactiveDismissDisabled(controller.isApplyingAnswers)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("AI Needs Your Input")
                    .font(.title2)
                    .bold()
                Text("Answer only the decisions that repository context could not determine.")
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(20)
    }

    private func questionCard(_ question: ConflictAIUserQuestion) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(question.filePath, systemImage: "doc.text")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(question.filePath)

            Text(question.question)
                .font(.body)
                .textSelection(.enabled)

            if !question.reason.isEmpty {
                Text(question.reason)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(question.options.indices, id: \.self) { index in
                    optionButton(question.options[index], index: index, question: question)
                }
            }
        }
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.separator, lineWidth: 1)
        }
    }

    private func optionButton(
        _ option: ConflictAIResolutionOption,
        index: Int,
        question: ConflictAIUserQuestion
    ) -> some View {
        let isSelected = controller.selectedOptionIndex(for: question) == index
        return Button {
            controller.selectOption(at: index, for: question)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .accessibilityHidden(true)
                Text(option.label)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.label)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    private var footer: some View {
        HStack {
            Button("Resolve Manually") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .disabled(controller.isApplyingAnswers)

            Spacer()

            Button {
                Task {
                    await controller.applySelectedAnswers()
                    onApplied()
                    if controller.pendingQuestions.isEmpty {
                        dismiss()
                    }
                }
            } label: {
                if controller.isApplyingAnswers {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Apply Answers")
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!controller.canApplyAnswers)
        }
        .padding(16)
    }
}
