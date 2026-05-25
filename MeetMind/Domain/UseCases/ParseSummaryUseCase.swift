//
//  ParseSummaryUseCase.swift
//  MeetMind
//
//  Extracts action items and decisions from a Markdown summary string.
//  Previously this logic lived inside Meeting.syncStructuredEntities(),
//  mixing persistence concerns with parsing business logic.
//

import Foundation

// MARK: - DTOs

struct ActionItemDTO {
    let text: String
    let isCompleted: Bool
    let assignee: String?
}

struct DecisionDTO {
    let text: String
}

// MARK: - ParseSummaryUseCase

/// Pure business logic: parses a Markdown meeting summary into structured DTOs.
/// Has no SwiftData dependency — can be unit-tested in isolation.
struct ParseSummaryUseCase {

    // MARK: - Public Interface

    func extractActionItems(from markdown: String) -> [ActionItemDTO] {
        var items: [ActionItemDTO] = []
        let lines = markdown.components(separatedBy: CharacterSet.newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- [ ]") || trimmed.hasPrefix("- [x]") else { continue }

            let isDone = trimmed.hasPrefix("- [x]")
            var text = trimmed
                .replacingOccurrences(of: "- [ ]", with: "")
                .replacingOccurrences(of: "- [x]", with: "")
                .trimmingCharacters(in: .whitespaces)

            let assignee = extractAndStripAssignee(from: &text)

            guard !text.isEmpty else { continue }
            items.append(ActionItemDTO(text: text, isCompleted: isDone, assignee: assignee))
        }
        return items
    }

    func extractDecisions(from markdown: String) -> [DecisionDTO] {
        var decisions: [DecisionDTO] = []
        var inDecisionsSection = false

        let lines = markdown.components(separatedBy: CharacterSet.newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("#") {
                inDecisionsSection = trimmed.localizedCaseInsensitiveContains("рішення")
                    || trimmed.localizedCaseInsensitiveContains("decisions")
                continue
            }

            guard inDecisionsSection else { continue }
            guard trimmed.hasPrefix("-") || trimmed.hasPrefix("*") || trimmed.hasPrefix("•") else { continue }

            let text = trimmed
                .trimmingCharacters(in: CharacterSet(charactersIn: "-*• "))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            decisions.append(DecisionDTO(text: text))
        }
        return decisions
    }

    // MARK: - Private

    private let assigneeRegex = try? NSRegularExpression(
        pattern: #"\(([^)]+)\)$|@(\w+)$"#,
        options: []
    )

    /// Extracts an assignee from the end of `text` and strips it in place.
    /// Returns `nil` if no assignee pattern found.
    private func extractAndStripAssignee(from text: inout String) -> String? {
        guard let regex = assigneeRegex,
              let match = regex.firstMatch(
                in: text,
                options: [],
                range: NSRange(text.startIndex..., in: text)
              )
        else { return nil }

        let range = Range(match.range(at: 1), in: text)
                 ?? Range(match.range(at: 2), in: text)

        guard let assigneeRange = range,
              let fullMatchRange = Range(match.range, in: text)
        else { return nil }

        let assignee = String(text[assigneeRange])
        text = text.replacingCharacters(in: fullMatchRange, with: "")
            .trimmingCharacters(in: .whitespaces)
        return assignee
    }
}
