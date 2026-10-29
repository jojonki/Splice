import Foundation
import Observation
import SwiftUI

@Observable
final class ProjectStore {
    var projects: [Project] = [] {
        didSet { save() }
    }

    private let fileURL = URL.documentsDirectory.appending(path: "projects.json")

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([Project].self, from: data) {
            projects = decoded
        }
    }

    func binding(for id: UUID) -> Binding<Project>? {
        guard let current = projects.first(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { self.projects.first { $0.id == id } ?? current },
            set: { newValue in
                if let i = self.projects.firstIndex(where: { $0.id == id }) { self.projects[i] = newValue }
            }
        )
    }

    private func save() {
        do {
            try JSONEncoder().encode(projects).write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save projects: \(error)")
        }
    }
}

func formatDuration(_ seconds: Double) -> String {
    let total = Int(seconds.rounded())
    let h = total / 3600, m = total % 3600 / 60, s = total % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
}
