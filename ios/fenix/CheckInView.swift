//
//  CheckInView.swift
//  fenix
//
//  Created by Codex on 11/6/2026.
//

import AVFoundation
import SwiftUI

struct CheckInView: View {
    @Environment(AppModel.self) private var appModel
    @State private var manualCode = ""
    @State private var scannerIsActive = false

    private var currentCheckedInBooking: GymBooking? {
        appModel.bookings.first { $0.status == .active && $0.checkedInAt != nil && $0.checkedOutAt == nil }
    }

    var body: some View {
        List {
            Section {
                if let booking = currentCheckedInBooking {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Checked in", systemImage: "checkmark.circle.fill")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.green)
                        Text(FacilityTime.intervalText(start: booking.startTime, end: booking.endTime))
                            .foregroundStyle(FenixTheme.darkSecondaryText)
                        Button {
                            Task { await appModel.checkOut(booking) }
                        } label: {
                            Label("Check out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(FenixTheme.orange)
                    }
                    .padding(.vertical, 4)
                } else {
                    Text("Scan the wellbeing facility QR code when you arrive for your booked session.")
                        .foregroundStyle(FenixTheme.darkSecondaryText)
                }
            }
            .listRowBackground(FenixTheme.darkCard)

            Section("QR Code") {
                Button {
                    scannerIsActive = true
                } label: {
                    Label("Scan QR code", systemImage: "qrcode.viewfinder")
                }
            }
            .listRowBackground(FenixTheme.darkCard)

            Section {
                TextField("QR code", text: $manualCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Button {
                    Task { await appModel.checkIn(code: manualCode) }
                } label: {
                    Label("Check in with code", systemImage: "checkmark.circle")
                }
                .disabled(manualCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: {
                Text("Manual Code")
            } footer: {
                Text("Manual entry is available if the camera cannot scan the QR code.")
            }
            .listRowBackground(FenixTheme.darkCard)

            if let accountMessage = appModel.accountMessage(for: .checkIn) {
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
        .navigationTitle("Check In")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(FenixTheme.loginBlue, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .sheet(isPresented: $scannerIsActive) {
            QRScannerView { code in
                scannerIsActive = false
                manualCode = code
                Task { await appModel.checkIn(code: code) }
            }
            .ignoresSafeArea()
        }
        .task { await appModel.refreshBookings() }
    }
}

struct QRScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> QRScannerController {
        let controller = QRScannerController()
        controller.onCode = onCode
        return controller
    }

    func updateUIViewController(_ uiViewController: QRScannerController, context: Context) {}
}

final class QRScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    private let session = AVCaptureSession()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSession()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [session] in
                session.startRunning()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning {
            session.stopRunning()
        }
    }

    private func configureSession() {
        // Camera permission is handled by AVFoundation. If iOS denies or withholds the
        // camera, the manual code field in CheckInView remains the fallback path.
        guard
            let device = AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            addMessage("Camera is unavailable.")
            return
        }

        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            addMessage("QR scanning is unavailable.")
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.addSublayer(preview)
    }

    private func addMessage(_ message: String) {
        let label = UILabel()
        label.text = message
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let code = metadataObjects.compactMap({ ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }).first else { return }
        // Stop scanning after the first readable code to avoid submitting the same
        // check-in several times while the sheet is dismissing.
        session.stopRunning()
        onCode?(code)
    }
}

#Preview {
    NavigationStack {
        CheckInView()
            .environment(AppModel(repository: MockGymBookingRepository()))
    }
}
