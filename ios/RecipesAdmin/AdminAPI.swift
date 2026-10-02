import Foundation
import UIKit

/// Client for the password-protected endpoints of the backend (backend/index.js `requireAdmin`).
/// Lives only in the admin app.
struct AdminAPI {
    let password: String

    /// Same values as config.js.
    static let cloudinaryCloud = "dnrswj6aw"
    static let cloudinaryPreset = "Recipes"

    enum AdminError: LocalizedError {
        case unauthorized
        case server(String)

        var errorDescription: String? {
            switch self {
            case .unauthorized: "סיסמה שגויה"
            case .server(let message): message
            }
        }
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 600
        return URLSession(configuration: config)
    }()

    private func request(_ path: String, method: String = "GET", body: Any? = nil) throws -> URLRequest {
        var request = URLRequest(url: URL(string: path, relativeTo: API.baseURL)!)
        request.httpMethod = method
        request.setValue(password, forHTTPHeaderField: "x-admin-password")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    private static func check(_ data: Data, _ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 401 { throw AdminError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw AdminError.server(message ?? "שגיאה (\(http.statusCode))")
        }
    }

    @discardableResult
    private func send(_ path: String, method: String = "GET", body: Any? = nil) async throws -> Data {
        let (data, response) = try await Self.session.data(for: try request(path, method: method, body: body))
        try Self.check(data, response)
        return data
    }

    private func json(_ path: String, method: String = "GET", body: Any? = nil) async throws -> [String: Any] {
        (try JSONSerialization.jsonObject(with: try await send(path, method: method, body: body)) as? [String: Any]) ?? [:]
    }

    // MARK: Auth

    /// Checks the password with a read-only admin request.
    func verify() async throws {
        try await send("/api/admin/pantry-staples")
    }

    // MARK: Recipes

    func recipes() async throws -> [Recipe] {
        try JSONDecoder().decode([Recipe].self, from: try await send("/api/recipes?include_hidden=true"))
    }

    /// recipe id → number of ingredients no step mentions.
    func unmatchedIngredientCounts() async throws -> [Int: Int] {
        let data = try await send("/api/admin/recipes/unmatched-ingredients")
        let rows = (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        var out: [Int: Int] = [:]
        for row in rows {
            if let id = row["recipe_id"] as? Int, let count = row["unmatched_count"] as? Int { out[id] = count }
        }
        return out
    }

    func setHidden(_ hidden: Bool, recipeID: Int) async throws {
        try await send("/api/recipes/\(recipeID)", method: "PATCH", body: ["is_hidden": hidden])
    }

    func deleteRecipe(_ id: Int) async throws {
        try await send("/api/recipes/\(id)", method: "DELETE")
    }

    /// Creates (`id == nil`) or replaces a recipe; returns its id.
    /// Note: the backend deletes the recipe's nutrition row on every update.
    func save(_ draft: RecipeDraft) async throws -> Int {
        let path = draft.id.map { "/api/recipes/\($0)" } ?? "/api/recipes"
        let saved = try await json(path, method: draft.id == nil ? "POST" : "PUT", body: draft.payload)
        guard let id = saved["id"] as? Int else { throw AdminError.server("תשובה לא צפויה מהשרת") }
        return id
    }

    /// Returns the calories per serving.
    func calculateNutrition(recipeID: Int) async throws -> String {
        let result = try await json("/api/admin/recipes/\(recipeID)/calculate-nutrition", method: "POST", body: [:])
        if let calories = result["calories"] as? Double { return JSNumber.string(calories) }
        return "\(result["calories"] ?? "?")"
    }

    func cleanDuplicates(recipeID: Int) async throws -> Int {
        (try await json("/api/admin/recipes/\(recipeID)/clean-duplicates", method: "POST"))["updated"] as? Int ?? 0
    }

    // MARK: Ingredient manager

    func aliasRows() async throws -> [AliasRow] {
        try JSONDecoder().decode([AliasRow].self, from: try await send("/api/admin/ingredients/all"))
    }

    func saveAlias(originalName: String, oldNote: String, displayName: String, note: String) async throws {
        try await send("/api/admin/ingredients/alias", method: "PUT", body: [
            "original_name": originalName, "old_note": oldNote, "new_display_name": displayName, "new_note": note,
        ])
    }

    func diagnose(name: String) async throws -> String {
        var components = URLComponents()
        components.path = "/api/admin/ingredients/diagnose"
        components.queryItems = [URLQueryItem(name: "name", value: name)]
        let data = try await send(components.string ?? "/api/admin/ingredients/diagnose")
        let object = try JSONSerialization.jsonObject(with: data)
        let pretty = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(decoding: pretty, as: UTF8.self)
    }

    func cleanAllDuplicates() async throws -> Int {
        (try await json("/api/admin/steps/clean-all-duplicates", method: "POST"))["updated"] as? Int ?? 0
    }

    struct StripResult {
        var updated: Int
        var remaining: [String]
    }

    func stripAmounts() async throws -> StripResult {
        let result = try await json("/api/admin/steps/strip-amounts", method: "POST")
        let remaining = (result["remaining"] as? [[String: Any]] ?? []).map { row in
            "\(row["recipe_title"] as? String ?? "") · שלב \(row["step_order"] ?? "?"): \(row["text"] as? String ?? "")"
        }
        return StripResult(updated: result["updated"] as? Int ?? 0, remaining: remaining)
    }

    /// Runs the step-title generation and reports progress from its event stream.
    /// Returns (updated, total).
    func generateStepTitles(progress: @escaping @MainActor (String) -> Void) async throws -> (updated: Int, total: Int) {
        let (bytes, response) = try await Self.session.bytes(for: try request("/api/admin/recipes/generate-step-titles", method: "POST"))
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 { throw AdminError.unauthorized }
            guard (200..<300).contains(http.statusCode) else { throw AdminError.server("שגיאה בהרצת הפעולה") }
        }
        var event = "message"
        var updated = 0
        var total = 0
        for try await line in bytes.lines {
            if line.hasPrefix("event:") {
                event = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                let raw = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                guard let payload = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any] else { continue }
                switch event {
                case "start":
                    total = payload["total"] as? Int ?? 0
                    await progress(total == 0 ? "אין שלבים לעדכון" : "מעבד 0 מתוך \(total)...")
                case "progress":
                    updated = payload["updated"] as? Int ?? updated
                    await progress("מעבד \(payload["processed"] ?? 0) מתוך \(payload["total"] ?? total)...")
                case "done":
                    updated = payload["updated"] as? Int ?? updated
                    total = payload["total"] as? Int ?? total
                case "error":
                    throw AdminError.server(payload["error"] as? String ?? "שגיאה במהלך העיבוד")
                default:
                    break
                }
                event = "message"
            }
        }
        return (updated, total)
    }

