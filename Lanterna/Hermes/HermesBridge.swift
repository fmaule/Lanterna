import Foundation

enum HermesConnectionState: Equatable {
  case notConfigured
  case checking
  case connected
  case unreachable(String)
}

private enum HermesLog {
  static func line(_ s: String = "") { NSLog("[Hermes] %@", s) }

  static func banner(_ title: String) {
    NSLog("[Hermes] ═══════════════ %@ ═══════════════", title)
  }

  static func redactBearer(_ token: String) -> String {
    guard token.count > 8 else { return "***" }
    let head = token.prefix(4)
    let tail = token.suffix(4)
    return "\(head)…\(tail) (len=\(token.count))"
  }

  static func dumpRequest(_ request: URLRequest, body: Data?) {
    line("→ \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "?")")
    if let headers = request.allHTTPHeaderFields {
      for (k, v) in headers.sorted(by: { $0.key < $1.key }) {
        let redacted: String
        if k.caseInsensitiveCompare("Authorization") == .orderedSame {
          let stripped = v.replacingOccurrences(of: "Bearer ", with: "")
          redacted = "Bearer \(redactBearer(stripped))"
        } else {
          redacted = v
        }
        line("  \(k): \(redacted)")
      }
    }
    if let body, let s = String(data: body, encoding: .utf8) {
      line("  body: \(s)")
    }
  }

  static func dumpResponse(_ response: URLResponse?) {
    guard let http = response as? HTTPURLResponse else {
      line("← (no HTTP response)")
      return
    }
    line("← HTTP \(http.statusCode) \(http.url?.absoluteString ?? "?")")
    for (k, v) in http.allHeaderFields {
      line("  \(k): \(v)")
    }
  }
}

@MainActor
class HermesBridge: ObservableObject {
  @Published var lastToolCallStatus: ToolCallStatus = .idle
  @Published var connectionState: HermesConnectionState = .notConfigured

  private let session: URLSession
  private let pingSession: URLSession

  init() {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 300
    config.timeoutIntervalForResource = 600
    self.session = URLSession(configuration: config)

    let pingConfig = URLSessionConfiguration.default
    pingConfig.timeoutIntervalForRequest = 5
    self.pingSession = URLSession(configuration: pingConfig)
  }

  func checkConnection() async {
    guard GeminiConfig.isHermesConfigured else {
      HermesLog.line("checkConnection: not configured (baseURL or bearer empty)")
      connectionState = .notConfigured
      return
    }
    connectionState = .checking
    HermesLog.banner("CHECK CONNECTION")
    HermesLog.line("baseURL=\(GeminiConfig.hermesBaseURL) sessionKey=\(GeminiConfig.hermesSessionKey)")

    guard let url = URL(string: "\(GeminiConfig.hermesBaseURL)/v1/runs") else {
      HermesLog.line("checkConnection: invalid URL")
      connectionState = .unreachable("Invalid base URL")
      return
    }

    var request = URLRequest(url: url)
    request.httpMethod = "OPTIONS"
    request.setValue("Bearer \(GeminiConfig.hermesBearerToken)", forHTTPHeaderField: "Authorization")
    request.setValue(GeminiConfig.hermesSessionKey, forHTTPHeaderField: "X-Hermes-Session-Key")
    HermesLog.dumpRequest(request, body: nil)

    do {
      let (data, response) = try await pingSession.data(for: request)
      HermesLog.dumpResponse(response)
      if let body = String(data: data, encoding: .utf8), !body.isEmpty {
        HermesLog.line("  body: \(String(body.prefix(400)))")
      }
      if let http = response as? HTTPURLResponse, (200...499).contains(http.statusCode) {
        connectionState = .connected
        HermesLog.line("checkConnection: OK")
      } else {
        connectionState = .unreachable("Unexpected response")
      }
    } catch {
      connectionState = .unreachable(error.localizedDescription)
      HermesLog.line("checkConnection: FAILED \(error.localizedDescription)")
    }
  }

  func resetSession() {
    HermesLog.line("resetSession (server-side key retained: \(GeminiConfig.hermesSessionKey))")
  }

  // MARK: - Agent Run (start + SSE subscribe)

