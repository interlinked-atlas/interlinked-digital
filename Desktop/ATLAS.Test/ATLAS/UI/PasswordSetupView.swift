import SwiftUI

struct PasswordSetupView: View {
    @State private var password: String = ""
    @State private var errorMessage: String = ""
    @State private var isVerifying: Bool = false
    @FocusState private var fieldFocused: Bool
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 24) {

            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text("ATLAS needs your Mac password")
                .font(.title2.bold())

            Text("Used to install software on your behalf. Stored securely in your Mac's Keychain — never sent anywhere.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            SecureField("Enter your Mac login password", text: $password)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
                .focused($fieldFocused)
                .onSubmit { savePassword() }

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            Button(isVerifying ? "Verifying..." : "Save & Continue") {
                savePassword()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(password.isEmpty || isVerifying)

            Text("Encrypted and stored in macOS Keychain only.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(40)
        .frame(minWidth: 480)
        .onAppear {
            // Delay slightly so the window is ready before grabbing focus
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                fieldFocused = true
            }
        }
    }

    private func savePassword() {
        guard !password.isEmpty else {
            errorMessage = "Password cannot be empty."
            return
        }

        isVerifying = true
        errorMessage = ""

        DispatchQueue.global().async {
            let verified = verifyPassword(password)
            DispatchQueue.main.async {
                isVerifying = false
                if verified {
                    let saved = KeychainManager.savePassword(password)
                    if saved {
                        onComplete()
                    } else {
                        errorMessage = "Could not save to Keychain. Please try again."
                    }
                } else {
                    errorMessage = "Incorrect password. Please try again."
                }
            }
        }
    }

    private func verifyPassword(_ pwd: String) -> Bool {
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["-S", "true"]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
            let passwordData = (pwd + "\n").data(using: .utf8)!
            inputPipe.fileHandleForWriting.write(passwordData)
            inputPipe.fileHandleForWriting.closeFile()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
