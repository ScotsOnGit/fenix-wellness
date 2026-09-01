//
//  ChallengesView.swift
//  fenix
//
//  Created by Codex on 11/6/2026.
//

import SwiftUI

struct ChallengesView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        List {
            Section("Wellbeing Challenges") {
                if appModel.challenges.isEmpty {
                    Text("Active wellbeing challenges will appear here.")
                        .foregroundStyle(FenixTheme.darkSecondaryText)
                } else {
                    ForEach(appModel.challenges) { challenge in
                        NavigationLink {
                            ChallengeDetailView(challenge: challenge)
                        } label: {
                            ChallengeRow(challenge: challenge)
                        }
                    }
                }
            }
            .listRowBackground(FenixTheme.darkCard)

            if let accountMessage = appModel.accountMessage(for: .challenges) {
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
        .navigationTitle("Challenges")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(FenixTheme.loginBlue, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task { await appModel.refreshChallenges() }
        .refreshable { await appModel.refreshChallenges() }
    }
}

private struct ChallengeRow: View {
    let challenge: WellbeingChallenge

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(challenge.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text(challenge.status.label)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(challenge.status.tint)
            }

            Text(challenge.challengeType)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FenixTheme.orange)

            Text(challenge.dateRangeText)
                .font(.footnote)
                .foregroundStyle(FenixTheme.darkSecondaryText)

            Text(challenge.metricLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.82))
        }
        .padding(.vertical, 5)
    }
}

private struct ChallengeDetailView: View {
    @Environment(AppModel.self) private var appModel

    let challenge: WellbeingChallenge

    @State private var valueText = ""
    @State private var note = ""
    @State private var entryDate = Date()

    private var value: Double? {
        Double(valueText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var canLogProgress: Bool {
        challenge.status == .active && (value ?? 0) > 0
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text(challenge.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                    Text(challenge.description.isEmpty ? challenge.challengeType : challenge.description)
                        .foregroundStyle(FenixTheme.darkSecondaryText)
                    HStack {
                        Label(challenge.dateRangeText, systemImage: "calendar")
                        Spacer()
                        Text(challenge.targetText)
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(FenixTheme.darkSecondaryText)
                }
            }
            .listRowBackground(FenixTheme.darkCard)

            Section("Rules") {
                Text(challenge.rules.isEmpty ? "Follow the challenge instructions set by the wellbeing facility team." : challenge.rules)
                    .foregroundStyle(FenixTheme.darkSecondaryText)
            }
            .listRowBackground(FenixTheme.darkCard)

            Section {
                TextField(challenge.metricLabel, text: $valueText)
                    .keyboardType(.decimalPad)
                DatePicker("Date", selection: $entryDate, displayedComponents: .date)
                    .tint(FenixTheme.orange)
                TextField("Note", text: $note, axis: .vertical)
                Button {
                    guard let value else { return }
                    Task {
                        await appModel.addChallengeEntry(challenge: challenge, value: value, note: note, entryDate: entryDate)
                        valueText = ""
                        note = ""
                    }
                } label: {
                    Label("Add progress", systemImage: "plus.circle")
                }
                .disabled(!canLogProgress)
            } header: {
                Text("Log Progress")
            } footer: {
                Text("Progress is entered manually. Apple Health is not used.")
            }
            .listRowBackground(FenixTheme.darkCard)

            Section("My Entries") {
                if appModel.selectedChallengeEntries.isEmpty {
                    Text("Your entries for this challenge will appear here.")
                        .foregroundStyle(FenixTheme.darkSecondaryText)
                } else {
                    ForEach(appModel.selectedChallengeEntries) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(FacilityTime.dateText(entry.entryDate))
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                if !entry.note.isEmpty {
                                    Text(entry.note)
                                        .font(.footnote)
                                        .foregroundStyle(FenixTheme.darkSecondaryText)
                                }
                            }
                            Spacer()
                            Text("\(entry.valueText) \(challenge.metricUnit)")
                                .font(.headline)
                                .foregroundStyle(FenixTheme.orange)
                        }
                    }
                }
            }
            .listRowBackground(FenixTheme.darkCard)

            Section("Leaderboard") {
                if !challenge.leaderboardVisible {
                    Text("The leaderboard is hidden for this challenge.")
                        .foregroundStyle(FenixTheme.darkSecondaryText)
                } else if appModel.selectedChallengeLeaderboard.isEmpty {
                    Text("No leaderboard entries yet.")
                        .foregroundStyle(FenixTheme.darkSecondaryText)
                } else {
                    ForEach(appModel.selectedChallengeLeaderboard) { row in
                        HStack {
                            Text("#\(row.rank)")
                                .font(.headline)
                                .foregroundStyle(FenixTheme.orange)
                                .frame(width: 44, alignment: .leading)
                            VStack(alignment: .leading) {
                                Text(row.memberName)
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                Text("\(row.entryCount) entries")
                                    .font(.caption)
                                    .foregroundStyle(FenixTheme.darkSecondaryText)
                            }
                            Spacer()
                            Text("\(row.totalText) \(challenge.metricUnit)")
                                .font(.headline)
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
            .listRowBackground(FenixTheme.darkCard)

            if let accountMessage = appModel.accountMessage(for: .challenges) {
                Section {
                    Text(accountMessage)
                        .foregroundStyle(FenixTheme.darkSecondaryText)
                }
                .listRowBackground(FenixTheme.darkCard)
            }
        }
        .adminListStyle(title: "Challenge")
        .task { await appModel.refreshChallengeDetail(challenge) }
        .refreshable { await appModel.refreshChallengeDetail(challenge) }
        .toolbar {
            Button {
                Task { await appModel.joinChallenge(challenge) }
            } label: {
                Label("Join", systemImage: "person.badge.plus")
            }
            .disabled(challenge.status == .ended || !challenge.isPublished)
        }
    }
}

#Preview {
    NavigationStack {
        ChallengesView()
            .environment(AppModel(repository: MockGymBookingRepository()))
    }
}
