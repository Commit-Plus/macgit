import SwiftUI

struct SearchModalView: View {
    @StateObject private var coordinator: SearchCoordinator
    @FocusState private var isSearchFieldFocused: Bool
    let onDismiss: () -> Void
    let onSelect: (SearchAction) -> Void
    
    init(repositoryURL: URL, onDismiss: @escaping () -> Void, onSelect: @escaping (SearchAction) -> Void) {
        self._coordinator = StateObject(wrappedValue: SearchCoordinator(repositoryURL: repositoryURL))
        self.onDismiss = onDismiss
        self.onSelect = onSelect
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            searchBar
            
            Divider()
            
            // Results
            if coordinator.isLoading && coordinator.results.isEmpty {
                ProgressView()
                    .scaleEffect(0.8)
                    .padding(40)
            } else if coordinator.results.isEmpty && !coordinator.query.isEmpty {
                emptyState
            } else {
                resultsList
            }
            
            // Footer
            footer
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
        .frame(maxWidth: 640, maxHeight: 500)
        .onAppear {
            isSearchFieldFocused = true
        }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
        .onKeyPress(.upArrow) {
            coordinator.selectPrevious()
            return .handled
        }
        .onKeyPress(.downArrow) {
            coordinator.selectNext()
            return .handled
        }
        .onKeyPress(.return) {
            if let result = coordinator.selectedResult() {
                onSelect(result.action)
            }
            return .handled
        }
        .onKeyPress(characters: .alphanumerics) { press in
            // Allow typing to flow into the search field
            return .ignored
        }
    }
    
    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Search")
            
            TextField("Search commits, files, branches...", text: $coordinator.query)
                .font(.system(size: 16))
                .textFieldStyle(.plain)
                .focused($isSearchFieldFocused)
            
            if !coordinator.query.isEmpty {
                Button(action: { coordinator.query = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Clear search")
                }
                .buttonStyle(.plain)
            }
            
            HStack(spacing: 4) {
                Text("⌘⇧F")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
    
    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(groupedResults) { section in
                        Section(header: sectionHeader(title: section.type.rawValue)) {
                            ForEach(section.results) { result in
                                SearchResultRow(
                                    result: result,
                                    isSelected: coordinator.selectedResultID == result.id
                                )
                                .id(result.id)
                                .onTapGesture {
                                    coordinator.selectedResultID = result.id
                                    onSelect(result.action)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            .onChange(of: coordinator.selectedResultID) { _, newID in
                if let newID = newID {
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(newID, anchor: .center)
                    }
                }
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("No results found")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Try a different search term")
                .font(.system(size: 12))
                .foregroundStyle(.secondary.opacity(0.7))
            Spacer()
        }
        .frame(minHeight: 120)
    }
    
    private var footer: some View {
        HStack {
            Text("↑↓ Navigate • ↵ Select")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }
    
    private func sectionHeader(title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
    }
    
    private var groupedResults: [ResultSection] {
        let typeOrder: [SearchResultType] = [.commit, .file, .branch, .tag]
        return typeOrder.compactMap { type in
            let typeResults = coordinator.results.filter { $0.type == type }
            guard !typeResults.isEmpty else { return nil }
            return ResultSection(type: type, results: typeResults)
        }
    }
}

struct ResultSection: Identifiable {
    var id: String { type.rawValue }
    let type: SearchResultType
    let results: [SearchResult]
}
