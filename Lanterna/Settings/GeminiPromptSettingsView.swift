import SwiftUI

struct GeminiPromptSettingsView: View {
  @Environment(\.dismiss) private var dismiss
  private let settings = SettingsManager.shared

  @State private var systemPrompt: String = ""

  var body: some View {
    Form {
      Section(footer: Text("Customize the AI assistant's behavior and personality. Changes take effect on the next Gemini session.")) {
        TextEditor(text: $systemPrompt)
          .font(.system(size: 12, design: .monospaced))
          .frame(minHeight: 400)
      }
    }
    .navigationTitle("Prompt")
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
    .onAppear { systemPrompt = settings.geminiSystemPrompt }
  }

  private func save() {
    settings.geminiSystemPrompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
