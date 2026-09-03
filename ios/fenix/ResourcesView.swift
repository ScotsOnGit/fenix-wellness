//
//  ResourcesView.swift
//  fenix
//
//  Created by Codex on 11/6/2026.
//

import SwiftUI

struct ResourcesView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section("My Programs") {
                if appModel.myPrograms.isEmpty {
                    Text("Personal workout programs assigned by an admin will appear here.")
                        .foregroundStyle(FenixTheme.darkSecondaryText)
                } else {
                    ForEach(appModel.myPrograms) { program in
                        ResourceLinkRow(
                            title: program.title,
                            subtitle: program.description,
                            type: program.resourceType,
                            url: program.url,
                            storagePath: program.storagePath
                        )
                    }
                }
            }
            .listRowBackground(FenixTheme.darkCard)

            Section("Wellbeing Resources") {
                if appModel.resources.isEmpty {
                    Text("Workout guides, stretching routines, and wellbeing resources will appear here.")
                        .foregroundStyle(FenixTheme.darkSecondaryText)
                } else {
                    ForEach(appModel.resources.filter(\.isPublished)) { resource in
                        ResourceLinkRow(
                            title: resource.title,
                            subtitle: resource.description.isEmpty ? resource.category : resource.description,
                            type: resource.resourceType,
                            url: resource.url,
                            storagePath: resource.storagePath
                        )
                    }
                }
            }
            .listRowBackground(FenixTheme.darkCard)

            if let accountMessage = appModel.accountMessage(for: .resources) {
                Section {
                    Text(accountMessage)
                        .foregroundStyle(FenixTheme.darkSecondaryText)
                }
                .listRowBackground(FenixTheme.darkCard)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(FenixTheme.loginBlue.ignoresSafeArea())
        .navigationTitle("Resources")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(FenixTheme.loginBlue, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .refreshable { await appModel.refreshResourcesAndPrograms() }
        .task { await appModel.refreshResourcesAndPrograms() }
    }
}

struct ResourceLinkRow: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openURL) private var openURL

    let title: String
    let subtitle: String
    let type: ResourceKind
    let url: String
    let storagePath: String

    var body: some View {
        Button {
            Task { await openResource() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: type == .pdf ? "doc.richtext" : "link")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(FenixTheme.orange)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(FenixTheme.darkSecondaryText)
                    }
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(FenixTheme.darkSecondaryText)
            }
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
    }

    private func openResource() async {
        if type == .link, let linkURL = FenixURLValidator.webURL(from: url) {
            await MainActor.run { openURL(linkURL) }
            return
        }
        if !storagePath.isEmpty, let signedURL = await appModel.signedURL(forStoragePath: storagePath) {
            await MainActor.run { openURL(signedURL) }
        }
    }
}

#Preview {
    NavigationStack {
        ResourcesView()
            .environment(AppModel(repository: MockGymBookingRepository()))
    }
}
