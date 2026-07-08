import SwiftUI

struct HermesSettingsView: View {
  @Environment(\.dismiss) private var dismiss
  private let settings = SettingsManager.shared

  @State private var baseURL: String = ""
  @State private var bearerToken: String = ""
  @State private var sessionKey: String = ""

  @State private var testInput: String = "say hi in one short sentence"
  @State private var testOutput: String = ""
  @State private var testInFlight: Bool = false

  var body: some View {
    Form {
      Section(header: Text("Connection"), footer: Text("Alternative HTTP agent backend. Base URL must include scheme and port.")) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Base URL")
            .font(.caption)
            .foregroundColor(.secondary)
          TextField("http://host.example.ts.net:8642", text: $baseURL)
            .autocapitalization(.none)
            .disableAutocorrection(true)
            .keyboardType(.URL)
            .font(.system(.body, design: .monospaced))
        }

        VStack(alignment: .leading, spacing: 4) {
          Text("Bearer Token")
            .font(.caption)
            .foregroundColor(.secondary)
          TextField("Bearer token", text: $bearerToken)
            .autocapitalization(.none)
            .disableAutocorrection(true)
            .font(.system(.body, design: .monospaced))
        }

        VStack(alignment: .leading, spacing: 4) {
          Text("Session Key")
            .font(.caption)
            .foregroundColor(.secondary)
          TextField("agent:main:glasses:dm:fer", text: $sessionKey)
            .autocapitalization(.none)
            .disableAutocorrection(true)
            .font(.system(.body, design: .monospaced))
        }
      }

      Section(header: Text("Test"), footer: Text("Fires a run against the currently-saved Hermes config. Save first if you just edited the fields. Full request/response is logged to Xcode with the [Hermes] prefix.")) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Input")
            .font(.caption)
            .foregroundColor(.secondary)
          TextField("say hi", text: $testInput)
            .autocapitalization(.none)
            .disableAutocorrection(true)
            .font(.system(.body, design: .monospaced))
        }

        Button(action: runTest) {
          HStack {
            if testInFlight {
              ProgressView()
              Text("Running…")
            } else {
              Image(systemName: "play.circle.fill")
              Text("Send Test Run")
            }
          }
        }
        .disabled(testInFlight || testInput.trimmingCharacters(in: .whitespaces).isEmpty)

        if !testOutput.isEmpty {
          VStack(alignment: .leading, spacing: 4) {
            Text("Result")
              .font(.caption)
              .foregroundColor(.secondary)
            ScrollView {
              Text(testOutput)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 200)
          }
        }
      }
    }
    .navigationTitle("Hermes")
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
    baseURL = settings.hermesBaseURL
    bearerToken = settings.hermesBearerToken
    sessionKey = settings.hermesSessionKey
  }

  private func save() {
    settings.hermesBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    settings.hermesBearerToken = bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
    settings.hermesSessionKey = sessionKey.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func runTest() {
    let input = testInput.trimmingCharacters(in: .whitespaces)
    guard !input.isEmpty else { return }
    testInFlight = true
    testOutput = ""
    Task { @MainActor in
      let bridge = HermesBridge()
      await bridge.checkConnection()
      let result = await bridge.delegateTask(task: input, toolName: "settings.test")
      switch result {
      case .success(let text):
        testOutput = "✅ \(text)"
      case .failure(let err):
        testOutput = "❌ \(err)"
      }
      testInFlight = false
    }
  }
}