  func delegateTask(
    task: String,
    toolName: String = "execute"
  ) async -> ToolResult {
    lastToolCallStatus = .executing(toolName)
    HermesLog.banner("RUN START tool=\(toolName)")

    // Step 1: POST /v1/runs to kick off the run and get a run_id
    guard let startURL = URL(string: "\(GeminiConfig.hermesBaseURL)/v1/runs") else {
      HermesLog.line("delegateTask: invalid start URL")
      lastToolCallStatus = .failed(toolName, "Invalid URL")
      return .failure("Invalid Hermes URL")
    }

    var startRequest = URLRequest(url: startURL)
    startRequest.httpMethod = "POST"
    startRequest.setValue("Bearer \(GeminiConfig.hermesBearerToken)", forHTTPHeaderField: "Authorization")
    startRequest.setValue(GeminiConfig.hermesSessionKey, forHTTPHeaderField: "X-Hermes-Session-Key")
    startRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    startRequest.setValue("application/json", forHTTPHeaderField: "Accept")

    let body: [String: Any] = ["input": task]
    let bodyData: Data
    do {
      bodyData = try JSONSerialization.data(withJSONObject: body)
      startRequest.httpBody = bodyData
    } catch {
      HermesLog.line("delegateTask: body encode failed \(error.localizedDescription)")
      lastToolCallStatus = .failed(toolName, "Body encode failed")
      return .failure("Body encode failed: \(error.localizedDescription)")
    }

    HermesLog.dumpRequest(startRequest, body: bodyData)
    let startedAt = Date()

    let runId: String
    do {
      let (startData, startResponse) = try await session.data(for: startRequest)
      HermesLog.dumpResponse(startResponse)
      if let s = String(data: startData, encoding: .utf8), !s.isEmpty {
        HermesLog.line("  body: \(String(s.prefix(400)))")
      }
      guard let http = startResponse as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
        let code = (startResponse as? HTTPURLResponse)?.statusCode ?? 0
        HermesLog.line("run start failed HTTP \(code)")
        lastToolCallStatus = .failed(toolName, "HTTP \(code)")
        return .failure("Hermes /v1/runs returned HTTP \(code)")
      }
      guard let json = try? JSONSerialization.jsonObject(with: startData) as? [String: Any],
            let id = json["run_id"] as? String else {
        HermesLog.line("run start response missing run_id")
        lastToolCallStatus = .failed(toolName, "Missing run_id")
        return .failure("Hermes did not return a run_id")
      }
      runId = id
      let status = (json["status"] as? String) ?? "?"
      HermesLog.line("run started run_id=\(runId) status=\(status)")
    } catch {
      HermesLog.line("run start threw: \(error.localizedDescription)")
      lastToolCallStatus = .failed(toolName, error.localizedDescription)
      return .failure("Hermes start error: \(error.localizedDescription)")
    }

    // Step 2: GET /v1/runs/{run_id}/events to subscribe to the SSE stream
    guard let streamURL = URL(string: "\(GeminiConfig.hermesBaseURL)/v1/runs/\(runId)/events") else {
      HermesLog.line("delegateTask: invalid stream URL")
      lastToolCallStatus = .failed(toolName, "Invalid stream URL")
      return .failure("Invalid Hermes stream URL")
    }

    var streamRequest = URLRequest(url: streamURL)
    streamRequest.httpMethod = "GET"
    streamRequest.setValue("Bearer \(GeminiConfig.hermesBearerToken)", forHTTPHeaderField: "Authorization")
    streamRequest.setValue(GeminiConfig.hermesSessionKey, forHTTPHeaderField: "X-Hermes-Session-Key")
    streamRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")

    HermesLog.dumpRequest(streamRequest, body: nil)

