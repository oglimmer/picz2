import Foundation

/// Whether a commentary's audio can be played on this device right now.
enum RecordingAudioReadiness {
    /// The iPhone-playable rendition is on storage.
    case ready
    /// Still being made. Ask again in a few seconds.
    case notReady
    /// The server gave up making it. Waiting will not help.
    case failed
    /// The question itself could not be asked — offline, or the server is down.
    case unreachable
}

/// Slideshow narration recordings — list, upload, delete. The album's gallery pairs one
/// recording with one (tag filter, language) combination.
extension APIClient {
    func fetchRecordings(albumId: Int, completion: @escaping (Result<[RecordingInfo], Error>) -> Void) {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/albums/\(albumId)/recordings"))
        request.httpMethod = "GET"
        addBasicAuth(to: &request)

        performRequest(request, expecting: RecordingsListResponse.self) { result in
            completion(result.map(\.recordings))
        }
    }

    /// Asks whether the iPhone rendition of a commentary is ready, and tells the server to start
    /// making it if it is not.
    ///
    /// No auth header: `GET /api/r/**` is `permitAll` on the server — the public token is the
    /// credential — which is the same deal the audio stream itself takes.
    func fetchRecordingAudioStatus(
        publicToken: String,
        completion: @escaping (RecordingAudioReadiness) -> Void,
    ) {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/r/\(publicToken)/audio/status"))
        request.httpMethod = "GET"
        // Never a cached answer: the whole point is to see the state change from not-ready to ready.
        request.cachePolicy = .reloadIgnoringLocalCacheData

        performRequest(request, expecting: RecordingAudioStatusResponse.self) { result in
            switch result {
            case let .success(status):
                if status.ready {
                    completion(.ready)
                } else {
                    completion(status.failed ? .failed : .notReady)
                }
            case .failure:
                completion(.unreachable)
            }
        }
    }

    func deleteRecording(id: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/recordings/\(id)"))
        request.httpMethod = "DELETE"
        addBasicAuth(to: &request)

        performRequestIgnoringBody(request, completion: completion)
    }

    /// Uploads one finished narration: the audio file plus the slide timings.
    ///
    /// The body is staged to a temp file and sent with `uploadTask(fromFile:)` rather than being
    /// held in memory — a long narration is several megabytes, and this runs while the phone is
    /// still holding a full-screen slideshow.
    func uploadRecording(
        albumId: Int,
        audioFileURL: URL,
        request payload: RecordingUploadRequest,
        completion: @escaping (Result<RecordingInfo?, Error>) -> Void,
    ) {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: baseURL.appendingPathComponent("api/albums/\(albumId)/recordings"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        addBasicAuth(to: &request)

        let bodyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("narration-body-\(UUID().uuidString)")

        do {
            let dataJSON = try JSONEncoder().encode(payload)
            try writeRecordingMultipartBody(
                to: bodyURL,
                audioFileURL: audioFileURL,
                dataJSON: dataJSON,
                boundary: boundary,
            )
        } catch {
            try? FileManager.default.removeItem(at: bodyURL)
            completion(.failure(error))
            return
        }

        let task = URLSession.shared.uploadTask(with: request, fromFile: bodyURL) { data, response, error in
            try? FileManager.default.removeItem(at: bodyURL)

            switch APIClient.validate(data: data, response: response, error: error) {
            case let .failure(err):
                completion(.failure(err))
            case let .success(response):
                // A success the app cannot decode is still a success — the recording is saved.
                // Report it rather than making the user record the whole thing again.
                let decoded = try? JSONDecoder().decode(RecordingResponse.self, from: response.body)
                completion(.success(decoded?.recording))
            }
        }
        task.resume()
    }

    /// Streams the two multipart parts to `destinationURL`: `audio` (the file) and `data` (the
    /// JSON), the two field names ``SlideshowRecordingController`` reads.
    private func writeRecordingMultipartBody(
        to destinationURL: URL,
        audioFileURL: URL,
        dataJSON: Data,
        boundary: String,
    ) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        fileManager.createFile(atPath: destinationURL.path, contents: nil, attributes: nil)

        let out = try FileHandle(forWritingTo: destinationURL)
        defer { try? out.close() }

        out.write(Data("--\(boundary)\r\n".utf8))
        let audioName = NarrationAudioRecorder.uploadFilename
        out.write(Data("Content-Disposition: form-data; name=\"audio\"; filename=\"\(audioName)\"\r\n".utf8))
        out.write(Data("Content-Type: audio/webm\r\n\r\n".utf8))

        let inHandle = try FileHandle(forReadingFrom: audioFileURL)
        defer { try? inHandle.close() }
        while let chunk = try inHandle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            out.write(chunk)
        }
        out.write(Data("\r\n".utf8))

        out.write(Data("--\(boundary)\r\n".utf8))
        out.write(Data("Content-Disposition: form-data; name=\"data\"\r\n".utf8))
        out.write(Data("Content-Type: application/json\r\n\r\n".utf8))
        out.write(dataJSON)
        out.write(Data("\r\n".utf8))

        out.write(Data("--\(boundary)--\r\n".utf8))
    }
}
