//
//  AuthView.swift
//  fenix
//
//  Created by Codex on 5/6/2026.
//

import SwiftUI

struct AuthView: View {
    @Environment(AppModel.self) private var appModel
    @State private var fullName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var phone = ""
    @State private var acceptedWellnessAcknowledgement = false

    @Namespace private var segmentNamespace
    @State private var darkAppeared = false
    @State private var glowPulse = false

    private var isRegistering: Bool {
        appModel.authMode == .register
    }

    private var canSubmit: Bool {
        if isRegistering {
            return !fullName.isEmpty &&
                isValidEmail &&
                password.count >= 8 &&
                password == confirmPassword &&
                acceptedWellnessAcknowledgement
        }
        return !email.isEmpty && !password.isEmpty
    }

    private var isValidEmail: Bool {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanEmail.contains("@") && cleanEmail.contains(".")
    }

    var body: some View {
        NavigationStack {
            loginContent
                .scrollDismissesKeyboard(.interactively)
                .background(FenixTheme.loginBlue.ignoresSafeArea())
                .toolbar(.hidden, for: .navigationBar)
        }
        .tint(FenixTheme.orange)
        .preferredColorScheme(.dark)
    }

    private var loginContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                    .padding(.top, 56)
                    .opacity(darkAppeared ? 1 : 0)
                    .offset(y: darkAppeared ? 0 : 22)
                    .animation(.spring(duration: 0.6, bounce: 0.12), value: darkAppeared)

                segmentedControl
                    .padding(.horizontal, 24)
                    .padding(.top, 36)
                    .opacity(darkAppeared ? 1 : 0)
                    .offset(y: darkAppeared ? 0 : 16)
                    .animation(.spring(duration: 0.6, bounce: 0.12).delay(0.08), value: darkAppeared)

                formFields
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .opacity(darkAppeared ? 1 : 0)
                    .offset(y: darkAppeared ? 0 : 14)
                    .animation(.spring(duration: 0.6, bounce: 0.12).delay(0.16), value: darkAppeared)

