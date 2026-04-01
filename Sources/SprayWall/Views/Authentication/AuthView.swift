import SwiftData
import SwiftUI

struct AuthView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var modelContext

    @State private var displayName = ""
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        @Bindable var appModel = appModel

        NavigationStack {
            Form {
                Picker("Mode", selection: $appModel.authMode) {
                    Text("Login").tag(AppModel.AuthMode.login)
                    Text("Register").tag(AppModel.AuthMode.register)
                }
                .pickerStyle(.segmented)

                if appModel.authMode == .register {
                    TextField("Display name", text: $displayName)
                }

                TextField("Email", text: $email)
#if os(iOS)
                    .keyboardType(.emailAddress)
#endif

                SecureField("Password", text: $password)

                Button(action: submit) {
                    Text(appModel.authMode == .login ? "Sign In" : "Create Account")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                if let authError = appModel.authErrorMessage {
                    Text(authError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Spray Wall")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text("Digital Twin")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func submit() {
        switch appModel.authMode {
        case .login:
            appModel.login(email: email, password: password, context: modelContext)
        case .register:
            appModel.register(
                displayName: displayName,
                email: email,
                password: password,
                context: modelContext
            )
        }

        if appModel.isAuthenticated {
            email = ""
            password = ""
            displayName = ""
        }
    }
}
