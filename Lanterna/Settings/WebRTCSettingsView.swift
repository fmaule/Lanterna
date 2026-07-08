import SwiftUI

struct WebRTCSettingsView: View {
  @Environment(\.dismiss) private var dismiss
  private let settings = SettingsManager.shared

  @State private var signalingURL: String = ""

  var body: some View {
    Form {
      Section(header: Text("Signaling")) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Signaling URL")
            .font(.caption)
            .foregroundColor(.secondary)
          TextField("wss://your-server.example.com", text: $signalingURL)
            .autocapitalization(.none)
            .disableAutocorrection(true)
            .keyboardType(.URL)
            .font(.system(.body, design: .monospaced))
        }
      }
    }
    .navigationTitle("WebRTC")
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
    signalingURL = settings.webrtcSignalingURL
  }

  private func save() {
    settings.webrtcSignalingURL = signalingURL.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
