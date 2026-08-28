import Foundation
import os

/// One album in the share sheet's destination picker.
struct ShareAlbum: Equatable {
    let id: Int
    let name: String
    let fileCount: Int
}

/// Fetches the signed-in user's albums for the destination picker.
enum ShareAlbumsLoader {
    /// Calls back on the main actor with the albums, or `nil` when anything about the
    /// request failed — the share sheet shows the same "Failed to load albums" state for
    /// every failure, so callers don't need the distinction. An empty array is a success
    /// with no albums, which the UI presents differently.
    @MainActor
    static func fetch(
        apiBaseURL: String,
        authorization: String?,
        completion: @escaping @MainActor ([ShareAlbum]?) -> Void
    ) {
        guard let url = URL(string: "\(apiBaseURL)/albums") else {
            AppLog.share.error("Could not build the albums web address")
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        if let authorization {
            request.setValue(authorization, forHTTPHeaderField: "Authorization")
        }

        URLSession.shared.dataTask(with: request) { data, _, error in
            let albums = parse(data: data, error: error)
            DispatchQueue.main.async {
                completion(albums)
            }
        }.resume()
    }

    /// Tolerant row-by-row parsing: a row missing its id or name is skipped rather than
    /// failing the whole list, and a missing fileCount is zero.
    private static func parse(data: Data?, error: Error?) -> [ShareAlbum]? {
        if let error {
            AppLog.share.error("Could not load albums: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["success"] as? Bool) == true,
              let rows = json["albums"] as? [[String: Any]]
        else { return nil }

        return rows.compactMap { row in
            guard let id = row["id"] as? Int,
                  let name = row["name"] as? String
            else { return nil }
            return ShareAlbum(id: id, name: name, fileCount: row["fileCount"] as? Int ?? 0)
        }
    }
}
