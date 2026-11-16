import SwiftUI

/// Once, right after the first sign-in: the name friends see and the @handle they find you by.
struct HandleSetupView: View {
    @Environment(AccountService.self) private var account
    @State private var name = AppSettings.riderName
    @State private var handle = ""
    @State private var error: String?
    @State private var saving = false
    @FocusState private var field: Field?

    private enum Field { case name, handle }

    private var cleanHandle: String { AccountService.normalisedHandle(handle) }
    private var canSave: Bool {
        !saving && AccountService.isValidHandle(cleanHandle) && !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Pick your @handle").font(.largeTitle.bold().width(.expanded))
                    Text("Friends find you by it in the app. Your email stays private.")
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("NAME").font(Brand.label).tracking(0.8).foregroundStyle(.secondary)
                    TextField("Your name", text: $name)
                        .textContentType(.name)
                        .submitLabel(.next)
                        .focused($field, equals: .name)
                        .onSubmit { field = .handle }
                        .font(.title3)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 56)
                        .background(Brand.card, in: .rect(cornerRadius: 16))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("HANDLE").font(Brand.label).tracking(0.8).foregroundStyle(.secondary)
                    HStack(spacing: 2) {
                        Text("@").font(.title3).foregroundStyle(.secondary)
                        TextField("rajan_rides", text: $handle)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textContentType(.username)
                            .submitLabel(.done)
                            .focused($field, equals: .handle)
                            .onSubmit(save)
                            .font(.title3)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 56)
                    .background(Brand.card, in: .rect(cornerRadius: 16))
                    Text("3–20 letters, numbers, _ or .")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(Brand.signal)
                }

                Button(action: save) {
                    HStack {
                        if saving { ProgressView().tint(Brand.asphalt) }
                        Text("Continue")
                    }
                    .font(.headline)
                    .foregroundStyle(Brand.asphalt)
                    .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.borderedProminent)
                .tint(Brand.highwayYellow)
                .disabled(!canSave)
            }
            .padding(24)
        }
        .background(Brand.page)
        .scrollDismissesKeyboard(.interactively)
        .onAppear { field = name.isEmpty ? .name : .handle }
    }

    private func save() {
        guard canSave else { return }
        saving = true
        Task {
            error = await account.saveProfile(name: name, handle: cleanHandle)
            saving = false
        }
    }
}
