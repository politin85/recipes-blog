import Foundation

/// Client for the public endpoints of the Railway backend (backend/index.js).
/// Admin endpoints are deliberately not part of this app.
struct API {
    /// Same value as `CONFIG.API` in config.js.
    static let baseURL = URL(string: "https://tts-proxy-production-675e.up.railway.app")!
    static let shared = API()

    enum APIError: Error { case badStatus(Int), missingAudio }

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()

    private func url(_ path: String) -> URL {
        URL(string: path, relativeTo: Self.baseURL)!
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.badStatus(http.statusCode)
        }
        return data
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        try JSONDecoder().decode(T.self, from: try await send(URLRequest(url: url(path))))
    }

    private func jsonRequest(_ path: String, method: String, body: [String: Any]) throws -> URLRequest {
        var request = URLRequest(url: url(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    func settings() async throws -> [String: String] {
        let data = try await send(URLRequest(url: url("/api/settings")))
        let raw = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        return raw.compactMapValues { $0 as? String }
    }

    func recipes() async throws -> [Recipe] { try await get("/api/recipes") }

    func recipe(id: Int) async throws -> Recipe { try await get("/api/recipes/\(id)") }

    /// Returns nil when the recipe has no nutrition row.
    func nutrition(recipeID: Int) async throws -> Nutrition? {
        let data = try await send(URLRequest(url: url("/api/recipes/\(recipeID)/nutrition")))
        return try JSONDecoder().decode(Nutrition?.self, from: data)
    }

    func ingredients() async throws -> [CatalogIngredient] { try await get("/api/ingredients") }

    func recipesByIngredients(ids: [Int], includePantry: Bool) async throws -> [Recipe] {
        let request = try jsonRequest("/api/recipes/by-ingredients", method: "POST",
                                      body: ["ingredient_ids": ids, "include_pantry": includePantry])
        return try JSONDecoder().decode([Recipe].self, from: try await send(request))
    }

    func addNote(recipeID: Int, text: String) async throws -> RecipeNote {
        let request = try jsonRequest("/api/recipes/\(recipeID)/notes", method: "POST", body: ["note_text": text])
        return try JSONDecoder().decode(RecipeNote.self, from: try await send(request))
    }

    func deleteNote(recipeID: Int, noteID: Int) async throws {
        var request = URLRequest(url: url("/api/recipes/\(recipeID)/notes/\(noteID)"))
        request.httpMethod = "DELETE"
        _ = try await send(request)
    }

    /// Google TTS via the backend proxy; returns MP3 data.
    func tts(text: String, voice: String) async throws -> Data {
        let request = try jsonRequest("/tts", method: "POST", body: ["text": text, "voice": voice])
        let data = try await send(request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let base64 = json["audioContent"] as? String,
              let audio = Data(base64Encoded: base64) else { throw APIError.missingAudio }
        return audio
    }
}
