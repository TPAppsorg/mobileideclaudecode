import Foundation

actor GeminiChatService {
    static let shared = GeminiChatService()
    
    /// Базовый URL Supabase edge-функции Gemini (идём напрямую в Supabase проект).
    /// Важно: здесь нет API-ключа — авторизация и доступ к Gemini происходят только на сервере.
    private let baseURL = URL(string: "https://dmlrznfuccnlpafprbxu.supabase.co/functions/v1/gemini-chat")!
    
    struct HistoryItem: Codable {
        let role: String   // "user" или "agent"
        let content: String
    }
    
    struct RequestBody: Codable {
        let userId: String?
        let message: String
        let history: [HistoryItem]?
    }
    
    struct ResponseBody: Codable {
        let reply: String
        let model: String?
    }
    
    /// Отправить запрос в Supabase edge-функцию `gemini-chat` и получить ответ модели.
    func send(
        userId: String?,
        message: String,
        history: [HistoryItem] = []
    ) async throws -> ResponseBody {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRtbHJ6bmZ1Y2NubHBhZnByYnh1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg5NTUyNzksImV4cCI6MjA5NDUzMTI3OX0.NqOvxYOQj9Iu_ksWAS8TGgFnu6fQ5DSeO7Dm4LUa-i8"
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        
        let body = RequestBody(
            userId: userId,
            message: message,
            history: history.isEmpty ? nil : history
        )
        
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "GeminiChatService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No HTTP response"])
        }
        
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: "GeminiChatService",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Server error \(http.statusCode): \(text)"]
            )
        }
        
        return try JSONDecoder().decode(ResponseBody.self, from: data)
    }
}

