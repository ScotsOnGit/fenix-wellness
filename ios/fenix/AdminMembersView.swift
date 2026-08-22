//
//  AdminMembersView.swift
//  fenix
//
//  Created by Codex on 11/6/2026.
//

import SwiftUI
import UniformTypeIdentifiers

struct AdminMembersView: View {
    @Environment(AppModel.self) private var appModel
    @State private var query = ""

    var body: some View {
        List {
            Section {
                TextField("Search name, email, or phone", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { Task { await appModel.searchMembers(query: query) } }

                Button {
                    Task { await appModel.searchMembers(query: query) }
                } label: {
                    Label("Search members", systemImage: "magnifyingglass")
                }
            }
            .listRowBackground(FenixTheme.darkCard)

            Section("Members") {
                if appModel.memberSearchResults.isEmpty {
                    Text("No members found.")
                        .foregroundStyle(FenixTheme.darkSecondaryText)
                } else {
                    ForEach(appModel.memberSearchResults) { member in
                        NavigationLink {
                            AdminMemberDetailView(member: member)
                        } label: {
                            AdminMemberRow(member: member)
                        }
                    }
                }
            }
            .listRowBackground(FenixTheme.darkCard)

            if let accountMessage = appModel.accountMessage(for: .members) {
                Section {
                    Text(accountMessage)
                        .foregroundStyle(FenixTheme.darkSecondaryText)
                }
                .listRowBackground(FenixTheme.darkCard)
            }
        }
        .adminListStyle(title: "Members")
        .task { await appModel.searchMembers(query: "") }
        .refreshable { await appModel.searchMembers(query: query) }
    }
}

private struct AdminMemberRow: View {
    let member: UserProfile

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(FenixTheme.actionBlue.opacity(0.25))
                Text(member.initials)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(member.fullName)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(member.email)
                    .font(.footnote)
                    .foregroundStyle(FenixTheme.darkSecondaryText)
            }

            Spacer()

            Text(member.accessStatus.label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(member.canBookWellnessSessions ? .green : FenixTheme.amber)
        }
        .padding(.vertical, 4)
    }
}

struct AdminMemberDetailView: View {
    @Environment(AppModel.self) private var appModel
    let member: UserProfile

    @State private var displayedMember: UserProfile
    @State private var selectedStatus: UserProfile.AccessStatus
    @State private var inductionComplete: Bool
    @State private var programTitle = ""
    @State private var programDescription = ""
    @State private var programType: ResourceKind = .link
    @State private var programURL = ""
    @State private var pdfData: Data?
    @State private var pdfFileName: String?
    @State private var importingPDF = false

    init(member: UserProfile) {
        self.member = member
        _displayedMember = State(initialValue: member)
        _selectedStatus = State(initialValue: member.accessStatus)
        _inductionComplete = State(initialValue: member.inductionCompletedAt != nil)
    }

    private var accessIsDirty: Bool {
        selectedStatus != displayedMember.accessStatus ||
            inductionComplete != (displayedMember.inductionCompletedAt != nil)
    }

    private var canSaveAccess: Bool {
        appModel.loadState != .loading && accessIsDirty
    }

    private var shouldShowApproveButton: Bool {
        displayedMember.accessStatus == .pending || displayedMember.inductionCompletedAt == nil
    }

    private var canAssignProgram: Bool {
        !programTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            (programType == .link ? URL(string: programURL) != nil : pdfData != nil)
    }

