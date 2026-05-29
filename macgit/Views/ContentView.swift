//
//  ContentView.swift
//  macgit
//
//  Created by Thanh Tran on 26/5/26.
//

import SwiftUI

struct ContentView: View {
    @State private var repositoryURL: URL?

    var body: some View {
        Group {
            if let url = repositoryURL {
                MainWindowView(repositoryURL: url)
            } else {
                RepoPickerView(onRepositoryOpened: { url in
                    repositoryURL = url
                })
            }
        }
    }
}
