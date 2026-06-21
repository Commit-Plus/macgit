import Foundation

enum GitCurrentBranchResolver {
    nonisolated static func resolve(showCurrentOutput: String?, abbreviatedHeadOutput: String?) -> String? {
        if let branch = normalizedBranchName(showCurrentOutput) {
            return branch
        }

        guard let branch = normalizedBranchName(abbreviatedHeadOutput), branch != "HEAD" else {
            return nil
        }
        return branch
    }

    nonisolated private static func normalizedBranchName(_ output: String?) -> String? {
        let branch = output?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return branch.isEmpty ? nil : branch
    }
}
