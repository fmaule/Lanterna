import SwiftUI

struct SettingsView: View {
  @Environment(\.dismiss) private var dismiss
  private let settings = SettingsManager.shared

  @State private var geminiAPIKey: String = ""
  @State private var openClawHost: String = ""
  @State private var openClawPort: String = ""
  @State private var openClawHookToken: String = ""
  @State private var openClawGatewayToken: String = ""
  @State private var hermesBaseURL: String = ""
  @State private var hermesBearerToken: String = ""
  @State private var hermesSessionKey: String = ""
  @State private var geminiSystemPrompt: String = ""
  @State private var geminiVoiceName: String = GeminiConfig.defaultVoiceName
  @State private var webrtcSignalingURL: String = ""
  @State private var speakerOutputEnabled: Bool = false
  @State private var videoStreamingEnabled: Bool = true
  @State private var proactiveNotificationsEnabled: Bool = true
  @State private var showResetConfirmation = false
  @State private var hermesTestInput: String = "say hi in one short sentence"
  @State private var hermesTestOutput: String = ""
  @State private var hermesTestInFlight: Bool = false

  var body: some View {
    NavigationView {
      Form {
        Section(header: Text("Gemini API")) {
          VStack(alignment: .leading, spacing: 4) {
            Text("API Key")
              .font(.caption)
              .foregroundColor(.secondary)
            TextField("Enter Gemini API key", text: $geminiAPIKey)
              .autocapitalization(.none)
              .disableAutocorrection(true)
              .font(.system(.body, design: .monospaced))
          }
        }

        Section(header: Text("Voice"), footer: Text("Which Gemini prebuilt voice to use. Takes effect on the next session.")) {
          Picker("Voice", selection: $geminiVoiceName) {
            ForEach(GeminiConfig.availableVoices, id: \.self) { name in
              Text(name).tag(name)
            }
          }
        }

        Section(header: Text("System Prompt"), footer: Text("Customize the AI assistant's behavior and personality. Changes take effect on the next Gemini session.")) {
          TextEditor(text: $geminiSystemPrompt)
            .font(.system(.body, design: .monospaced))
            .frame(minHeight: 200)
        }

        Section(header: Text("OpenClaw"), footer: Text("Connect to an OpenClaw gateway running on your Mac for agentic tool-calling.")) {
          VStack(alignment: .leading, spacing: 4) {
            Text("Host")
              .font(.caption)
              .foregroundColor(.secondary)
            TextField("http://your-mac.local", text: $openClawHost)
              .autocapitalization(.none)
              .disableAutocorrection(true)
              .keyboardType(.URL)
              .font(.system(.body, design: .monospaced))
          }

          VStack(alignment: .leading, spacing: 4) {
            Text("Port")
              .font(.caption)
              .foregroundColor(.secondary)
            TextField("18789", text: $openClawPort)
              .keyboardType(.numberPad)
              .font(.system(.body, design: .monospaced))
          }

          VStack(alignment: .leading, spacing: 4) {
            Text("Hook Token")
              .font(.caption)
              .foregroundColor(.secondary)
            TextField("Hook token", text: $openClawHookToken)
              .autocapitalization(.none)
              .disableAutocorrection(true)
              .font(.system(.body, design: .monospaced))
          }

          VStack(alignment: .leading, spacing: 4) {
            Text("Gateway Token")
              .font(.caption)
              .foregroundColor(.secondary)
            TextField("Gateway auth token", text: $openClawGatewayToken)
              .autocapitalization(.none)
              .disableAutocorrection(true)
              .font(.system(.body, design: .monospaced))
          }
        }

        Section(header: Text("Hermes"), footer: Text("Alternative HTTP agent backend. Base URL must include scheme and port.")) {
          VStack(alignment: .leading, spacing: 4) {
            Text("Base URL")
              .font(.caption)
              .foregroundColor(.secondary)
            TextField("http://host.example.ts.net:8642", text: $hermesBaseURL)
              .autocapitalization(.none)
              .disableAutocorrection(true)
              .keyboardType(.URL)
              .font(.system(.body, design: .monospaced))
          }

          VStack(alignment: .leading, spacing: 4) {
            Text("Bearer Token")
              .font(.caption)
              .foregroundColor(.secondary)
            TextField("Bearer token", text: $hermesBearerToken)
              .autocapitalization(.none)
              .disableAutocorrection(true)
              .font(.system(.body, design: .monospaced))
          }

          VStack(alignment: .leading, spacing: 4) {
            Text("Session Key")
              .font(.caption)
              .foregroundColor(.secondary)
            TextField("agent:main:glasses:dm:fer", text: $hermesSessionKey)
              .autocapitalization(.none)
              .disableAutocorrection(true)
              .font(.system(.body, design: .monospaced))
          }
        }

        Section(header: Text("Hermes Test"), footer: Text("Fires a run against the currently-saved Hermes config. Save first if you just edited the fields. Full request/response is logged to Xcode with the [Hermes] prefix.")) {
          VStack(alignment: .leading, spacing: 4) {
            Text("Input")
              .font(.caption)
              .foregroundColor(.secondary)
            TextField("say hi", text: $hermesTestInput)
              .autocapitalization(.none)
              .disableAutocorrection(true)
              .font(.system(.body, design: .monospaced))
          }

          Button(action: runHermesTest) {
            HStack {
              if hermesTestInFlight {
                ProgressView()
                Text("Running…")
              } else {
                Image(systemName: "play.circle.fill")
                Text("Send Test Run")
              }
            }
          }
          .disabled(hermesTestInFlight || hermesTestInput.trimmingCharacters(in: .whitespaces).isEmpty)

          if !hermesTestOutput.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
              Text("Result")
                .font(.caption)
                .foregroundColor(.secondary)
              ScrollView {
                Text(hermesTestOutput)
                  .font(.system(.footnote, design: .monospaced))
                  .textSelection(.enabled)
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
              .frame(maxHeight: 200)
            }
          }
        }

        Section(header: Text("WebRTC")) {
          VStack(alignment: .leading, spacing: 4) {
            Text("Signaling URL")
              .font(.caption)
              .foregroundColor(.secondary)
            TextField("wss://your-server.example.com", text: $webrtcSignalingURL)
              .autocapitalization(.none)
              .disableAutocorrection(true)
              .keyboardType(.URL)
              .font(.system(.body, design: .monospaced))
          }
        }

        Section(header: Text("Audio"), footer: Text("Route audio output to the iPhone speaker instead of glasses. Useful for demos where others need to hear.")) {
          Toggle("Speaker Output", isOn: $speakerOutputEnabled)
        }

        Section(header: Text("Video"), footer: Text("Disable video streaming to save battery. Audio remains active for voice-only interaction.")) {
          Toggle("Video Streaming", isOn: $videoStreamingEnabled)
        }

        Section(header: Text("Notifications"), footer: Text("Receive proactive updates from OpenClaw (heartbeat, scheduled tasks) spoken through the glasses.")) {
          Toggle("Proactive Notifications", isOn: $proactiveNotificationsEnabled)
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
          Button("Cancel") {
            dismiss()
          }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
          Button("Save") {
            save()
            dismiss()
          }
          .fontWeight(.semibold)
        }
      }
      .alert("Reset Settings", isPresented: $showResetConfirmation) {
        Button("Reset", role: .destructive) {
          settings.resetAll()
          loadCurrentValues()
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("This will reset all settings to the values built into the app.")
      }
      .onAppear {
        loadCurrentValues()
      }
    }
  }

