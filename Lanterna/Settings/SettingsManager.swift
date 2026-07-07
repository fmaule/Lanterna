import Foundation

final class SettingsManager {
  static let shared = SettingsManager()

  private let defaults = UserDefaults.standard

  // Keys for secrets (stored in Keychain)
  private enum SecretKey: String {
    case geminiAPIKey
    case openClawHookToken
    case openClawGatewayToken
    case hermesBearerToken
  }

  // Keys for non-sensitive settings (stored in UserDefaults)
  private enum Key: String {
    case openClawHost
    case openClawPort
    case geminiSystemPrompt
    case geminiVoiceName
    case webrtcSignalingURL
    case speakerOutputEnabled
    case videoStreamingEnabled
    case proactiveNotificationsEnabled
    case hermesBaseURL
    case hermesSessionKey
  }

  private init() {}

  // MARK: - Gemini (secrets in Keychain)

  var geminiAPIKey: String {
    get { KeychainManager.get(SecretKey.geminiAPIKey.rawValue) ?? Secrets.geminiAPIKey }
    set { KeychainManager.set(SecretKey.geminiAPIKey.rawValue, value: newValue) }
  }

  var geminiSystemPrompt: String {
    get { defaults.string(forKey: Key.geminiSystemPrompt.rawValue) ?? GeminiConfig.defaultSystemInstruction }
    set { defaults.set(newValue, forKey: Key.geminiSystemPrompt.rawValue) }
  }

  var geminiVoiceName: String {
    get { defaults.string(forKey: Key.geminiVoiceName.rawValue) ?? GeminiConfig.defaultVoiceName }
    set { defaults.set(newValue, forKey: Key.geminiVoiceName.rawValue) }
  }

  // MARK: - OpenClaw

  var openClawHost: String {
    get { defaults.string(forKey: Key.openClawHost.rawValue) ?? Secrets.openClawHost }
    set { defaults.set(newValue, forKey: Key.openClawHost.rawValue) }
  }

  var openClawPort: Int {
    get {
      let stored = defaults.integer(forKey: Key.openClawPort.rawValue)
      return stored != 0 ? stored : Secrets.openClawPort
    }
    set { defaults.set(newValue, forKey: Key.openClawPort.rawValue) }
  }

  var openClawHookToken: String {
    get { KeychainManager.get(SecretKey.openClawHookToken.rawValue) ?? Secrets.openClawHookToken }
    set { KeychainManager.set(SecretKey.openClawHookToken.rawValue, value: newValue) }
  }

  var openClawGatewayToken: String {
    get { KeychainManager.get(SecretKey.openClawGatewayToken.rawValue) ?? Secrets.openClawGatewayToken }
    set { KeychainManager.set(SecretKey.openClawGatewayToken.rawValue, value: newValue) }
  }

  // MARK: - Hermes

  var hermesBaseURL: String {
    get { defaults.string(forKey: Key.hermesBaseURL.rawValue) ?? "" }
    set { defaults.set(newValue, forKey: Key.hermesBaseURL.rawValue) }
  }

  var hermesBearerToken: String {
    get { KeychainManager.get(SecretKey.hermesBearerToken.rawValue) ?? "" }
    set { KeychainManager.set(SecretKey.hermesBearerToken.rawValue, value: newValue) }
  }

  var hermesSessionKey: String {
    get { defaults.string(forKey: Key.hermesSessionKey.rawValue) ?? "" }
    set { defaults.set(newValue, forKey: Key.hermesSessionKey.rawValue) }
  }

  // MARK: - WebRTC

  var webrtcSignalingURL: String {
    get { defaults.string(forKey: Key.webrtcSignalingURL.rawValue) ?? Secrets.webrtcSignalingURL }
    set { defaults.set(newValue, forKey: Key.webrtcSignalingURL.rawValue) }
  }

  // MARK: - Audio

  var speakerOutputEnabled: Bool {
    get { defaults.bool(forKey: Key.speakerOutputEnabled.rawValue) }
    set { defaults.set(newValue, forKey: Key.speakerOutputEnabled.rawValue) }
  }

  // MARK: - Video

  var videoStreamingEnabled: Bool {
    get { defaults.object(forKey: Key.videoStreamingEnabled.rawValue) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Key.videoStreamingEnabled.rawValue) }
  }

  // MARK: - Notifications

  var proactiveNotificationsEnabled: Bool {
    get { defaults.object(forKey: Key.proactiveNotificationsEnabled.rawValue) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Key.proactiveNotificationsEnabled.rawValue) }
  }

  // MARK: - Reset

  func resetAll() {
    KeychainManager.deleteAll()
    for key in [Key.geminiSystemPrompt, .geminiVoiceName, .openClawHost, .openClawPort,
                .webrtcSignalingURL, .speakerOutputEnabled, .videoStreamingEnabled,
                .proactiveNotificationsEnabled, .hermesBaseURL, .hermesSessionKey] {
      defaults.removeObject(forKey: key.rawValue)
    }
  }
}
