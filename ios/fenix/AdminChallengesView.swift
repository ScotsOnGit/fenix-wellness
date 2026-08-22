//
//  AdminChallengesView.swift
//  fenix
//
//  Created by Codex on 11/6/2026.
//

import SwiftUI

struct AdminChallengesView: View {
    @Environment(AppModel.self) private var appModel

    @State private var editingChallenge: WellbeingChallenge?
    @State private var challengeToDelete: WellbeingChallenge?

    var body: some View {
        List {
            Section {
                Button {
                    editingChallenge = .blank
                } label: {
                    Label("Add challenge", systemImage: "plus.circle")
                }
            }
            .listRowBackground(FenixTheme.darkCard)

            Section("Challenges") {
                if appModel.challenges.isEmpty {
                    Text("No challenges found.")
                        .foregroundStyle(FenixTheme.darkSecondaryText)
                } else {
                    ForEach(appModel.challenges) { challenge in
                        Button {
                            editingChallenge = challenge
                        } label: {
                            AdminChallengeRow(challenge: challenge)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button(role: .destructive) {
                                challengeToDelete = challenge
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
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
        .adminListStyle(title: "Challenges")
        .task { await appModel.refreshChallenges() }
        .refreshable { await appModel.refreshChallenges() }
        .sheet(item: $editingChallenge) { challenge in
            NavigationStack {
                ChallengeEditorView(challenge: challenge)
            }
        }
        .alert("Delete challenge?", isPresented: Binding(
            get: { challengeToDelete != nil },
            set: { if !$0 { challengeToDelete = nil } }
        ), presenting: challengeToDelete) { challenge in
            Button("Keep", role: .cancel) { challengeToDelete = nil }
            Button("Delete", role: .destructive) {
                challengeToDelete = nil
                Task { await appModel.deleteChallenge(challenge) }
            }
        } message: { challenge in
            Text(challenge.title)
        }
    }
}

private struct AdminChallengeRow: View {
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
            Text("\(challenge.challengeType) • \(challenge.metricLabel)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(FenixTheme.orange)
            Text(challenge.dateRangeText)
                .font(.footnote)
                .foregroundStyle(FenixTheme.darkSecondaryText)
            Text(challenge.leaderboardVisible ? "Leaderboard visible" : "Leaderboard hidden")
                .font(.caption.weight(.semibold))
                .foregroundStyle(FenixTheme.darkSecondaryText)
        }
        .padding(.vertical, 5)
    }
}

private struct ChallengeEditorView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var challenge: WellbeingChallenge
    @State private var targetText: String

    private var targetValue: Double? {
        let clean = targetText.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : Double(clean)
    }

    init(challenge: WellbeingChallenge) {
        _challenge = State(initialValue: challenge)
        _targetText = State(initialValue: challenge.targetValue?.cleanEditorText ?? "")
    }

    var body: some View {
        List {
            Section("Details") {
                TextField("Title", text: $challenge.title)
                TextField("Description", text: $challenge.description, axis: .vertical)
                TextField("Challenge type, e.g. Steps", text: $challenge.challengeType)
                TextField("Metric name, e.g. Steps", text: $challenge.metricName)
                TextField("Metric unit, e.g. steps", text: $challenge.metricUnit)
                TextField("Target value optional", text: $targetText)
                    .keyboardType(.decimalPad)
            }
            .listRowBackground(FenixTheme.darkCard)

            Section("Dates") {
                DatePicker("Starts", selection: $challenge.startsOn, displayedComponents: .date)
                    .tint(FenixTheme.orange)
                DatePicker("Ends", selection: $challenge.endsOn, displayedComponents: .date)
                    .tint(FenixTheme.orange)
            }
            .listRowBackground(FenixTheme.darkCard)

            Section("Rules") {
                TextField("Rules", text: $challenge.rules, axis: .vertical)
                    .lineLimit(4...8)
            }
            .listRowBackground(FenixTheme.darkCard)

            Section {
                Toggle("Published", isOn: $challenge.isPublished)
                    .tint(FenixTheme.orange)
                Toggle("Show leaderboard", isOn: $challenge.leaderboardVisible)
                    .tint(FenixTheme.orange)
            } header: {
                Text("Visibility")
            } footer: {
                Text("Entries are manual. Apple Health is not used. Hidden leaderboards still allow admins to review progress.")
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
        .adminListStyle(title: "Edit Challenge")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    challenge.targetValue = targetValue
                    Task {
                        await appModel.saveChallenge(challenge)
                        if appModel.loadState == .idle {
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}

private extension WellbeingChallenge {
    static var blank: WellbeingChallenge {
        let today = FacilityTime.calendar.startOfDay(for: Date())
        return WellbeingChallenge(
            id: UUID(),
            title: "",
            description: "",
            challengeType: "Steps",
            metricName: "Steps",
            metricUnit: "steps",
            targetValue: nil,
            startsOn: today,
            endsOn: FacilityTime.calendar.date(byAdding: .day, value: 14, to: today) ?? today,
            rules: "",
            leaderboardVisible: true,
            isPublished: false,
            createdAt: Date()
        )
    }
}

private extension Double {
    var cleanEditorText: String {
        if rounded() == self {
            return String(Int(self))
        }
        return String(format: "%.2f", self)
    }
}

#Preview {
    NavigationStack {
        AdminChallengesView()
            .environment(AppModel(repository: MockGymBookingRepository()))
    }
}
