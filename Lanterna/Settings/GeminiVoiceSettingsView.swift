import SwiftUI

struct GeminiVoiceSettingsView: View {
  @Environment(\.dismiss) private var dismiss
  private let settings = SettingsManager.shared

  @State private var voiceName: String = GeminiConfig.defaultVoiceName

  var body: some View {
    Form {
      Section(footer: Text("Which Gemini prebuilt voice to use. Takes effect on the next session.")) {
        Picker("Voice", selection: $voiceName) {
          ForEach(GeminiConfig.availableVoices, id: \.self) { name in
            Text(name).tag(name)
          }
        }
        .pickerStyle(.inline)
        .labelsHidden()
      }
    }
    .navigationTitle("Voice")
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
    .onAppear { voiceName = settings.geminiVoiceName }
  }

  private func save() {
    settings.geminiVoiceName = voiceName
  }
}
