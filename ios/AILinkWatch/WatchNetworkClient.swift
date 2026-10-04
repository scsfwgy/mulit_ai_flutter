import Foundation

@MainActor
final class WatchNetworkClient: NSObject, URLSessionTaskDelegate {
  private var session: URLSession!

  init(configuration: URLSessionConfiguration = .ephemeral) {
    super.init()
    configuration.timeoutIntervalForRequest = 65
    configuration.timeoutIntervalForResource = 240
    configuration.waitsForConnectivity = false
    configuration.allowsCellularAccess = true
    configuration.httpCookieStorage = nil
    configuration.urlCredentialStorage = nil
    configuration.urlCache = nil
    session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
  }

  func close() { session.invalidateAndCancel() }

  // Credentials must never follow redirects, including same-host redirects.
  nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
                  willPerformHTTPRedirection response: HTTPURLResponse,
                  newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
    completionHandler(nil)
  }

  private func request(base: String, path: String, key: String, body: Data,
                       contentType: String = "application/json", protocolName: String = "openAi",
                       headers: [String: String] = [:]) throws -> URLRequest {
    guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          !key.contains(where: { $0.isNewline }),
          headers.values.allSatisfy({ !$0.contains(where: { $0.isNewline }) }) else {
      throw WatchRequestError("服务密钥无效，请在手机重新配置", "Invalid API key; update settings on iPhone")
    }
    var request = URLRequest(url: try WatchNetworkConfiguration.endpoint(base, path))
    request.httpMethod = "POST"
    request.httpBody = body
    request.setValue(contentType, forHTTPHeaderField: "Content-Type")
    if protocolName == "anthropic_messages" {
      request.setValue(key, forHTTPHeaderField: "x-api-key")
      request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
    } else if protocolName == "doubao" { request.setValue(key, forHTTPHeaderField: "X-Api-Key") }
    else { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
    headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
    return request
  }

  private func encode(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value) }
  private func json(_ data: Data) throws -> [String: Any] {
    guard let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw WatchRequestError("服务返回格式无效", "Invalid service response")
    }
    return result
  }

  private func validate(_ response: URLResponse) throws -> HTTPURLResponse {
    guard let http = response as? HTTPURLResponse else {
      throw WatchRequestError("服务响应无效", "Invalid service response")
    }
    guard (200..<300).contains(http.statusCode) else {
      // Do not read or display raw error bodies, which may echo credentials.
      throw WatchRequestError("服务请求失败（HTTP \(http.statusCode)），请检查配置和权限",
                              "Service request failed (HTTP \(http.statusCode)); check settings and access")
    }
    return http
  }

  private func send(_ request: URLRequest, limit: Int = 2 * 1024 * 1024) async throws -> (Data, HTTPURLResponse) {
    do {
      let (bytes, response) = try await session.bytes(for: request)
      let http = try validate(response)
      var data = Data()
      for try await byte in bytes {
        guard data.count < limit else { throw WatchRequestError("服务响应过大", "Service response is too large") }
        data.append(byte)
      }
      return (data, http)
    } catch { throw WatchRequestError.network(error) }
  }

  private func post(_ voice: WatchVoiceConfiguration, path: String, body: Any,
                    headers: [String: String] = [:], limit: Int = 2 * 1024 * 1024) async throws -> (Data, HTTPURLResponse) {
    try await send(request(base: voice.baseUrl, path: path, key: voice.apiKey,
                           body: encode(body), protocolName: voice.protocolName, headers: headers), limit: limit)
  }

  private func transcript(_ text: String) throws -> String {
    let clean = text.unicodeScalars.filter { scalar in
      !([0...8, 11...12, 14...31].contains { $0.contains(Int(scalar.value)) })
    }
    let result = String(String.UnicodeScalarView(clean)).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !result.isEmpty, result.unicodeScalars.count <= 5000 else {
      throw WatchRequestError("没有识别到有效文字，请分段重试", "No usable transcript; try shorter recordings")
    }
    return result
  }

  func transcribe(_ wav: Data, config: WatchNetworkConfiguration) async throws -> String {
    guard config.canChat, config.canTranscribe, let voice = config.asr,
          !wav.isEmpty, wav.count <= 4 * 1024 * 1024 else {
      throw WatchRequestError("请先在手机配置文字模型和语音识别", "Set up text and transcription services on iPhone first")
    }
    switch voice.protocolName {
    case "openAi":
      let boundary = "AILink\(UUID().uuidString)"
      guard !voice.asrModel.contains(where: { $0.isNewline }) else {
        throw WatchRequestError("识别模型无效", "Invalid transcription model")
      }
      var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\n\(voice.asrModel)\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"speech.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8)
      body.append(wav)
      body.append(Data("\r\n--\(boundary)--\r\n".utf8))
      let (data, _) = try await send(request(base: voice.baseUrl, path: "/audio/transcriptions", key: voice.apiKey,
        body: body, contentType: "multipart/form-data; boundary=\(boundary)"))
      return try transcript(json(data)["text"] as? String ?? "")
    case "mimo":
      let (data, _) = try await post(voice, path: "/chat/completions", body: [
        "model": voice.asrModel, "messages": [["role": "user", "content": [[
          "type": "input_audio", "input_audio": ["data": "data:audio/wav;base64,\(wav.base64EncodedString())", "format": "wav"],
        ]]]], "asr_options": ["language": "auto"],
      ])
      let message = (try json(data)["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any]
      return try transcript(message?["content"] as? String ?? "")
    case "doubao":
      let (data, response) = try await post(voice, path: "/api/v3/auc/bigmodel/recognize/flash", body: [
        "user": ["uid": "between-models"], "audio": ["data": wav.base64EncodedString(), "format": "wav"],
        "request": ["model_name": "bigmodel"],
      ], headers: ["X-Api-Resource-Id": voice.asrModel, "X-Api-Request-Id": UUID().uuidString, "X-Api-Sequence": "-1"])
      if let code = response.value(forHTTPHeaderField: "X-Api-Status-Code"), code != "20000000" {
        throw WatchRequestError("语音识别失败，请检查资源权限", "Transcription failed; check resource access")
      }
      return try transcript((json(data)["result"] as? [String: Any])?["text"] as? String ?? "")
    default: throw WatchRequestError("不支持此识别协议", "Unsupported transcription protocol")
    }
  }

  func reply(history: [[String: String]], config: WatchNetworkConfiguration,
             onText: @escaping (String) -> Void) async throws -> String {
    guard config.canChat else { throw WatchRequestError("文字服务未配置", "Text service is not configured") }
    let anthropic = config.protocolName == "anthropic_messages"
    let prompt = config.systemPrompt ?? ""
    var messages = history
    if !anthropic && !prompt.isEmpty { messages.insert(["role": "system", "content": prompt], at: 0) }
    var body: [String: Any] = ["model": config.model, "stream": true, "messages": messages]
    if anthropic {
      body["max_tokens"] = 4096
      if !prompt.isEmpty { body["system"] = prompt }
    }
    var request = try request(base: config.baseUrl!, path: anthropic ? "/messages" : "/chat/completions",
      key: config.apiKey!, body: encode(body), protocolName: config.protocolName!)
    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
    var answer = ""
    do {
      let (bytes, response) = try await session.bytes(for: request)
      _ = try validate(response)
      var event = ""
      var line = Data()
      var total = 0
      var finished = false
      func consume() throws {
        let payload = event.trimmingCharacters(in: .whitespacesAndNewlines)
        event = ""
        if payload.isEmpty { return }
        if payload == "[DONE]" { finished = true; return }
        let value = try json(Data(payload.utf8))
        if value["error"] != nil || value["type"] as? String == "error" {
          throw WatchRequestError("模型服务返回错误，请检查权限", "Model service returned an error; check access")
        }
        var piece = ""
        if anthropic {
          if value["type"] as? String == "content_block_delta" {
            piece = (value["delta"] as? [String: Any])?["text"] as? String ?? ""
          }
          if value["type"] as? String == "message_stop" { finished = true }
        } else {
          piece = ((value["choices"] as? [[String: Any]])?.first?["delta"] as? [String: Any])?["content"] as? String ?? ""
        }
        answer += piece
        guard answer.utf16.count <= 100_000 else { throw WatchRequestError("模型回复过长", "Model reply is too long") }
        if !piece.isEmpty { onText(answer) }
      }
      func consumeLine() throws {
        guard let text = String(data: line, encoding: .utf8) else {
          throw WatchRequestError("模型返回格式无效", "Invalid model response")
        }
        line.removeAll(keepingCapacity: true)
        let value = text.hasSuffix("\r") ? String(text.dropLast()) : text
        if value.isEmpty { try consume() }
        else if value.hasPrefix("data:") { event += String(value.dropFirst(5)) + "\n" }
      }
      for try await byte in bytes {
        total += 1
        guard total <= 2 * 1024 * 1024, line.count <= 512 * 1024 else {
          throw WatchRequestError("模型响应过大", "Model response is too large")
        }
        if byte == 10 { try consumeLine(); if finished { break } }
        else { line.append(byte) }
      }
      if !line.isEmpty { try consumeLine() }
      if !event.isEmpty { try consume() }
      guard finished, !answer.isEmpty else {
        throw WatchRequestError("模型回复未完整结束，请稍后检查再重试", "Model reply did not finish; check before retrying")
      }
      return answer
    } catch {
      let failure = WatchRequestError.network(error)
      throw WatchRequestError(failure.chinese, failure.english, retrySafe: answer.isEmpty && failure.retrySafe)
    }
  }

  func synthesize(_ text: String, config: WatchNetworkConfiguration) async throws -> (Data, String)? {
    guard let voice = config.tts else { return nil }
    let input = String(String.UnicodeScalarView(text.unicodeScalars.prefix(1800))).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !input.isEmpty else { return nil }
    switch voice.protocolName {
    case "openAi":
      let (data, _) = try await post(voice, path: "/audio/speech", body: ["model": voice.ttsModel,
        "input": input, "voice": voice.voice, "response_format": "mp3"], limit: 16 * 1024 * 1024)
      guard !data.isEmpty else { throw WatchRequestError("未返回朗读音频", "No speech audio returned") }
      return (data, "mp3")
    case "mimo":
      let (data, _) = try await post(voice, path: "/chat/completions", body: ["model": voice.ttsModel,
        "messages": [["role": "assistant", "content": input]], "audio": ["format": "wav", "voice": voice.voice]], limit: 20 * 1024 * 1024)
      let message = (try json(data)["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any]
      guard let encoded = (message?["audio"] as? [String: Any])?["data"] as? String,
            let audio = Data(base64Encoded: encoded), !audio.isEmpty else {
        throw WatchRequestError("朗读音频无效", "Invalid speech audio")
      }
      return (audio, "wav")
    case "doubao":
      let (data, _) = try await post(voice, path: "/api/v3/tts/unidirectional/sse", body: [
        "user": ["uid": "between-models"], "req_params": ["text": input, "speaker": voice.voice,
          "audio_params": ["format": "mp3", "sample_rate": 24000]],
      ], headers: ["X-Api-Resource-Id": voice.ttsModel, "X-Api-Request-Id": UUID().uuidString], limit: 24 * 1024 * 1024)
      var audio = Data()
      for line in String(decoding: data, as: UTF8.self).components(separatedBy: .newlines) where line.hasPrefix("data:") {
        let event = try json(Data(line.dropFirst(5).utf8))
        if let code = event["code"] as? Int, code != 0 && code != 20000000 {
          throw WatchRequestError("语音合成失败，请检查资源权限", "Speech synthesis failed; check resource access")
        }
        if let encoded = event["data"] as? String, !encoded.isEmpty {
          guard let piece = Data(base64Encoded: encoded), audio.count + piece.count <= 16 * 1024 * 1024 else {
            throw WatchRequestError("朗读音频无效或过大", "Speech audio is invalid or too large")
          }
          audio.append(piece)
        }
      }
      guard !audio.isEmpty else { throw WatchRequestError("未返回朗读音频", "No speech audio returned") }
      return (audio, "mp3")
    default: throw WatchRequestError("不支持此朗读协议", "Unsupported speech protocol")
    }
  }
}
