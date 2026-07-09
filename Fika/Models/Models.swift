import Foundation

// DTOs mirroring the Fika sidecar (sidecar/server.py). Secondary fields are
// optional so a hand-rolled server response never fails to decode.

struct Health: Codable {
    let status: String
    let namespace: String?
    let has_openai_key: Bool?
}

struct Usage: Codable {
    let cost_usd: Double
    let input_tokens: Int
    let output_tokens: Int
    let people: Int
    let notes: Int
}

struct PersonRef: Codable, Hashable, Identifiable {
    let id: String
    let name: String
}

/// A person "card" — the shape returned by /people and inside search hits.
struct Person: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    var relationship: String = ""
    var tags: [String] = []
    var interests: [String] = []
    var places: [String] = []
    var note_count: Int = 0
    var last_interaction: String?
    var days_since: Int?
    var has_avatar: Bool = false
    var score: Double?
}

struct RelatedPerson: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    var shared: [String] = []
}

/// The superset returned by GET /people/{id} (flat JSON).
struct PersonDetail: Codable, Identifiable {
    let id: String
    let name: String
    var relationship: String = ""
    var tags: [String] = []
    var interests: [String] = []
    var places: [String] = []
    var organizations: [String] = []
    var events: [String] = []
    var note_count: Int = 0
    var last_interaction: String?
    var days_since: Int?
    var has_avatar: Bool = false
    var profile: String = ""
    var timeline: [Note] = []
    var related_people: [RelatedPerson] = []
    var reminders: [Reminder] = []
}

struct Note: Codable, Identifiable, Hashable {
    let id: String
    var text: String = ""
    var title: String = ""
    var occurred_at: String?
    var people: [String] = []
    var prompt: String?
    var score: Double?
}

struct Answer: Codable {
    var answer: String = ""
    var sources: [String] = []
    var people: [PersonRef] = []
    var confidence: String?
}

struct QuestionCard: Codable {
    var title: String = ""
    var question: String = ""
    var reason: String = ""
    var hint: String = ""
    var people: [String] = []
}

struct Reminder: Codable, Identifiable, Hashable {
    let id: String
    var text: String = ""
    var person_id: String = ""
    var person_name: String = ""
    var due_at: String?
    var created_at: String?
    var status: String = "open"
}

struct Connection: Codable, Identifiable {
    var id: String { "\(type):\(label)" }
    let type: String
    let label: String
    var people: [PersonRef] = []
    var count: Int = 0
    var you: Bool?
}

struct Serendipity: Codable {
    var reconnect: [Person] = []
    var connections: [Connection] = []
    var spotlight: Person?
}

struct SearchResponse: Codable {
    var people: [Person] = []
    var notes: [Note] = []
    var answer: Answer?
    var question_card: QuestionCard?
    var reminder: Reminder?
    var mode: String = ""
}

struct SearchTurn: Codable {
    var q: String
    var answer: String
    var people: [PersonRef]
}

struct Me: Codable {
    var profile: String = ""
    var interests: [String] = []
    var places: [String] = []
}

struct MemoryGap: Codable, Identifiable {
    let id: String
    let q: String
}

struct MemoryState: Codable {
    var enabled: Bool = false
    var gaps: [MemoryGap] = []
    var counts: [String: Int] = [:]
}

struct Questions: Codable {
    var questions: [String] = []
}

// Small write-response shapes.
struct CreatedID: Codable {
    let id: String
    var name: String?
    var entities_extracted: Int?
}

struct Transcription: Codable {
    let text: String
}
