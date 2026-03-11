import Foundation
import AppKit

class SignatureManager: ObservableObject {
    @Published var savedSignatures: [SavedSignature] = []

    private static let storageKey = "pdfSignatures"

    struct SavedSignature: Codable, Identifiable {
        let id: UUID
        let name: String
        let imageData: Data
        let created: Date

        init(name: String, image: NSImage) {
            self.id = UUID()
            self.name = name
            self.created = Date()
            self.imageData = image.tiffRepresentation ?? Data()
        }

        var image: NSImage? {
            NSImage(data: imageData)
        }
    }

    init() {
        load()
    }

    func save(_ signature: SavedSignature) {
        savedSignatures.append(signature)
        persist()
    }

    func delete(_ id: UUID) {
        savedSignatures.removeAll { $0.id == id }
        persist()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let sigs = try? JSONDecoder().decode([SavedSignature].self, from: data) else { return }
        savedSignatures = sigs
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(savedSignatures) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