    var body: some View {
        List {
            Section("Profile") {
                LabeledContent("Name", value: displayedMember.fullName)
                LabeledContent("Email", value: displayedMember.email)
                LabeledContent("Phone", value: displayedMember.phone.isEmpty ? "Not supplied" : displayedMember.phone)
            }
            .listRowBackground(FenixTheme.darkCard)

            Section("Access") {
                Picker("Status", selection: $selectedStatus) {
                    ForEach(UserProfile.AccessStatus.allCases, id: \.self) { status in
                        Text(status.label).tag(status)
                    }
                }
                Toggle("Induction complete", isOn: $inductionComplete)
                    .tint(FenixTheme.orange)

                if shouldShowApproveButton {
                    Button {
                        selectedStatus = .active
                        inductionComplete = true
                        Task { await saveAccess(status: .active, inductionComplete: true) }
                    } label: {
                        Label("Approve member", systemImage: "person.crop.circle.badge.checkmark")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(FenixTheme.orange)
                    .disabled(appModel.loadState == .loading)
                }

                Button {
                    Task { await saveAccess(status: selectedStatus, inductionComplete: inductionComplete) }
                } label: {
                    Label(accessIsDirty ? "Save access changes" : "Access is up to date", systemImage: "checkmark.circle")
                }
                .disabled(!canSaveAccess)

                if let accountMessage = appModel.accountMessage(for: .members) {
                    Text(accountMessage)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(FenixTheme.darkSecondaryText)
                }
            }
            .listRowBackground(FenixTheme.darkCard)

            Section("Assign Program") {
                TextField("Title", text: $programTitle)
                TextField("Description", text: $programDescription, axis: .vertical)
                Picker("Type", selection: $programType) {
                    ForEach(ResourceKind.allCases, id: \.self) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                if programType == .link {
                    TextField("https://", text: $programURL)
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

                Button {
                    Task {
                        await appModel.assignProgram(
                            to: displayedMember,
                            title: programTitle,
                            description: programDescription,
                            type: programType,
                            url: programURL,
                            pdfData: pdfData,
                            fileName: pdfFileName
                        )
                        if appModel.loadState == .idle {
                            programTitle = ""
                            programDescription = ""
                            programURL = ""
                            pdfData = nil
                            pdfFileName = nil
                        }
                    }
                } label: {
                    Label("Assign program", systemImage: "person.crop.circle.badge.plus")
                }
                .disabled(!canAssignProgram)
            }
            .listRowBackground(FenixTheme.darkCard)

            Section("Assigned Programs") {
                if appModel.selectedMemberPrograms.isEmpty {
                    Text("No personal programs assigned.")
                        .foregroundStyle(FenixTheme.darkSecondaryText)
                } else {
                    ForEach(appModel.selectedMemberPrograms) { program in
                        VStack(alignment: .leading, spacing: 6) {
                            ResourceLinkRow(
                                title: program.title,
                                subtitle: program.description,
                                type: program.resourceType,
                                url: program.url,
                                storagePath: program.storagePath
                            )
                            Button(role: .destructive) {
                                Task { await appModel.archiveProgram(program, member: displayedMember) }
                            } label: {
                                Label("Archive", systemImage: "archivebox")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
            .listRowBackground(FenixTheme.darkCard)

            Section {
                if appModel.selectedMemberBookings.isEmpty {
                    Text("No recent bookings.")
                        .foregroundStyle(FenixTheme.darkSecondaryText)
                } else {
                    ForEach(appModel.selectedMemberBookings) { booking in
                        BookingRow(booking: booking)
                    }
                }
            } header: {
                Text("Recent bookings")
            } footer: {
                Text("Showing the latest 100 bookings for this member.")
            }
            .listRowBackground(FenixTheme.darkCard)

        }
        .adminListStyle(title: displayedMember.fullName)
        .onChange(of: selectedStatus) { _, newStatus in
            if newStatus == .active {
                inductionComplete = true
            }
        }
        .task { await appModel.refreshMemberDetail(displayedMember) }
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
    }

    private func saveAccess(status: UserProfile.AccessStatus, inductionComplete: Bool) async {
        if let updated = await appModel.updateMemberAccess(displayedMember, accessStatus: status, inductionComplete: inductionComplete) {
            displayedMember = updated
            selectedStatus = updated.accessStatus
            self.inductionComplete = updated.inductionCompletedAt != nil
        }
    }
}

#Preview {
    NavigationStack {
        AdminMembersView()
            .environment(AppModel(repository: MockGymBookingRepository()))
    }
}
