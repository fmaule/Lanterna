import SwiftUI

struct OpenClawSettingsView: View {
  @Environment(\.dismiss) private var dismiss
  private let settings = SettingsManager.shared

  @State private var host: String = ""
  @State private var port: String = ""
  @State private var hookToken: String = ""
  @State private var gatewayToken: String = ""

  var body: some View {
    Form {
      Section(footer: Text("Connect to an OpenClaw gateway running on your Mac for agentic tool-calling.")) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Host")
            .font(.caption)
            .foregroundColor(.secondary)
          TextField("http://your-mac.local", text: $host)
            .autocapitalization(.none)
            .disableAutocorrection(true)
            .keyboardType(.URL)
            .font(.system(.body, design: .monospaced))
        }

        VStack(alignment: .leading, spacing: 4) {
          Text("Port")
            .font(.caption)
            .foregroundColor(.secondary)
          TextField("18789", text: $port)
            .keyboardType(.numberPad)
            .font(.system(.body, design: .monospaced))
        }

        VStack(alignment: .leading, spacing: 4) {
          Text("Hook Token")
            .font(.caption)
            .foregroundColor(.secondary)
          TextField("Hook token", text: $hookToken)
            .autocapitalization(.none)
            .disableAutocorrection(true)
            .font(.system(.body, design: .monospaced))
        }

        VStack(alignment: .leading, spacing: 4) {
          Text("Gateway Token")
            .font(.caption)
            .foregroundColor(.secondary)
          TextField("Gateway auth token", text: $gatewayToken)
            .autocapitalization(.none)
            .disableAutocorrection(true)
            .font(.system(.body, design: .monospaced))
        }
      }
    }
    .navigationTitle("OpenClaw")
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
    host = settings.openClawHost
    port = String(settings.openClawPort)
    hookToken = settings.openClawHookToken
    gatewayToken = settings.openClawGatewayToken
  }

  private func save() {
    settings.openClawHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
    if let p = Int(port.trimmingCharacters(in: .whitespacesAndNewlines)) {
      settings.openClawPort = p
    }
    settings.openClawHookToken = hookToken.trimmingCharacters(in: .whitespacesAndNewlines)
    settings.openClawGatewayToken = gatewayToken.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
