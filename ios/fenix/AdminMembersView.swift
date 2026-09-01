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
    @Environment(\.dismiss) private var dismiss
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
    @State private var showingRemoveAccessConfirmation = false
    @State private var showingDeleteLoginConfirmation = false

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
        displayedMember.accessStatus != .removed &&
            !programTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            (programType == .link ? FenixURLValidator.webURL(from: programURL) != nil : pdfData != nil)
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
                    .disabled(selectedStatus == .removed)

                if selectedStatus == .removed {
                    Label {
                        Text("Removing access cancels future sessions and archives personal program links/PDF assignments. Past booking history is kept for reporting.")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(FenixTheme.amber)
                    .accessibilityLabel("Removing access cancels future sessions and archives personal programs. Past booking history is kept for reporting.")
                }

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
                    if selectedStatus == .removed {
                        showingRemoveAccessConfirmation = true
                    } else {
                        Task { await saveAccess(status: selectedStatus, inductionComplete: inductionComplete) }
                    }
                } label: {
                    Label(accessButtonTitle, systemImage: selectedStatus == .removed ? "person.crop.circle.badge.xmark" : "checkmark.circle")
                }
                .disabled(!canSaveAccess)

                if let accountMessage = appModel.accountMessage(for: .members) {
                    Text(accountMessage)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(FenixTheme.darkSecondaryText)
                }
            }
            .listRowBackground(FenixTheme.darkCard)

            if displayedMember.accessStatus == .removed {
                Section("Delete Login Account") {
                    Text("This permanently removes this member's sign-in account. If they return later, they will need to register again and be approved again.")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(FenixTheme.darkSecondaryText)
                        .accessibilityLabel("This permanently removes this member's sign-in account. If they return later, they will need to register again and be approved again.")

                    Button(role: .destructive) {
                        showingDeleteLoginConfirmation = true
                    } label: {
                        Label("Delete login account", systemImage: "trash")
                    }
                    .disabled(appModel.loadState == .loading)
                }
                .listRowBackground(FenixTheme.darkCard)
            }

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
            } else if newStatus == .removed {
                inductionComplete = false
            }
        }
        .task { await appModel.refreshMemberDetail(displayedMember) }
        .confirmationDialog(
            "Remove wellbeing facility access?",
            isPresented: $showingRemoveAccessConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove access", role: .destructive) {
                Task { await saveAccess(status: .removed, inductionComplete: false) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cancels future sessions and archives personal program links/PDF assignments for \(displayedMember.fullName).")
        }
        .confirmationDialog(
            "Delete login account?",
            isPresented: $showingDeleteLoginConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete login account", role: .destructive) {
                Task {
                    if await appModel.deleteRemovedMemberLogin(displayedMember) {
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone. Future sessions and personal programs should already be retired because the member is marked Removed.")
        }
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

    private var accessButtonTitle: String {
        if !accessIsDirty {
            return "Access is up to date"
        }
        if selectedStatus == .removed {
            return "Remove access"
        }
        return "Save access changes"
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
