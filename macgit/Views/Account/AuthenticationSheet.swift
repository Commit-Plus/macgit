//
//  macgit (Commit+) - a macOS Git client built with Swift and SwiftUI.
//  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//

import SwiftUI

struct AuthenticationSheet: View {
    @ObservedObject var controller: AccountSessionController
    @State private var mode: AuthenticationMode
    @State private var email = ""
    @State private var password = ""

    init(controller: AccountSessionController, mode: AuthenticationMode) {
        self.controller = controller
        _mode = State(initialValue: mode)
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.title2)
                .bold()

            if controller.pendingLinkEmail == nil {
                Picker("Account action", selection: $mode) {
                    ForEach(AuthenticationMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: mode) {
                    controller.errorMessage = nil
                }
            } else {
                Text("Enter the password for your existing Commit+ account. Google will be linked to the same account.")
                    .foregroundStyle(.secondary)
            }

            Form {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .disabled(controller.pendingLinkEmail != nil)
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .onSubmit(submit)
            }
            .formStyle(.grouped)

            if let errorMessage = controller.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .accessibilityLabel("Error: \(errorMessage)")
            }

            if let passwordResetMessage = controller.passwordResetMessage {
                Label(passwordResetMessage, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            if mode == .signIn, controller.pendingLinkEmail == nil {
                Button("Forgot Password?", action: sendPasswordReset)
                    .buttonStyle(.link)
                    .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || controller.isLoading)
            }

            Button("Continue with Google", systemImage: "person.crop.circle.badge.plus", action: signInWithGoogle)
                .frame(maxWidth: .infinity)
                .disabled(controller.isLoading || controller.pendingLinkEmail != nil)

            Button("Sign in with Apple · Coming later", systemImage: "apple.logo") {}
                .frame(maxWidth: .infinity)
                .disabled(true)

            Text("You can keep using Commit+ and all local Git features without an account.")
                .foregroundStyle(.secondary)

            HStack {
                Button("Cancel", role: .cancel, action: cancel)
                Spacer()
                if controller.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Signing in")
                }
                Button(primaryActionTitle, action: submit)
                    .buttonStyle(.borderedProminent)
                    .disabled(primaryActionDisabled)
            }
        }
        .padding()
        .frame(minWidth: 440)
        .interactiveDismissDisabled(controller.isLoading)
        .onAppear(perform: populatePendingLinkEmail)
        .onChange(of: controller.pendingLinkEmail) {
            populatePendingLinkEmail()
        }
    }

    private var title: String {
        if controller.pendingLinkEmail != nil {
            "Link Google Account"
        } else {
            mode.rawValue
        }
    }

    private var primaryActionTitle: String {
        if controller.pendingLinkEmail != nil {
            "Link Account"
        } else {
            mode.rawValue
        }
    }

    private var primaryActionDisabled: Bool {
        email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || password.count < 6
            || controller.isLoading
            || !controller.cloudFeaturesAvailable
    }

    private func submit() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            if controller.pendingLinkEmail != nil {
                await controller.completePendingLink(password: password)
            } else if mode == .signIn {
                await controller.signIn(email: trimmedEmail, password: password)
            } else {
                await controller.createAccount(email: trimmedEmail, password: password)
            }
        }
    }

    private func sendPasswordReset() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            await controller.sendPasswordReset(email: trimmedEmail)
        }
    }

    private func signInWithGoogle() {
        Task {
            await controller.signInWithGoogle()
        }
    }

    private func cancel() {
        controller.presentedSheet = nil
    }

    private func populatePendingLinkEmail() {
        if let pendingLinkEmail = controller.pendingLinkEmail {
            email = pendingLinkEmail
            password = ""
        }
    }
}
