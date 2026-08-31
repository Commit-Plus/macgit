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

import Foundation
import Observation

@MainActor
@Observable
final class ConflictAIResolutionController {
    private struct PendingFileResolution {
        let loadedFile: ConflictAILoadedFile
        var document: ConflictResolutionDocument
        let questions: [ConflictAIUserQuestion]
    }

    private(set) var isRunning = false
    private(set) var isApplyingAnswers = false
    private(set) var processedFileCount = 0
    private(set) var totalFileCount = 0
    private(set) var currentFilePath: String?
    private(set) var resolvedFilePaths: [String] = []
    private(set) var pendingQuestions: [ConflictAIUserQuestion] = []
    private(set) var failures: [ConflictAIFileFailure] = []
    private(set) var wasCancelled = false
    var isShowingQuestions = false

    @ObservationIgnored private let repositoryURL: URL
    @ObservationIgnored private let providerController: AIProviderController
    @ObservationIgnored private let fileService: any ConflictAIFileServicing
    @ObservationIgnored private var resolutionTask: Task<Void, Never>?
    @ObservationIgnored private var pendingFiles: [String: PendingFileResolution] = [:]
    @ObservationIgnored private var selectedOptionIndices: [String: Int] = [:]
    @ObservationIgnored private var runProviderID: AIProviderID?
    @ObservationIgnored private var runCharacterBudget = 0

    init(
        repositoryURL: URL,
        providerController: AIProviderController,
        fileService: any ConflictAIFileServicing = GitStatusService.shared
    ) {
        self.repositoryURL = repositoryURL
        self.providerController = providerController
        self.fileService = fileService
    }

    var canApplyAnswers: Bool {
        !pendingQuestions.isEmpty
            && pendingQuestions.allSatisfy { selectedOptionIndices[$0.id] != nil }
            && !isApplyingAnswers
    }

    var progressText: String {
        if isApplyingAnswers {
            return "Applying AI decisions…"
        }
        if isRunning {
            return "Resolving \(min(processedFileCount + 1, totalFileCount)) of \(totalFileCount)…"
        }
        if wasCancelled {
            return "AI resolution cancelled"
        }
        let resolvedCount = resolvedFilePaths.count
        let questionCount = pendingQuestions.count
        let failureCount = failures.count
        if resolvedCount == 0, questionCount == 0, failureCount == 0 {
            return ""
        }
        var parts: [String] = []
        if resolvedCount > 0 { parts.append("\(resolvedCount) resolved") }
        if questionCount > 0 { parts.append("\(questionCount) need input") }
        if failureCount > 0 { parts.append("\(failureCount) failed") }
        return parts.joined(separator: " · ")
    }

    @discardableResult
    func start(files: [StatusFile]) -> Task<Void, Never>? {
        guard !isRunning, !isApplyingAnswers, !files.isEmpty else { return nil }
        resolutionTask?.cancel()
        resetForNewRun(fileCount: files.count)
        runProviderID = providerController.selectedProviderID
        runCharacterBudget = providerController.selectedDescriptor.inputCharacterBudget
        isRunning = true
        resolutionTask = Task { [weak self] in
            await self?.resolve(files: files)
        }
        return resolutionTask
    }

    func cancel() {
        resolutionTask?.cancel()
    }

    func selectedOptionIndex(for question: ConflictAIUserQuestion) -> Int? {
        selectedOptionIndices[question.id]
    }

    func selectOption(at index: Int, for question: ConflictAIUserQuestion) {
        guard question.options.indices.contains(index) else { return }
        selectedOptionIndices[question.id] = index
    }

