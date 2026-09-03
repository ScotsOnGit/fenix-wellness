//
//  AdminResourcesView.swift
//  fenix
//
//  Created by Codex on 11/6/2026.
//

import SwiftUI
import UniformTypeIdentifiers

struct AdminResourcesView: View {
    @Environment(AppModel.self) private var appModel

    @State private var title = ""
    @State private var description = ""
    @State private var category = "General"
    @State private var resourceType: ResourceKind = .link
    @State private var url = ""
    @State private var isPublished = true
    @State private var pdfData: Data?
    @State private var pdfFileName: String?
    @State private var importingPDF = false
    @State private var resourceToDelete: WellnessResource?

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            (resourceType == .link ? FenixURLValidator.webURL(from: url) != nil : pdfData != nil)
    }

    var body: some View {
        List {
            Section("Add Resource") {
                TextField("Title", text: $title)
                TextField("Category", text: $category)
                TextField("Description", text: $description, axis: .vertical)
                Picker("Type", selection: $resourceType) {
                    ForEach(ResourceKind.allCases, id: \.self) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                if resourceType == .link {
                    TextField("https://", text: $url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else {
                    Button {
                        importingPDF = true
                    } label: {
                        Label(pdfFileName ?? "Choose PDF", systemImage: "doc.badge.plus")
                    }
                }
                Toggle("Published", isOn: $isPublished)
                    .tint(FenixTheme.orange)
                Button {
                    Task {
                        await appModel.saveResource(
                            title: title,
                            description: description,
                            category: category,
                            type: resourceType,
                            url: url,
                            pdfData: pdfData,
                            fileName: pdfFileName,
                            isPublished: isPublished
                        )
                        if appModel.loadState == .idle {
                            title = ""
                            description = ""
                            category = "General"
                            url = ""
                            pdfData = nil
                            pdfFileName = nil
                            isPublished = true
                        }
                    }
                } label: {
                    Label("Save resource", systemImage: "plus.circle")
                }
                .disabled(!canSave)
            }
            .listRowBackground(FenixTheme.darkCard)

            Section("Resources") {
                if appModel.resources.isEmpty {
                    Text("No resources found.")
                        .foregroundStyle(FenixTheme.darkSecondaryText)
                } else {
                    ForEach(appModel.resources) { resource in
                        HStack {
                            ResourceLinkRow(
                                title: resource.title,
                                subtitle: resource.description.isEmpty ? resource.category : resource.description,
                                type: resource.resourceType,
                                url: resource.url,
                                storagePath: resource.storagePath
                            )
                            Button(role: .destructive) {
                                resourceToDelete = resource
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
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
        .adminListStyle(title: "Resources")
        .task { await appModel.refreshResourcesAndPrograms() }
        .refreshable { await appModel.refreshResourcesAndPrograms() }
        .fileImporter(isPresented: $importingPDF, allowedContentTypes: [.pdf], allowsMultipleSelection: false) { result in
            if case let .success(urls) = result, let url = urls.first {
                let didAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if didAccess { url.stopAccessingSecurityScopedResource() }
                }
                pdfData = try? Data(contentsOf: url)
                pdfFileName = url.lastPathComponent
            }
        }
        .alert("Delete resource?", isPresented: Binding(
            get: { resourceToDelete != nil },
            set: { if !$0 { resourceToDelete = nil } }
        ), presenting: resourceToDelete) { resource in
            Button("Keep", role: .cancel) { resourceToDelete = nil }
            Button("Delete", role: .destructive) {
                resourceToDelete = nil
                Task { await appModel.deleteResource(resource) }
            }
        } message: { resource in
            Text(resource.title)
        }
    }
}

#Preview {
    NavigationStack {
        AdminResourcesView()
            .environment(AppModel(repository: MockGymBookingRepository()))
    }
}