    // MARK: Pantry staples

    struct PantryItem: Decodable {
        let id: Int
        let name: String
        let displayName: String?
        enum CodingKeys: String, CodingKey { case id, name, displayName = "display_name" }
        var label: String { (displayName?.isEmpty == false ? displayName : nil) ?? name }
    }

    func pantryStaples() async throws -> [PantryItem] {
        try JSONDecoder().decode([PantryItem].self, from: try await send("/api/admin/pantry-staples"))
    }

    func addPantryStaple(ingredientID: Int) async throws {
        try await send("/api/admin/pantry-staples", method: "POST", body: ["ingredient_id": ingredientID])
    }

    func removePantryStaple(ingredientID: Int) async throws {
        try await send("/api/admin/pantry-staples/\(ingredientID)", method: "DELETE")
    }

    // MARK: Site settings

    func saveSettings(siteName: String, heroTitle: String, description: String, mainImageURL: String) async throws {
        try await send("/api/settings", method: "PUT", body: [
            "site_name": siteName, "hero_title": heroTitle, "site_description": description, "main_image_url": mainImageURL,
        ])
    }

    // MARK: Images (Cloudinary, unsigned preset — same as the website)

    static func multipartBody(boundary: String, fields: [(String, String)], fileName: String, fileData: Data, mimeType: String) -> Data {
        var body = Data()
        for (name, value) in fields {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\nContent-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(fileData)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return body
    }

    /// Resizes very large photos and encodes as JPEG before uploading.
    static func uploadData(for image: UIImage, maxDimension: CGFloat = 2400) -> Data? {
        let largest = max(image.size.width, image.size.height) * image.scale
        guard largest > maxDimension else { return image.jpegData(compressionQuality: 0.88) }
        let ratio = maxDimension / largest
        let size = CGSize(width: image.size.width * image.scale * ratio, height: image.size.height * image.scale * ratio)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }.jpegData(compressionQuality: 0.88)
    }

    /// Uploads to the `recipes` folder and returns the image's `secure_url`.
    static func uploadImage(_ data: Data) async throws -> String {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: URL(string: "https://api.cloudinary.com/v1_1/\(cloudinaryCloud)/image/upload")!)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let body = multipartBody(boundary: boundary,
                                 fields: [("upload_preset", cloudinaryPreset), ("folder", "recipes")],
                                 fileName: "photo.jpg", fileData: data, mimeType: "image/jpeg")
        let (responseData, response) = try await session.upload(for: request, from: body)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let url = json["secure_url"] as? String else {
            throw AdminError.server("שגיאה בהעלאת התמונה")
        }
        return url
    }
}