                actions
                    .padding(.horizontal, 24)
                    .padding(.top, 22)
                    .padding(.bottom, 48)
                    .opacity(darkAppeared ? 1 : 0)
                    .animation(.spring(duration: 0.6, bounce: 0.12).delay(0.24), value: darkAppeared)
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            Task {
                try? await Task.sleep(for: .milliseconds(80))
                darkAppeared = true
            }
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                glowPulse = true
            }
        }
        .onDisappear {
            darkAppeared = false
            glowPulse = false
        }
    }

    private var header: some View {
        VStack(spacing: 20) {
            // Logo with animated glow rings
            ZStack {
                Circle()
                    .fill(FenixTheme.glowGold)
                    .frame(width: 132, height: 132)
                    .opacity(glowPulse ? 0.38 : 0.18)
                    .scaleEffect(glowPulse ? 1.16 : 0.94)
                    .blur(radius: 18)

                Circle()
                    .fill(FenixTheme.glowGold)
                    .frame(width: 96, height: 96)
                    .opacity(glowPulse ? 0.44 : 0.22)
                    .scaleEffect(glowPulse ? 1.08 : 0.98)
                    .blur(radius: 7)

                ZStack {
                    Circle()
                        .fill(FenixTheme.loginBlue)
                        .frame(width: 76, height: 76)

                    Image("FenixXMark")
                        .resizable()
                        .renderingMode(.original)
                        .scaledToFit()
                        .padding(15)
                        .frame(width: 76, height: 76)
                }
                .shadow(color: FenixTheme.glowGold.opacity(0.46), radius: 13, x: 0, y: 5)
            }

            VStack(spacing: 7) {
                Text(FenixBrand.appName)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(isRegistering ? "Create your staff access" : "Sign in to your account")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FenixTheme.orange)
                    .animation(.easeInOut(duration: 0.2), value: isRegistering)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var segmentedControl: some View {
        HStack(spacing: 0) {
            ForEach([AppModel.AuthMode.signIn, AppModel.AuthMode.register], id: \.self) { mode in
                Button {
                    withAnimation(.spring(duration: 0.38, bounce: 0.08)) {
                        appModel.authMode = mode
                        appModel.authNotice = nil
                    }
                } label: {
                    Text(mode == .signIn ? "Sign In" : "Register")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(appModel.authMode == mode ? .white : .white.opacity(0.40))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background {
                            if appModel.authMode == mode {
                                Capsule()
                                    .fill(Color.white.opacity(0.14))
                                    .matchedGeometryEffect(id: "authModePill", in: segmentNamespace)
                            }
                        }
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.2), value: appModel.authMode)
            }
        }
        .padding(3)
        .background(Color.white.opacity(0.07), in: Capsule())
    }

    private var formFields: some View {
        VStack(spacing: 14) {
            if isRegistering {
                DarkAuthTextField(
                    title: "Full name",
                    text: $fullName,
                    systemImage: "person",
                    textContentType: .name
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .opacity
                ))
            }

            DarkAuthTextField(
                title: "Email",
                text: $email,
                systemImage: "envelope",
                keyboardType: .emailAddress,
                textContentType: .emailAddress,
                autocapitalization: .never
            )

            DarkAuthSecureField(
                title: "Password",
                text: $password,
                textContentType: isRegistering ? .newPassword : .password
            )

            if isRegistering {
                DarkAuthSecureField(
                    title: "Confirm password",
                    text: $confirmPassword,
                    textContentType: .newPassword
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .opacity
                ))

                DarkAuthTextField(
                    title: "Phone (optional)",
                    text: $phone,
                    systemImage: "phone",
                    keyboardType: .phonePad,
                    textContentType: .telephoneNumber
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .opacity
                ))

                if !email.isEmpty && !isValidEmail {
                    Label("Enter a valid email address.", systemImage: "exclamationmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(FenixTheme.amber)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity)
                }

                if !confirmPassword.isEmpty && password != confirmPassword {
                    Label("Passwords do not match.", systemImage: "exclamationmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(FenixTheme.amber)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity)
                }

                Button {
                    acceptedWellnessAcknowledgement.toggle()
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: acceptedWellnessAcknowledgement ? "checkmark.square.fill" : "square")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(acceptedWellnessAcknowledgement ? FenixTheme.orange : FenixTheme.darkSecondaryText)
                        Text("I acknowledge that I use the wellness centre voluntarily and at my own risk, and will seek medical advice first if I have a relevant medical condition, injury, or concern.")
                            .font(.footnote)
                            .foregroundStyle(FenixTheme.darkSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .animation(.spring(duration: 0.42, bounce: 0.05), value: isRegistering)
    }

    private var actions: some View {
        VStack(spacing: 16) {
            Button {
                Task {
                    if isRegistering {
                        await appModel.register(fullName: fullName, email: email, password: password, phone: phone)
                    } else {
                        await appModel.signIn(email: email, password: password)
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    if appModel.loadState == .loading {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(isRegistering ? "Create Account" : "Sign In")
                        .fontWeight(.bold)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(
                    canSubmit ? FenixTheme.orange : FenixTheme.orange.opacity(0.30),
                    in: Capsule()
                )
                .animation(.easeInOut(duration: 0.2), value: canSubmit)
            }
            .buttonStyle(DarkPressButtonStyle())
            .disabled(!canSubmit || appModel.loadState == .loading)

            if !isRegistering {
                Button("Forgot password?") {
                    let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmedEmail.isEmpty {
                        appModel.authNotice = "Enter your email address, then tap Forgot password."
                    } else {
                        Task { await appModel.resetPassword(email: trimmedEmail) }
                    }
                }
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.38))
            }

            if let authNotice = appModel.authNotice {
                Text(authNotice)
                    .font(.footnote)
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }

            if case let .failed(message) = appModel.loadState {
                Text(friendlyError(message))
                    .font(.footnote)
                    .foregroundStyle(FenixTheme.alertRed)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
        }
    }

    private func friendlyError(_ message: String) -> String {
        let lowercased = message.lowercased()
        if lowercased.contains("jwt expired") || lowercased.contains("invalid jwt") {
            return "Your session expired. Please sign in again."
        }
        return message
    }
}

// MARK: - Field components

private struct DarkAuthTextField: View {
    let title: String
    @Binding var text: String
    let systemImage: String
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType?
    var autocapitalization: TextInputAutocapitalization? = .sentences

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(isFocused ? FenixTheme.orange : .white.opacity(0.38))
                .frame(width: 22)
                .animation(.easeInOut(duration: 0.18), value: isFocused)

            TextField(title, text: $text,
                      prompt: Text(title).foregroundStyle(.white.opacity(0.28)))
                .keyboardType(keyboardType)
                .textContentType(textContentType)
                .textInputAutocapitalization(autocapitalization)
                .autocorrectionDisabled()
                .foregroundStyle(.white)
                .focused($isFocused)
        }
        .font(.body.weight(.medium))
        .padding(.horizontal, 16)
        .frame(minHeight: 56)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isFocused ? FenixTheme.orange : Color.white.opacity(0.09),
                    lineWidth: isFocused ? 1.5 : 1
                )
                .animation(.easeInOut(duration: 0.18), value: isFocused)
        }
    }
}

private struct DarkAuthSecureField: View {
    let title: String
    @Binding var text: String
    var textContentType: UITextContentType?

    @FocusState private var isFocused: Bool
    @State private var isVisible = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock")
                .font(.body.weight(.semibold))
                .foregroundStyle(isFocused ? FenixTheme.orange : .white.opacity(0.38))
                .frame(width: 22)
                .animation(.easeInOut(duration: 0.18), value: isFocused)

            Group {
                if isVisible {
                    TextField(title, text: $text,
                              prompt: Text(title).foregroundStyle(.white.opacity(0.28)))
                        .textContentType(textContentType)
                } else {
                    SecureField(title, text: $text,
                                prompt: Text(title).foregroundStyle(.white.opacity(0.28)))
                        .textContentType(textContentType)
                }
            }
            .foregroundStyle(.white)
            .focused($isFocused)

            Button {
                isVisible.toggle()
            } label: {
                Image(systemName: isVisible ? "eye.slash" : "eye")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.42))
                    .frame(width: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isVisible ? "Hide \(title)" : "Show \(title)")
        }
        .font(.body.weight(.medium))
        .padding(.horizontal, 16)
        .frame(minHeight: 56)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isFocused ? FenixTheme.orange : Color.white.opacity(0.09),
                    lineWidth: isFocused ? 1.5 : 1
                )
                .animation(.easeInOut(duration: 0.18), value: isFocused)
        }
    }
}

// MARK: - Button style

private struct DarkPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(duration: 0.22, bounce: 0.3), value: configuration.isPressed)
    }
}

// MARK: - Previews

#Preview {
    AuthView()
        .environment(AppModel(repository: MockGymBookingRepository()))
}
