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
import Combine

@MainActor
final class SearchCoordinator: ObservableObject {
    @Published var query: String = ""
    @Published var results: [SearchResult] = []
    @Published var isLoading: Bool = false
    @Published var selectedResultID: UUID?
    @Published var selectedFilter: SearchFilter
    
    private var cancellables = Set<AnyCancellable>()
    private var searchTask: Task<Void, Never>?
    private let repositoryURL: URL
    
    init(repositoryURL: URL, selectedFilter: SearchFilter = .all) {
        self.repositoryURL = repositoryURL
        self.selectedFilter = selectedFilter
        
        $query
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] query in
                self?.performSearch(query: query)
            }
            .store(in: &cancellables)
    }
    
    private func performSearch(query: String) {
        searchTask?.cancel()
        
        guard !query.isEmpty else {
            results = []
            selectedResultID = nil
            isLoading = false
            return
        }
        
        isLoading = true
        
        searchTask = Task { [weak self] in
            guard let self = self else { return }
            defer { self.searchTask = nil }
            let searchResults = await GitStatusService.shared.search(query: query, in: repositoryURL)
            
            if Task.isCancelled { return }
            
            await MainActor.run {
                self.results = searchResults
                self.selectedResultID = self.filteredResults.first?.id
                self.isLoading = false
            }
        }
    }

    var filteredResults: [SearchResult] {
        guard let resultType = selectedFilter.resultType else { return results }
        return results.filter { $0.type == resultType }
    }

    func selectFilter(_ filter: SearchFilter) {
        selectedFilter = filter
        selectedResultID = filteredResults.first?.id
    }
    
    func selectNext() {
        guard let currentID = selectedResultID,
              let currentIndex = filteredResults.firstIndex(where: { $0.id == currentID }),
              currentIndex + 1 < filteredResults.count else { return }
        selectedResultID = filteredResults[currentIndex + 1].id
    }
    
    func selectPrevious() {
        guard let currentID = selectedResultID,
              let currentIndex = filteredResults.firstIndex(where: { $0.id == currentID }),
              currentIndex > 0 else { return }
        selectedResultID = filteredResults[currentIndex - 1].id
    }
    
    func selectedResult() -> SearchResult? {
        guard let selectedResultID = selectedResultID else { return nil }
        return filteredResults.first(where: { $0.id == selectedResultID })
    }
    
    func clear() {
        query = ""
        results = []
        selectedResultID = nil
        isLoading = false
        searchTask?.cancel()
    }
}
