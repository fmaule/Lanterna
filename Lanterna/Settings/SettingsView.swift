import SwiftUI

/// Root Settings menu. Each backend / connection group drills into its own
/// sub-page under `Lanterna/Settings/`. Simple single-toggle settings
/// (notifications) and destructive actions (reset) stay inline here — matches
/// OpenVision's pattern where only multi-field configs get a dedicated page.
struct SettingsView: View {
  @Environment(\.dismiss) private var dismiss
  private let settings = SettingsManager.shared

  @State private var proactiveNotificationsEnabled: Bool = true
  @State private var showResetConfirmation = false
  @State private var knownFacesCount: Int = 0

  // Cached status values so the trailing indicators refresh when we come back
  // from a sub-page (each sub-page saves onto SettingsManager directly).
  @State private var geminiConfigured: Bool = false
  @State private var openClawConfigured: Bool = false
  @State private var hermesConfigured: Bool = false
  @State private var webrtcConfigured: Bool = false

  var body: some View {
    NavigationStack {
      Form {
        Section(header: Text("AI")) {
          NavigationLink {
            GeminiAPIKeySettingsView()
          } label: {
            settingsRow(
              title: "API Key",
              systemImage: "key.fill",
              trailingText: nil,
              warning: !geminiConfigured
            )
          }

          NavigationLink {
            GeminiVoiceSettingsView()
          } label: {
            settingsRow(
              title: "Voice",
              systemImage: "waveform",
              trailingText: settings.geminiVoiceName,
              warning: false
            )
          }

          NavigationLink {
            GeminiPromptSettingsView()
          } label: {
            settingsRow(
              title: "Prompt",
              systemImage: "text.quote",
              trailingText: nil,
              warning: false
            )
          }
        }

        Section(header: Text("Agents")) {
          NavigationLink {
            OpenClawSettingsView()
          } label: {
            settingsRow(
              title: "OpenClaw",
              systemImage: "hammer",
              trailingText: openClawConfigured ? "Configured" : nil,
              warning: !openClawConfigured
            )
          }

          NavigationLink {
            HermesSettingsView()
          } label: {
            settingsRow(
              title: "Hermes",
              systemImage: "network",
              trailingText: hermesConfigured ? "Configured" : nil,
              warning: !hermesConfigured
            )
          }
        }

        Section(header: Text("Streaming")) {
          NavigationLink {
            WebRTCSettingsView()
          } label: {
            settingsRow(
              title: "WebRTC",
              systemImage: "antenna.radiowaves.left.and.right",
              trailingText: webrtcConfigured ? "Configured" : nil,
              warning: !webrtcConfigured
            )
          }

          NavigationLink {
            AudioVideoSettingsView()
          } label: {
            settingsRow(
              title: "Audio & Video",
              systemImage: "speaker.wave.2",
              trailingText: nil,
              warning: false
            )
          }
        }

        if #available(iOS 18.0, *) {
          Section(header: Text("Face Recognition")) {
            NavigationLink {
              FaceRecognitionSettingsView()
            } label: {
              settingsRow(
                title: "Known Faces",
                systemImage: "person.crop.circle.badge.checkmark",
                trailingText: knownFacesCount > 0 ? "\(knownFacesCount)" : nil,
                warning: false
              )
            }
          }
        }

        Section(header: Text("Notifications"), footer: Text("Receive proactive updates from OpenClaw (heartbeat, scheduled tasks) spoken through the glasses.")) {
          Toggle("Proactive Notifications", isOn: $proactiveNotificationsEnabled)
            .onChange(of: proactiveNotificationsEnabled) { _, newValue in
              settings.proactiveNotificationsEnabled = newValue
            }
        }

        Section {
          Button("Reset to Defaults") {
            showResetConfirmation = true
          }
          .foregroundColor(.red)
        }
      }
      .navigationTitle("Settings")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarLeading) {
          Button("Done") {
            dismiss()
          }
        }
      }
      .alert("Reset Settings", isPresented: $showResetConfirmation) {
        Button("Reset", role: .destructive) {
          settings.resetAll()
          load()
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("This will reset all settings to the values built into the app.")
      }
      .onAppear(perform: load)
    }
  }

  @ViewBuilder
  private func settingsRow(
    title: String,
    systemImage: String,
    trailingText: String?,
    warning: Bool
  ) -> some View {
    HStack {
      Label(title, systemImage: systemImage)
      Spacer()
      if let trailingText, !trailingText.isEmpty {
        Text(trailingText)
          .font(.caption)
          .foregroundColor(.secondary)
      }
      if warning {
        Image(systemName: "exclamationmark.circle.fill")
          .foregroundColor(.orange)
      }
    }
  }

  private func load() {
    proactiveNotificationsEnabled = settings.proactiveNotificationsEnabled
    geminiConfigured = GeminiConfig.isConfigured
    openClawConfigured = GeminiConfig.isOpenClawConfigured
    hermesConfigured = GeminiConfig.isHermesConfigured
    webrtcConfigured = !settings.webrtcSignalingURL.isEmpty
    if #available(iOS 18.0, *) {
      knownFacesCount = FaceRecognitionStore.allNames().count
    }
  }
}
