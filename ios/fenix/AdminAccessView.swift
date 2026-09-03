//
//  AdminAccessView.swift
//  fenix
//
//  Created by Codex on 6/6/2026.
//

import SwiftUI

struct AdminAccessView: View {
    @Environment(AppModel.self) private var appModel
    @State private var email = ""
    @State private var adminToDemote: UserProfile?

    private var canPromote: Bool {
        email.trimmingCharacters(in: .whitespacesAndNewlines).contains("@") &&
            appModel.loadState != .loading
    }

    var body: some View {
        List {
            Section {
                TextField("staff@example.com", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button {
                    let targetEmail = email
                    Task {
                        let didPromote = await appModel.promoteAdmin(email: targetEmail)
                        if didPromote {
                            email = ""
                        }
                    }
                } label: {
                    if appModel.loadState == .loading {
                        Label("Adding admin", systemImage: "hourglass")
                    } else {
                        Label("Add admin", systemImage: "person.badge.plus")
                    }
                }
                .disabled(!canPromote)
            } header: {
                Text("Add Admin")
            } footer: {
                Text("The staff member must already have a registered account. Admin access should only be given to trusted users who manage bookings and wellbeing facility settings.")
            }
            .listRowBackground(FenixTheme.darkCard)

            if let accountMessage = appModel.accountMessage(for: .access) {
                Section {
                    Label(accountMessage, systemImage: "info.circle")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(FenixTheme.darkSecondaryText)
                }
                .listRowBackground(FenixTheme.darkCard)
            }

            Section("Current Admins") {
                if appModel.adminProfiles.isEmpty {
                    Text("No admins found.")
                        .foregroundStyle(FenixTheme.darkSecondaryText)
                } else {
                    ForEach(appModel.adminProfiles) { admin in
                        AdminProfileRow(
                            admin: admin,
                            isCurrentUser: admin.id == appModel.profile?.id
                        ) {
                            adminToDemote = admin
                        }
                        .listRowBackground(FenixTheme.darkCard)
                    }
                }
            }
            .listRowBackground(FenixTheme.darkCard)

            Section {
                Label("Admins can edit opening hours, booking rules, blackout periods, contact details, bookings, and admin access.", systemImage: "lock.shield")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(FenixTheme.darkSecondaryText)
            }
            .listRowBackground(FenixTheme.darkCard)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(FenixTheme.loginBlue.ignoresSafeArea())
        .foregroundStyle(.white)
        .navigationTitle("Access")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(FenixTheme.loginBlue, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .refreshable {
            await appModel.refreshAdminProfiles()
        }
        .task {
            await appModel.refreshAdminProfiles()
        }
        .alert("Remove admin access?", isPresented: Binding(
            get: { adminToDemote != nil },
            set: { if !$0 { adminToDemote = nil } }
        ), presenting: adminToDemote) { admin in
            Button("Keep Admin", role: .cancel) {
                adminToDemote = nil
            }
            Button("Remove Access", role: .destructive) {
                adminToDemote = nil
                Task { await appModel.demoteAdmin(admin) }
            }
        } message: { admin in
            Text("\(admin.email) will keep their staff account but lose admin features.")
        }
    }
}

private struct AdminProfileRow: View {
    let admin: UserProfile
    let isCurrentUser: Bool
    let demote: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(FenixTheme.actionBlue.opacity(0.25))
                Text(admin.initials)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(admin.fullName)
                        .font(.headline)
                        .foregroundStyle(.white)
                    if isCurrentUser {
                        Text("You")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(FenixTheme.orange, in: Capsule())
                    }
                }

                Text(admin.email)
                    .font(.footnote)
                    .foregroundStyle(FenixTheme.darkSecondaryText)
            }

            Spacer()

            if !isCurrentUser {
                Button(role: .destructive, action: demote) {
                    Image(systemName: "person.badge.minus")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove admin access")
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        AdminAccessView()
            .environment(AppModel(repository: MockGymBookingRepository()))
    }
}
