//
//  SupabaseConfig.swift
//  fenix
//
//  Created by Codex on 5/6/2026.
//

import Foundation

/// Project-specific values are deliberately kept out of source control.
/// Copy `SupabaseConfig.plist.example` to `SupabaseConfig.plist`, add it to the
/// app target, and supply the values from the receiving organisation's project.
enum SupabaseConfig {
    private static let values: [String: Any] = {
        guard
            let url = Bundle.main.url(forResource: "SupabaseConfig", withExtension: "plist"),
            let values = NSDictionary(contentsOf: url) as? [String: Any]
        else {
            preconditionFailure("Missing SupabaseConfig.plist. Follow the repository README before running the app.")
        }
        return values
    }()

    nonisolated static let projectURL: URL = {
        guard let value = values["ProjectURL"] as? String, let url = URL(string: value) else {
            preconditionFailure("SupabaseConfig.plist has no valid ProjectURL.")
        }
        return url
    }()

    nonisolated static let publishableKey: String = {
        guard let value = values["PublishableKey"] as? String, !value.isEmpty else {
            preconditionFailure("SupabaseConfig.plist has no PublishableKey.")
        }
        return value
    }()
}
