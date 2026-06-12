#!/usr/bin/env swift

import Foundation

// Test the git commands that branchSyncStatus uses
let repoURL = URL(fileURLWithPath: "/Users/thanhtran/Project/macgit")

// Test upstreamBranch
let upstreamTask = Process()
upstreamTask.executableURL = URL(fileURLWithPath: "/usr/bin/git")
upstreamTask.arguments = ["rev-parse", "--abbrev-ref", "main@{upstream}"]
upstreamTask.currentDirectoryURL = repoURL
let upstreamPipe = Pipe()
upstreamTask.standardOutput = upstreamPipe
upstreamTask.standardError = Pipe()
try! upstreamTask.run()
upstreamTask.waitUntilExit()
let upstreamData = upstreamPipe.fileHandleForReading.readDataToEndOfFile()
let upstream = String(data: upstreamData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
print("Upstream: \(upstream ?? "nil")")

// Test rev-list
let revListTask = Process()
revListTask.executableURL = URL(fileURLWithPath: "/usr/bin/git")
revListTask.arguments = ["rev-list", "--count", "--left-right", "\(upstream ?? "origin/main")...main"]
revListTask.currentDirectoryURL = repoURL
let revListPipe = Pipe()
revListTask.standardOutput = revListPipe
revListTask.standardError = Pipe()
try! revListTask.run()
revListTask.waitUntilExit()
let revListData = revListPipe.fileHandleForReading.readDataToEndOfFile()
let revList = String(data: revListData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
print("Rev-list output: \(revList ?? "nil")")

if let line = revList {
    let parts = line.split(separator: "\t").map { String($0) }
    if parts.count == 2, let behind = Int(parts[0]), let ahead = Int(parts[1]) {
        print("Behind: \(behind), Ahead: \(ahead)")
    } else {
        print("Failed to parse: \(parts)")
    }
}
