import Foundation

enum ASRClientError: LocalizedError {
    case invalidResponse
    case httpFailure(statusCode: Int)
    case responseDecodeFailed
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "ASR returned an invalid response"
        case .httpFailure(let statusCode):
            return "ASR request failed with HTTP \(statusCode)"
        case .responseDecodeFailed:
            return "Unable to decode ASR response"
        case .emptyTranscript:
            return "ASR returned an empty transcript"
        }
    }
}

final class ASRClient {
    private struct InferenceResponse: Decodable {
        let text: String?
    }

    private let endpointURL: URL
    private let session: URLSession

    init(endpointURL: URL = RisperConfiguration.asrInferenceURL, session: URLSession = .shared) {
        self.endpointURL = endpointURL
        self.session = session
    }

    func transcribe(
        recording: RecordingResult,
        language: DictationLanguage,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let audioData: Data

        do {
            audioData = try Data(contentsOf: recording.url)
        } catch {
            completion(.failure(error))
            return
        }

        let boundary = "RisperBoundary-\(UUID().uuidString)"
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.multipartBody(
            audioData: audioData,
            filename: recording.url.lastPathComponent,
            language: language.whisperCode,
            boundary: boundary
        )

        session.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse,
                  let data else {
                completion(.failure(ASRClientError.invalidResponse))
                return
            }

            guard httpResponse.statusCode == 200 else {
                completion(.failure(ASRClientError.httpFailure(statusCode: httpResponse.statusCode)))
                return
            }

            do {
                let decoded = try JSONDecoder().decode(InferenceResponse.self, from: data)
                let cleanedTranscript = TranscriptCleaner.clean(decoded.text ?? "")

                guard !cleanedTranscript.isEmpty else {
                    completion(.failure(ASRClientError.emptyTranscript))
                    return
                }

                completion(.success(cleanedTranscript))
            } catch is DecodingError {
                completion(.failure(ASRClientError.responseDecodeFailed))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    private static func multipartBody(audioData: Data, filename: String, language: String, boundary: String) -> Data {
        var body = Data()

        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        body.appendUTF8("Content-Type: audio/wav\r\n\r\n")
        body.append(audioData)
        body.appendUTF8("\r\n")

        appendField("language", value: language, boundary: boundary, to: &body)
        appendField("translate", value: "false", boundary: boundary, to: &body)
        appendField("no_timestamps", value: "true", boundary: boundary, to: &body)
        appendField("temperature", value: "0.0", boundary: boundary, to: &body)
        appendField("temperature_inc", value: "0.2", boundary: boundary, to: &body)
        appendField("response_format", value: "json", boundary: boundary, to: &body)

        body.appendUTF8("--\(boundary)--\r\n")
        return body
    }

    private static func appendField(_ name: String, value: String, boundary: String, to body: inout Data) {
        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        body.appendUTF8("\(value)\r\n")
    }
}

private extension Data {
    mutating func appendUTF8(_ string: String) {
        append(Data(string.utf8))
    }
}
