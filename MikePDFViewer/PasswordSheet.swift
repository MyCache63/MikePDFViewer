import SwiftUI
import PDFKit

struct PasswordSheet: View {
    let document: PDFDocument
    let onUnlock: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var error = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text("This PDF is password protected")
                .font(.headline)

            SecureField("Enter password", text: $password)
                .textFieldStyle(.roundedBorder)
                .frame(width: 250)
                .onSubmit { tryUnlock() }

            if error {
                Text("Incorrect password")
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Unlock") { tryUnlock() }
                    .buttonStyle(.borderedProminent)
                    .disabled(password.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(30)
        .frame(width: 350)
    }

    private func tryUnlock() {
        if document.unlock(withPassword: password) {
            error = false
            onUnlock()
            dismiss()
        } else {
            error = true
        }
    }
}

struct EncryptSheet: View {
    let document: PDFDocument
    let currentURL: URL?
    @Environment(\.dismiss) private var dismiss
    @State private var ownerPassword = ""
    @State private var userPassword = ""
    @State private var confirmPassword = ""
    @State private var error = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Protect PDF with Password")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Owner Password (full access):")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField("Owner password", text: $ownerPassword)
                    .textFieldStyle(.roundedBorder)

                Text("User Password (to open):")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField("User password", text: $userPassword)
                    .textFieldStyle(.roundedBorder)

                SecureField("Confirm user password", text: $confirmPassword)
                    .textFieldStyle(.roundedBorder)
            }
            .frame(width: 300)

            if !error.isEmpty {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Protect") { encrypt() }
                    .buttonStyle(.borderedProminent)
                    .disabled(ownerPassword.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(30)
        .frame(width: 400)
    }

    private func encrypt() {
        guard userPassword == confirmPassword else {
            error = "User passwords don't match"
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = currentURL?.lastPathComponent ?? "Protected.pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        var options: [PDFDocumentWriteOption: Any] = [
            .ownerPasswordOption: ownerPassword
        ]
        if !userPassword.isEmpty {
            options[.userPasswordOption] = userPassword
        }

        if document.write(to: url, withOptions: options) {
            dismiss()
        } else {
            error = "Failed to write protected PDF"
        }
    }
}