    do {
      let (bytes, response) = try await session.bytes(for: streamRequest)
      HermesLog.dumpResponse(response)
      guard let http = response as? HTTPURLResponse else {
        lastToolCallStatus = .failed(toolName, "No HTTP response")
        return .failure("No HTTP response")
      }
      guard (200...299).contains(http.statusCode) else {
        var preview = ""
        for try await line in bytes.lines {
          preview += line + "\n"
          if preview.count > 400 { break }
        }
        HermesLog.line("stream subscribe failed HTTP \(http.statusCode) body: \(preview)")
        lastToolCallStatus = .failed(toolName, "HTTP \(http.statusCode)")
        return .failure("Hermes stream returned HTTP \(http.statusCode)")
      }

      HermesLog.line("SSE stream open, reading events…")

      var currentDelta = ""
      var frameCount = 0
      var deltaTokenCount = 0

      for try await line in bytes.lines {
        guard !Task.isCancelled else {
          HermesLog.line("task cancelled mid-stream")
          lastToolCallStatus = .cancelled(toolName)
          return .failure("Cancelled")
        }

        // Raw wire log (truncated so long deltas don't drown Xcode)
        if line.isEmpty {
          continue
        }
        HermesLog.line("‹ \(String(line.prefix(500)))")

        // SSE keepalive comment
        if line.hasPrefix(":") { continue }
        guard line.hasPrefix("data:") else { continue }

        let jsonPart = line
          .dropFirst("data:".count)
          .trimmingCharacters(in: .whitespaces)
        guard !jsonPart.isEmpty,
              let data = jsonPart.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
          HermesLog.line("  (unparseable data frame, skipping)")
          continue
        }

        frameCount += 1
        let event = (payload["event"] as? String) ?? "unknown"

        switch event {
        case "message.delta":
          if let delta = payload["delta"] as? String {
            currentDelta += delta
            deltaTokenCount += 1
            HermesLog.line("  ▸ message.delta[\(deltaTokenCount)] +\(delta.count)ch total=\(currentDelta.count)ch")
          }

        case "tool.started":
          let tool = (payload["tool"] as? String) ?? toolName
          let preview = (payload["preview"] as? String) ?? ""
          HermesLog.line("  ▸ tool.started \(tool) preview=\(String(preview.prefix(200)))")
          lastToolCallStatus = .executing(tool)

        case "tool.completed":
          let tool = (payload["tool"] as? String) ?? toolName
          let duration = (payload["duration"] as? Double) ?? 0
          let err = payload["error"] as? String
          if let err, !err.isEmpty {
            HermesLog.line("  ▸ tool.completed \(tool) FAILED (\(String(format: "%.2f", duration))s): \(err)")
          } else {
            HermesLog.line("  ▸ tool.completed \(tool) (\(String(format: "%.2f", duration))s)")
          }
          lastToolCallStatus = .executing(toolName)

        case "reasoning.available":
          if let text = payload["text"] as? String {
            HermesLog.line("  ▸ reasoning: \(String(text.prefix(200)))")
          }

        case "approval.request":
          let command = (payload["command"] as? String) ?? "(no command)"
          let choices = (payload["choices"] as? [String]) ?? []
          HermesLog.line("  ▸ approval.request run=\(runId) command=\(String(command.prefix(200))) choices=\(choices)")
          HermesLog.line("  ▸ auto-responding `once`")
          await respondToApproval(runId: runId, choice: "once")

        case "approval.responded":
          HermesLog.line("  ▸ approval.responded")

        case "run.completed":
          let output = (payload["output"] as? String) ?? currentDelta
          let usage = payload["usage"] as? [String: Any]
          let elapsed = Date().timeIntervalSince(startedAt)
          HermesLog.line("  ▸ run.completed run=\(runId) elapsed=\(String(format: "%.2f", elapsed))s frames=\(frameCount) output=\(output.count)ch")
          if let usage { HermesLog.line("  ▸ usage: \(usage)") }
          HermesLog.line("  ▸ output preview: \(String(output.prefix(400)))")
          HermesLog.banner("RUN END success")
          lastToolCallStatus = .completed(toolName)
          return .success(output)

        case "run.failed":
          let err = (payload["error"] as? String) ?? "Unknown error"
          HermesLog.line("  ▸ run.failed run=\(runId) error=\(err)")
          HermesLog.banner("RUN END failure")
          lastToolCallStatus = .failed(toolName, err)
          return .failure(err)

        case "run.cancelled":
          HermesLog.line("  ▸ run.cancelled run=\(runId)")
          HermesLog.banner("RUN END cancelled")
          lastToolCallStatus = .cancelled(toolName)
          return .failure("Run cancelled")

        default:
          HermesLog.line("  ▸ unknown event: \(event) payload=\(payload)")
        }
      }

      let elapsed = Date().timeIntervalSince(startedAt)
      HermesLog.line("stream closed without terminal event after \(String(format: "%.2f", elapsed))s, frames=\(frameCount), accumulated=\(currentDelta.count)ch")
      if !currentDelta.isEmpty {
        HermesLog.banner("RUN END partial")
        lastToolCallStatus = .completed(toolName)
        return .success(currentDelta)
      }
      HermesLog.banner("RUN END empty")
      lastToolCallStatus = .failed(toolName, "Stream ended without result")
      return .failure("Stream ended without result")

    } catch {
      HermesLog.line("stream threw: \(error.localizedDescription)")
      HermesLog.banner("RUN END error")
      lastToolCallStatus = .failed(toolName, error.localizedDescription)
      return .failure("Hermes error: \(error.localizedDescription)")
    }
  }

  // MARK: - Approvals

  private func respondToApproval(runId: String, choice: String) async {
    guard !runId.isEmpty,
          let url = URL(string: "\(GeminiConfig.hermesBaseURL)/v1/runs/\(runId)/approval") else {
      HermesLog.line("approval POST skipped: invalid runId or URL (runId=\(runId))")
      return
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(GeminiConfig.hermesBearerToken)", forHTTPHeaderField: "Authorization")
    request.setValue(GeminiConfig.hermesSessionKey, forHTTPHeaderField: "X-Hermes-Session-Key")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let bodyData = try? JSONSerialization.data(withJSONObject: ["choice": choice])
    request.httpBody = bodyData

    HermesLog.banner("APPROVAL run=\(runId) choice=\(choice)")
    HermesLog.dumpRequest(request, body: bodyData)

    do {
      let (data, response) = try await pingSession.data(for: request)
      HermesLog.dumpResponse(response)
      if let s = String(data: data, encoding: .utf8), !s.isEmpty {
        HermesLog.line("  body: \(String(s.prefix(400)))")
      }
    } catch {
      HermesLog.line("approval POST failed: \(error.localizedDescription)")
    }
  }
}
