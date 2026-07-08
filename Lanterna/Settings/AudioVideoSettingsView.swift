import SwiftUI

struct AudioVideoSettingsView: View {
  @Environment(\.dismiss) private var dismiss
  private let settings = SettingsManager.shared

  @State private var speakerOutputEnabled: Bool = false
  @State private var videoStreamingEnabled: Bool = true
  @State private var toolCallSoundsEnabled: Bool = true

  var body: some View {
    Form {
      Section(header: Text("Audio"), footer: Text("Route audio output to the iPhone speaker instead of glasses. Useful for demos where others need to hear.")) {
        Toggle("Speaker Output", isOn: $speakerOutputEnabled)
      }

      Section(header: Text("Video"), footer: Text("Disable video streaming to save battery. Audio remains active for voice-only interaction.")) {
        Toggle("Video Streaming", isOn: $videoStreamingEnabled)
      }

      Section(header: Text("Feedback"), footer: Text("Play a short sound and vibration when the assistant starts, finishes, fails, or cancels a task. Helpful when you can't see the status pill.")) {
        Toggle("Task Sounds & Haptics", isOn: $toolCallSoundsEnabled)
      }
    }
    .navigationTitle("Audio & Video")
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
    speakerOutputEnabled = settings.speakerOutputEnabled
    videoStreamingEnabled = settings.videoStreamingEnabled
    toolCallSoundsEnabled = settings.toolCallSoundsEnabled
  }

  private func save() {
    settings.speakerOutputEnabled = speakerOutputEnabled
    settings.videoStreamingEnabled = videoStreamingEnabled
    settings.toolCallSoundsEnabled = toolCallSoundsEnabled
  }
}
