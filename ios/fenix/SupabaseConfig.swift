//
//  SupabaseConfig.swift
//  fenix
//
//  Created by Codex on 5/6/2026.
//

import Foundation

enum SupabaseConfig {
    nonisolated static var projectURL: URL {
        guard let url = URL(string: stringValue(for: "ProjectURL")),
              url.scheme == "https",
              url.host?.isEmpty == false else {
            preconditionFailure("Set ProjectURL in SupabaseConfig.plist from the receiving company's Supabase project.")
        }
        return url
    }

    nonisolated static var publishableKey: String {
        let key = stringValue(for: "PublishableKey")
        guard !key.isEmpty, !key.contains("REPLACE_WITH") else {
            preconditionFailure("Set PublishableKey in SupabaseConfig.plist from the receiving company's Supabase project.")
        }
        return key
    }

    private nonisolated static func stringValue(for key: String) -> String {
        guard let url = Bundle.main.url(forResource: "SupabaseConfig", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String],
              let value = plist[key]?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            preconditionFailure("Copy SupabaseConfig.plist.example to SupabaseConfig.plist and set \(key).")
        }
        return value
    }
}
