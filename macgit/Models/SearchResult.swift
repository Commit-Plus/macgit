import Foundation

enum SearchResultType: String, CaseIterable {
    case commit = "Commits"
    case file = "Files"
    case branch = "Branches"
    case tag = "Tags"
    
    var icon: String {
        switch self {
        case .commit: return "doc.text"
        case .file: return "doc"
        case .branch: return "leaf"
        case .tag: return "tag"
        }
    }
}

enum SearchAction: Hashable {
    case showCommit(String)        // commit hash
    case showFile(String)           // file path relative to repo root
    case checkoutBranch(String)     // branch name
    case showTag(String)            // tag name
}

struct SearchResult: Identifiable, Hashable {
    let id = UUID()
    let type: SearchResultType
    let title: String
    let subtitle: String
    let action: SearchAction
    let badge: String?
    
    static func == (lhs: SearchResult, rhs: SearchResult) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