  private func loadCurrentValues() {
    geminiAPIKey = settings.geminiAPIKey
    geminiSystemPrompt = settings.geminiSystemPrompt
    geminiVoiceName = settings.geminiVoiceName
    openClawHost = settings.openClawHost
    openClawPort = String(settings.openClawPort)
    openClawHookToken = settings.openClawHookToken
    openClawGatewayToken = settings.openClawGatewayToken
    hermesBaseURL = settings.hermesBaseURL
    hermesBearerToken = settings.hermesBearerToken
    hermesSessionKey = settings.hermesSessionKey
    webrtcSignalingURL = settings.webrtcSignalingURL
    speakerOutputEnabled = settings.speakerOutputEnabled
    videoStreamingEnabled = settings.videoStreamingEnabled
    proactiveNotificationsEnabled = settings.proactiveNotificationsEnabled
  }

  private func save() {
    settings.geminiAPIKey = geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
    settings.geminiSystemPrompt = geminiSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    settings.geminiVoiceName = geminiVoiceName
    settings.openClawHost = openClawHost.trimmingCharacters(in: .whitespacesAndNewlines)
    if let port = Int(openClawPort.trimmingCharacters(in: .whitespacesAndNewlines)) {
      settings.openClawPort = port
    }
    settings.openClawHookToken = openClawHookToken.trimmingCharacters(in: .whitespacesAndNewlines)
    settings.openClawGatewayToken = openClawGatewayToken.trimmingCharacters(in: .whitespacesAndNewlines)
    settings.hermesBaseURL = hermesBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    settings.hermesBearerToken = hermesBearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
    settings.hermesSessionKey = hermesSessionKey.trimmingCharacters(in: .whitespacesAndNewlines)
    settings.webrtcSignalingURL = webrtcSignalingURL.trimmingCharacters(in: .whitespacesAndNewlines)
    settings.speakerOutputEnabled = speakerOutputEnabled
    settings.videoStreamingEnabled = videoStreamingEnabled
    settings.proactiveNotificationsEnabled = proactiveNotificationsEnabled
  }

  private func runHermesTest() {
    let input = hermesTestInput.trimmingCharacters(in: .whitespaces)
    guard !input.isEmpty else { return }
    hermesTestInFlight = true
    hermesTestOutput = ""
    Task { @MainActor in
      let bridge = HermesBridge()
      await bridge.checkConnection()
      let result = await bridge.delegateTask(task: input, toolName: "settings.test")
      switch result {
      case .success(let text):
        hermesTestOutput = "✅ \(text)"
      case .failure(let err):
        hermesTestOutput = "❌ \(err)"
      }
      hermesTestInFlight = false
    }
  }
}
