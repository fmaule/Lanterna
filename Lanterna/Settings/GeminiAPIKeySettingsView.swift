import SwiftUI

struct GeminiAPIKeySettingsView: View {
  @Environment(\.dismiss) private var dismiss
  private let settings = SettingsManager.shared

  @State private var apiKey: String = ""

  var body: some View {
    Form {
      Section(header: Text("API Key"), footer: Text("Your Gemini API key. Stored in the iOS keychain.")) {
        TextField("Enter Gemini API key", text: $apiKey)
          .autocapitalization(.none)
          .disableAutocorrection(true)
          .font(.system(.body, design: .monospaced))
      }
    }
    .navigationTitle("API Key")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        Button("Save") {
          save()
          dismiss()
        }
        .fontWeight(.semibold)
      }
    }
    .onAppear { apiKey = settings.geminiAPIKey }
  }

  private func save() {
    settings.geminiAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