    func applySelectedAnswers() async {
        guard canApplyAnswers else { return }
        isApplyingAnswers = true
        defer { isApplyingAnswers = false }

        let pendingPaths = pendingFiles.keys.sorted()
        for path in pendingPaths {
            guard var pending = pendingFiles[path] else { continue }
            do {
                for question in pending.questions {
                    guard let optionIndex = selectedOptionIndices[question.id],
                          question.options.indices.contains(optionIndex) else {
                        throw ConflictAIResolutionError.incompletePlan(
                            "Choose an answer for every AI question before continuing."
                        )
                    }
                    try ConflictAIResolutionPlanApplier.apply(
                        question.options[optionIndex],
                        to: &pending.document,
                        sectionIndex: question.sectionIndex,
                        filePath: path
                    )
                }
                try await fileService.applyAIConflictResolution(
                    file: pending.loadedFile.file,
                    document: pending.document,
                    expectedFingerprint: pending.loadedFile.snapshot.fingerprint,
                    originalWorkingTreeText: pending.loadedFile.originalWorkingTreeText,
                    in: repositoryURL
                )
                appendResolvedPath(path)
                pendingFiles.removeValue(forKey: path)
            } catch {
                appendFailure(path: path, error: error)
                pendingFiles.removeValue(forKey: path)
            }
        }
        rebuildPendingQuestions()
        isShowingQuestions = !pendingQuestions.isEmpty
    }

    func clearCompletedRun() {
        guard !isRunning, !isApplyingAnswers else { return }
        resolvedFilePaths = []
        failures = []
        wasCancelled = false
    }

    private func resolve(files: [StatusFile]) async {
        defer {
            isRunning = false
            currentFilePath = nil
            resolutionTask = nil
            rebuildPendingQuestions()
            isShowingQuestions = !pendingQuestions.isEmpty
        }

        for file in files {
            do {
                try Task.checkCancellation()
                guard providerController.selectedProviderID == runProviderID else {
                    appendFailure(
                        path: file.path,
                        error: ConflictAIResolutionError.staleFile(
                            "The selected AI provider changed. Run Resolve All with AI again."
                        )
                    )
                    return
                }
                currentFilePath = file.path
                let loaded = try await fileService.loadConflictAIFile(
                    file,
                    in: repositoryURL,
                    characterBudget: runCharacterBudget
                )
                let response = try await providerController.generateConflictResolution(
                    request: ConflictAIResolutionRequest(snapshot: loaded.snapshot)
                )
                try Task.checkCancellation()
                let currentFingerprint = try await fileService.conflictAIFingerprint(
                    for: file,
                    in: repositoryURL
                )
                guard currentFingerprint == loaded.snapshot.fingerprint else {
                    throw ConflictAIResolutionError.staleFile(
                        "\(file.path) changed while AI was resolving it."
                    )
                }

                let application = try ConflictAIResolutionPlanApplier.apply(
                    response,
                    to: loaded.document,
                    filePath: file.path
                )
                if application.questions.isEmpty {
                    try await fileService.applyAIConflictResolution(
                        file: file,
                        document: application.document,
                        expectedFingerprint: loaded.snapshot.fingerprint,
                        originalWorkingTreeText: loaded.originalWorkingTreeText,
                        in: repositoryURL
                    )
                    appendResolvedPath(file.path)
                } else {
                    pendingFiles[file.path] = PendingFileResolution(
                        loadedFile: loaded,
                        document: application.document,
                        questions: application.questions
                    )
                }
            } catch is CancellationError {
                wasCancelled = true
                return
            } catch {
                appendFailure(path: file.path, error: error)
            }
            processedFileCount += 1
        }
    }

    private func resetForNewRun(fileCount: Int) {
        processedFileCount = 0
        totalFileCount = fileCount
        currentFilePath = nil
        resolvedFilePaths = []
        pendingQuestions = []
        failures = []
        wasCancelled = false
        isShowingQuestions = false
        pendingFiles = [:]
        selectedOptionIndices = [:]
        runProviderID = nil
        runCharacterBudget = 0
    }

    private func rebuildPendingQuestions() {
        pendingQuestions = pendingFiles.values
            .flatMap(\.questions)
            .sorted {
                if $0.filePath == $1.filePath {
                    return $0.sectionIndex < $1.sectionIndex
                }
                return $0.filePath < $1.filePath
            }
        selectedOptionIndices = selectedOptionIndices.filter { questionID, _ in
            pendingQuestions.contains { $0.id == questionID }
        }
    }

    private func appendResolvedPath(_ path: String) {
        guard !resolvedFilePaths.contains(path) else { return }
        resolvedFilePaths.append(path)
        resolvedFilePaths.sort()
    }

    private func appendFailure(path: String, error: any Error) {
        failures.removeAll { $0.filePath == path }
        failures.append(ConflictAIFileFailure(filePath: path, message: error.localizedDescription))
        failures.sort { $0.filePath < $1.filePath }
    }
}
