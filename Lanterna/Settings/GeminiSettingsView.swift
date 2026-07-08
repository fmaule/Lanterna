import SwiftUI

struct GeminiSettingsView: View {
  @Environment(\.dismiss) private var dismiss
  private let settings = SettingsManager.shared

  @State private var apiKey: String = ""
  @State private var voiceName: String = GeminiConfig.defaultVoiceName
  @State private var systemPrompt: String = ""

  var body: some View {
    Form {
      Section(header: Text("API Key")) {
        TextField("Enter Gemini API key", text: $apiKey)
          .autocapitalization(.none)
          .disableAutocorrection(true)
          .font(.system(.body, design: .monospaced))
      }

      Section(header: Text("Voice"), footer: Text("Which Gemini prebuilt voice to use. Takes effect on the next session.")) {
        Picker("Voice", selection: $voiceName) {
          ForEach(GeminiConfig.availableVoices, id: \.self) { name in
            Text(name).tag(name)
          }
        }
      }

      Section(header: Text("System Prompt"), footer: Text("Customize the AI assistant's behavior and personality. Changes take effect on the next Gemini session.")) {
        TextEditor(text: $systemPrompt)
          .font(.system(.body, design: .monospaced))
          .frame(minHeight: 200)
      }
    }
    .navigationTitle("Gemini")
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
    .onAppear(perform: load)
  }

  private func load() {
    apiKey = settings.geminiAPIKey
    voiceName = settings.geminiVoiceName
    systemPrompt = settings.geminiSystemPrompt
  }

  private func save() {
    settings.geminiAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    settings.geminiVoiceName = voiceName
    settings.geminiSystemPrompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
