import Foundation

extension GitStatusService {
    func search(query: String, in repositoryURL: URL) async -> [SearchResult] {
        guard !query.isEmpty else { return [] }
        let lowerQuery = query.lowercased()
        
        var results: [SearchResult] = []
        
        await withTaskGroup(of: [SearchResult].self) { group in
            group.addTask { await self.searchCommits(query: lowerQuery, in: repositoryURL) }
            group.addTask { await self.searchFiles(query: lowerQuery, in: repositoryURL) }
            group.addTask { await self.searchBranches(query: lowerQuery, in: repositoryURL) }
            group.addTask { await self.searchTags(query: lowerQuery, in: repositoryURL) }
            
            for await partial in group {
                results.append(contentsOf: partial)
            }
        }
        
        // Sort by type order, then title
        let typeOrder: [SearchResultType] = [.commit, .file, .branch, .tag]
        return results.sorted { a, b in
            let aIdx = typeOrder.firstIndex(of: a.type) ?? 99
            let bIdx = typeOrder.firstIndex(of: b.type) ?? 99
            if aIdx != bIdx { return aIdx < bIdx }
            return a.title.lowercased() < b.title.lowercased()
        }
    }
    
    // MARK: - Private search helpers
    
    private func searchCommits(query: String, in repositoryURL: URL) async -> [SearchResult] {
        var results: [SearchResult] = []
        
        // Search by commit message
        let format = "%H%x00%s%x00%an%x00%ad"
        let logOutput = (try? await runGit(
            arguments: [
                "log", "--all", "--grep", query,
                "-i", "-n", "20",
                "--format=" + format,
                "--date=short"
            ],
            in: repositoryURL
        )) ?? ""
        results.append(contentsOf: parseSearchCommits(logOutput))
        
        // Search by hash prefix
        let allHashesOutput = (try? await runGit(
            arguments: ["log", "--all", "--format=%H", "-n", "200"],
            in: repositoryURL
        )) ?? ""
        let matchingHashes = allHashesOutput.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.lowercased().hasPrefix(query) }
            .prefix(20)
        
        var hashMatches: [SearchResult] = []
        if !matchingHashes.isEmpty {
            let hashOutput = (try? await runGit(
                arguments: [
                    "log", "--no-walk",
                    "--format=" + format,
                    "--date=short"
                ] + Array(matchingHashes),
                in: repositoryURL
            )) ?? ""
            hashMatches = parseSearchCommits(hashOutput)
        }
        
        // Avoid duplicates
        let existingHashes = Set(results.compactMap { r -> String? in
            if case .showCommit(let h) = r.action { return h } else { return nil }
        })
        results.append(contentsOf: hashMatches.filter { r in
            if case .showCommit(let h) = r.action { return !existingHashes.contains(h) }
            return true
        })
        
        return Array(results.prefix(20))
    }
    
    private func parseSearchCommits(_ raw: String) -> [SearchResult] {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        var results: [SearchResult] = []
        for line in raw.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.split(separator: "\u{0000}", omittingEmptySubsequences: false)
            guard parts.count >= 4 else { continue }
            let hash = String(parts[0])
            let message = String(parts[1])
            let author = String(parts[2])
            let dateStr = String(parts[3])
            let date = dateFormatter.date(from: dateStr) ?? Date()
            let shortHash = String(hash.prefix(7))
            
            let subtitle = "\(shortHash) • \(author) • \(formattedDate(date))"
            results.append(SearchResult(
                type: .commit,
                title: message,
                subtitle: subtitle,
                action: .showCommit(hash),
                badge: nil
            ))
        }
        return results
    }
    
    private func searchFiles(query: String, in repositoryURL: URL) async -> [SearchResult] {
        let output = (try? await runGit(
            arguments: ["ls-files"],
            in: repositoryURL
        )) ?? ""
        
        let statusOutput = (try? await runGit(
            arguments: ["status", "--short"],
            in: repositoryURL
        )) ?? ""
        
        var statusMap: [String: String] = [:]
        for line in statusOutput.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.count >= 3 else { continue }
            let statusCode = String(trimmed.prefix(2))
            let filePath = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            statusMap[filePath] = statusCode
        }
        
        let matching = output.split(separator: "\n").filter { line in
            let path = String(line).trimmingCharacters(in: .whitespaces)
            return path.lowercased().contains(query)
        }
        
        return matching.prefix(20).map { line in
            let path = String(line).trimmingCharacters(in: .whitespaces)
            let components = path.split(separator: "/")
            let name = String(components.last ?? Substring(path))
            let dir = components.dropLast().joined(separator: "/")
            let status = statusMap[path]
            let badge: String? = status.map { code in
                if code.contains("M") { return "Modified" }
                if code.contains("A") { return "Added" }
                if code.contains("D") { return "Deleted" }
                if code.contains("??") { return "Untracked" }
                return nil
            } ?? nil
            
            return SearchResult(
                type: .file,
                title: name,
                subtitle: dir.isEmpty ? path : dir,
                action: .showFile(path),
                badge: badge
            )
        }
    }
    
    private func searchBranches(query: String, in repositoryURL: URL) async -> [SearchResult] {
        let output = (try? await runGit(
            arguments: ["branch", "-a", "--format=%(refname:short)"],
            in: repositoryURL
        )) ?? ""
        
        let remotesOutput = (try? await runGit(
            arguments: ["remote"],
            in: repositoryURL
        )) ?? ""
        let remotes = remotesOutput.split(separator: "\n").map {
            String($0).trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }
        
        return output.split(separator: "\n").compactMap { line in
            let name = String(line).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, name.lowercased().contains(query) else { return nil }
            let isRemote = remotes.contains { remote in
                name.hasPrefix("\(remote)/")
            }
            return SearchResult(
                type: .branch,
                title: name,
                subtitle: isRemote ? "Remote" : "Local",
                action: .checkoutBranch(name),
                badge: isRemote ? "Remote" : nil
            )
        }.prefix(20).map { $0 }
    }
    
    private func searchTags(query: String, in repositoryURL: URL) async -> [SearchResult] {
        let output = (try? await runGit(
            arguments: ["tag", "-l", "--format=%(refname:short)"],
            in: repositoryURL
        )) ?? ""
        
        let matchingTags = output.split(separator: "\n").map {
            String($0).trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty && $0.lowercased().contains(query) }
        .prefix(20)
        
        var results: [SearchResult] = []
        for name in matchingTags {
            // Get commit hash for the tag
            let hash = (try? await runGit(
                arguments: ["rev-list", "-n", "1", name],
                in: repositoryURL
            ))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let shortHash = hash.isEmpty ? "" : String(hash.prefix(7))
            
            results.append(SearchResult(
                type: .tag,
                title: name,
                subtitle: shortHash.isEmpty ? "Tag" : shortHash,
                action: .showTag(name),
                badge: nil
            ))
        }
        return results
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
