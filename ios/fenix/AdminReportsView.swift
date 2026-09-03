//
//  AdminReportsView.swift
//  fenix
//
//  Created by Codex on 11/6/2026.
//

import SwiftUI
import UniformTypeIdentifiers

struct AdminReportsView: View {
    @Environment(AppModel.self) private var appModel
    @State private var startDate = FacilityTime.calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var endDate = Date()
    @State private var exportDocument: CSVDocument?

    private var rangeIsValid: Bool {
        FacilityTime.calendar.startOfDay(for: startDate) <= FacilityTime.calendar.startOfDay(for: endDate)
    }

    var body: some View {
        List {
            Section("Range") {
                DatePicker("Starts", selection: $startDate, displayedComponents: .date)
                    .tint(FenixTheme.orange)
                DatePicker("Ends", selection: $endDate, displayedComponents: .date)
                    .tint(FenixTheme.orange)
                Button {
                    Task { await appModel.refreshReports(startDate: startDate, endDate: endDate) }
                } label: {
                    Label("Refresh report", systemImage: "arrow.clockwise")
                }
                .disabled(!rangeIsValid)
            }
            .listRowBackground(FenixTheme.darkCard)

            if !rangeIsValid {
                Section {
                    Label("Choose an end date on or after the start date.", systemImage: "calendar.badge.exclamationmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(FenixTheme.amber)
                }
                .listRowBackground(FenixTheme.darkCard)
            }

            Section("Dashboard") {
                HStack(spacing: 10) {
                    AdminSummaryTile(title: "Bookings", value: "\(appModel.reportSummary.totalBookings)", color: .white)
                    AdminSummaryTile(title: "Attendance", value: appModel.reportSummary.attendanceRateText, color: .green)
                    AdminSummaryTile(title: "No-shows", value: "\(appModel.reportSummary.noShowCount)", color: FenixTheme.amber)
                }
                HStack(spacing: 10) {
                    AdminSummaryTile(title: "Members", value: "\(appModel.reportSummary.activeMembers)", color: FenixTheme.actionBlue)
                    AdminSummaryTile(title: "Cancelled", value: "\(appModel.reportSummary.cancelledCount)", color: FenixTheme.alertRed)
                    AdminSummaryTile(title: "Peak", value: appModel.reportSummary.peakHourText, color: FenixTheme.glowGold)
                }
            }
            .listRowBackground(FenixTheme.darkCard)

            Section("Actions") {
                Button {
                    Task { await appModel.markDueNoShows() }
                } label: {
                    Label("Mark due no-shows", systemImage: "person.crop.circle.badge.exclamationmark")
                }

                Button {
                    exportDocument = CSVDocument(text: appModel.exportCSVText())
                } label: {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                }
                .disabled(appModel.bookingExportRows.isEmpty)
            }
            .listRowBackground(FenixTheme.darkCard)

            Section("Recent Audit Log") {
                if appModel.auditLog.isEmpty {
                    Text("No audit events found.")
                        .foregroundStyle(FenixTheme.darkSecondaryText)
                } else {
                    ForEach(appModel.auditLog) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.title)
                                .font(.headline)
                                .foregroundStyle(.white)
                            Text("\(entry.targetType) \(entry.targetID)")
                                .font(.footnote)
                                .foregroundStyle(FenixTheme.darkSecondaryText)
                            Text(FacilityTime.dateText(entry.createdAt) + " " + FacilityTime.timeText(entry.createdAt))
                                .font(.caption)
                                .foregroundStyle(FenixTheme.darkSecondaryText)
                        }
                    }
                }
            }
            .listRowBackground(FenixTheme.darkCard)

            if let accountMessage = appModel.accountMessage(for: .reports) {
                Section {
                    Text(accountMessage)
                        .foregroundStyle(FenixTheme.darkSecondaryText)
                }
                .listRowBackground(FenixTheme.darkCard)
            }
        }
        .adminListStyle(title: "Reports")
        .task {
            if rangeIsValid {
                await appModel.refreshReports(startDate: startDate, endDate: endDate)
            }
        }
        .refreshable {
            if rangeIsValid {
                await appModel.refreshReports(startDate: startDate, endDate: endDate)
            }
        }
        .fileExporter(
            isPresented: Binding(
                get: { exportDocument != nil },
                set: { if !$0 { exportDocument = nil } }
            ),
            document: exportDocument,
            contentType: .commaSeparatedText,
            defaultFilename: "fenix-wellness-bookings.csv"
        ) { _ in
            exportDocument = nil
        }
    }
}

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            text = String(decoding: data, as: UTF8.self)
        } else {
            text = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

#Preview {
    NavigationStack {
        AdminReportsView()
            .environment(AppModel(repository: MockGymBookingRepository()))
    }
}
