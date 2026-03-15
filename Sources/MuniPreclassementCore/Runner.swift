import Foundation

public enum ClassificationConfidence: String, Codable, Equatable, Sendable {
    case high
    case medium
    case low
}

public struct SeedKeyword: Codable, Equatable, Sendable {
    public let term: String
    public let weight: Int

    public init(term: String, weight: Int) {
        self.term = term
        self.weight = max(1, weight)
    }
}

public struct PreclassificationInput: Equatable, Sendable {
    public let text: String
    public let sourceKind: String
    public let metadataKeywords: [SeedKeyword]
    public let maxSuggestions: Int

    public init(
        text: String,
        sourceKind: String,
        metadataKeywords: [SeedKeyword] = [],
        maxSuggestions: Int = 3
    ) {
        self.text = text
        self.sourceKind = sourceKind
        self.metadataKeywords = metadataKeywords
        self.maxSuggestions = max(1, maxSuggestions)
    }
}

public struct ClassificationSuggestion: Codable, Equatable, Sendable {
    public let classCode: String
    public let classLabel: String
    public let score: Int
    public let matchedTerms: [String]
    public let rationale: String

    public init(classCode: String, classLabel: String, score: Int, matchedTerms: [String], rationale: String) {
        self.classCode = classCode
        self.classLabel = classLabel
        self.score = max(0, score)
        self.matchedTerms = matchedTerms
        self.rationale = rationale
    }

    enum CodingKeys: String, CodingKey {
        case classCode = "class_code"
        case classLabel = "class_label"
        case score
        case matchedTerms = "matched_terms"
        case rationale
    }
}

public struct PreclassificationReport: Codable, Equatable, Sendable {
    public let generatedAt: String
    public let sourceKind: String
    public let topClassCode: String?
    public let topClassLabel: String?
    public let topScore: Int
    public let confidenceLevel: ClassificationConfidence
    public let suggestions: [ClassificationSuggestion]
    public let warnings: [String]

    public init(
        generatedAt: String,
        sourceKind: String,
        topClassCode: String?,
        topClassLabel: String?,
        topScore: Int,
        confidenceLevel: ClassificationConfidence,
        suggestions: [ClassificationSuggestion],
        warnings: [String]
    ) {
        self.generatedAt = generatedAt
        self.sourceKind = sourceKind
        self.topClassCode = topClassCode
        self.topClassLabel = topClassLabel
        self.topScore = max(0, topScore)
        self.confidenceLevel = confidenceLevel
        self.suggestions = suggestions
        self.warnings = warnings
    }

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case sourceKind = "source_kind"
        case topClassCode = "top_class_code"
        case topClassLabel = "top_class_label"
        case topScore = "top_score"
        case confidenceLevel = "confidence_level"
        case suggestions
        case warnings
    }
}

public enum MuniPreclassementRunner {
    public static func preclassify(
        input: PreclassificationInput,
        rules: [ClassificationRule] = DefaultClassificationProfile.rules,
        generatedAt: String? = nil
    ) -> PreclassificationReport {
        let timestamp = generatedAt ?? isoTimestamp()
        let normalizedText = input.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let frequencies = mergedFrequencies(text: normalizedText, metadataKeywords: input.metadataKeywords)

        let scoredSuggestions = rules.map { rule -> ClassificationSuggestion in
            var matchedTerms: [String] = []
            var score = 0

            for rawKeyword in rule.keywords {
                let keyword = normalizeToken(rawKeyword)
                guard !keyword.isEmpty else { continue }
                let value = frequencies[keyword, default: 0]
                if value > 0 {
                    matchedTerms.append(keyword)
                    score += value
                }
            }

            matchedTerms.sort()
            let rationale = matchedTerms.isEmpty
                ? "Aucun terme distinctif detecte pour cette classe."
                : "Termes alignes: \(matchedTerms.joined(separator: ", "))."

            return ClassificationSuggestion(
                classCode: rule.code,
                classLabel: rule.label,
                score: score,
                matchedTerms: matchedTerms,
                rationale: rationale
            )
        }

        let sortedSuggestions = scoredSuggestions.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.classCode < rhs.classCode
            }
            return lhs.score > rhs.score
        }

        let limitedSuggestions = Array(sortedSuggestions.prefix(max(1, input.maxSuggestions)))
        let top = sortedSuggestions.first
        let secondScore = sortedSuggestions.dropFirst().first?.score ?? 0
        let topScore = top?.score ?? 0
        let gap = max(0, topScore - secondScore)
        let confidence = confidenceLevel(topScore: topScore, gap: gap)

        var warnings: [String] = []
        if normalizedText.isEmpty {
            warnings.append("Texte principal absent; classement base sur les metadonnees disponibles.")
        }
        if topScore == 0 {
            warnings.append("Aucune classe n'a atteint un score positif.")
        }
        if confidence == .low {
            warnings.append("Confiance faible; validation humaine recommandee.")
        }

        return PreclassificationReport(
            generatedAt: timestamp,
            sourceKind: input.sourceKind,
            topClassCode: top?.classCode,
            topClassLabel: top?.classLabel,
            topScore: topScore,
            confidenceLevel: confidence,
            suggestions: limitedSuggestions,
            warnings: warnings
        )
    }

    private static func confidenceLevel(topScore: Int, gap: Int) -> ClassificationConfidence {
        if topScore >= 6 && gap >= 2 {
            return .high
        }
        if topScore >= 3 && gap >= 1 {
            return .medium
        }
        return .low
    }

    private static func mergedFrequencies(text: String, metadataKeywords: [SeedKeyword]) -> [String: Int] {
        var frequencies = termFrequencies(from: text)
        for keyword in metadataKeywords {
            let normalized = normalizeToken(keyword.term)
            guard !normalized.isEmpty else { continue }
            frequencies[normalized, default: 0] += max(1, keyword.weight)
        }
        return frequencies
    }

    private static func termFrequencies(from text: String) -> [String: Int] {
        let tokens = text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        var frequencies: [String: Int] = [:]
        for token in tokens {
            frequencies[token, default: 0] += 1
        }
        return frequencies
    }

    private static func normalizeToken(_ token: String) -> String {
        token
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isoTimestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
