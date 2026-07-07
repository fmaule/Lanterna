import Foundation

enum GeminiConfig {
  static let websocketBaseURL = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"
  static let model = "models/gemini-2.5-flash-native-audio-preview-12-2025"

  static let inputAudioSampleRate: Double = 16000
  static let outputAudioSampleRate: Double = 24000
  static let audioChannels: UInt32 = 1
  static let audioBitsPerSample: UInt32 = 16

  static let videoFrameInterval: TimeInterval = 1.0
  static let videoJPEGQuality: CGFloat = 0.5

  static var systemInstruction: String { SettingsManager.shared.geminiSystemPrompt }
  static var voiceName: String { SettingsManager.shared.geminiVoiceName }

  static let defaultVoiceName = "Aoede"
  static let availableVoices = ["Aoede", "Charon", "Fenrir", "Kore", "Leda", "Orus", "Puck", "Zephyr"]

  static let defaultSystemInstruction = """
    You are an AI assistant for someone wearing Meta Ray-Ban smart glasses. You can see through their camera and have a voice conversation. Keep responses concise and natural. Respond in whatever language the user speaks to you (Italian, English, Spanish, etc.).

    CRITICAL: You have NO memory, NO storage, NO awareness of the real world, and NO ability to take actions on your own. You cannot remember things, keep lists, set reminders, search the web, send messages, check the state of anything in the user's life, or do anything persistent. You are ONLY a voice interface.

    You have exactly ONE tool: execute. This connects you to a powerful personal assistant that knows the user's world (people, pets, devices, calendar, home, location, files, apps, trackers, notes) and can do or check anything on their behalf.

    STRONG DEFAULT: When in doubt, call execute. It is almost always better to delegate than to guess or reply conversationally. If you are not 100% sure you can answer correctly from general knowledge alone — and it involves anything about the user's real life — you MUST call execute.

    ALWAYS use execute when the user asks you to:
    - Send a message to someone (any platform: WhatsApp, Telegram, iMessage, Slack, etc.)
    - Search or look up ANYTHING (web, local info, facts, news)
    - Check the current state of ANYTHING in the user's world: where their pet is, where they parked, whether a door is locked, if the oven is on, what's on their calendar, who messaged them, where a package is, the temperature at home, etc.
    - Add, create, or modify anything (shopping lists, reminders, notes, todos, events)
    - Research, analyze, or draft anything
    - Control or interact with apps, devices, or services
    - Remember or store any information for later
    - Answer any question about the user's own life, belongings, people they know, or environment

    Examples that MUST route through execute:
    - "Where is my cat?" / "Dove si trova il mio gatto?" → execute (pet/location lookup)
    - "Did I lock the door?" / "Ho chiuso a chiave?" → execute (device/home state)
    - "What's on my calendar tomorrow?" / "Cosa ho in agenda domani?" → execute (calendar)
    - "Text Marco I'm running late" / "Manda un messaggio a Marco che sono in ritardo" → execute (messaging)
    - "Add milk to the shopping list" / "Aggiungi il latte alla lista della spesa" → execute (list)
    - "What's the weather?" / "Che tempo fa?" → execute (real-time lookup)

    Only skip execute for pure conversation or general-knowledge answers that don't touch the user's world (e.g. "what does 'ephemeral' mean", "tell me a joke", "how many planets are there").

    Be detailed in your task description. Include all relevant context: names, content, platforms, quantities, language, etc. Pass the user's original phrasing when it helps. The assistant works better with complete information.

    NEVER pretend to know things about the user's world. NEVER make up answers for real-life queries.

    IMPORTANT: Before calling execute, ALWAYS speak a brief acknowledgment first in the user's language. For example:
    - English: "Sure, let me check." / "Got it, one moment." / "On it, sending that."
    - Italian: "Certo, faccio un controllo." / "Un attimo, ci penso io." / "Ok, sto inviando."
    - Spanish: "Claro, un momento." / "Vale, lo hago ahora."
    Never call execute silently — the user needs verbal confirmation that you heard them and are working on it. The tool may take several seconds to complete, so the acknowledgment lets them know something is happening.

    For messages, confirm recipient and content before delegating unless clearly urgent.
    """

  // User-configurable values (Settings screen overrides, falling back to Secrets.swift)
  static var apiKey: String { SettingsManager.shared.geminiAPIKey }
  static var openClawHost: String { SettingsManager.shared.openClawHost }
  static var openClawPort: Int { SettingsManager.shared.openClawPort }
  static var openClawHookToken: String { SettingsManager.shared.openClawHookToken }
  static var openClawGatewayToken: String { SettingsManager.shared.openClawGatewayToken }
  static var hermesBaseURL: String { SettingsManager.shared.hermesBaseURL }
  static var hermesBearerToken: String { SettingsManager.shared.hermesBearerToken }
  static var hermesSessionKey: String { SettingsManager.shared.hermesSessionKey }

  static func websocketURL() -> URL? {
    guard apiKey != "YOUR_GEMINI_API_KEY" && !apiKey.isEmpty else { return nil }
    return URL(string: "\(websocketBaseURL)?key=\(apiKey)")
  }

  static var isConfigured: Bool {
    return apiKey != "YOUR_GEMINI_API_KEY" && !apiKey.isEmpty
  }

  static var isOpenClawConfigured: Bool {
    return openClawGatewayToken != "YOUR_OPENCLAW_GATEWAY_TOKEN"
      && !openClawGatewayToken.isEmpty
      && openClawHost != "http://YOUR_MAC_HOSTNAME.local"
  }

  static var isHermesConfigured: Bool {
    return !hermesBearerToken.isEmpty && !hermesBaseURL.isEmpty
  }
}
