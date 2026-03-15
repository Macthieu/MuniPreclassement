import Foundation

public struct ClassificationRule: Codable, Equatable, Sendable {
    public let code: String
    public let label: String
    public let keywords: [String]

    public init(code: String, label: String, keywords: [String]) {
        self.code = code
        self.label = label
        self.keywords = keywords
    }
}

public enum DefaultClassificationProfile {
    public static let rules: [ClassificationRule] = [
        ClassificationRule(
            code: "ADM-100",
            label: "Administration generale",
            keywords: ["conseil", "resolution", "proces", "verbal", "reglement", "seance", "municipal"]
        ),
        ClassificationRule(
            code: "FIN-200",
            label: "Finances et budget",
            keywords: ["budget", "finance", "finances", "taxe", "subvention", "depense", "investissement"]
        ),
        ClassificationRule(
            code: "INF-300",
            label: "Infrastructures et voirie",
            keywords: ["voirie", "route", "routes", "trottoir", "egout", "aqueduc", "travaux", "infrastructure"]
        ),
        ClassificationRule(
            code: "URB-400",
            label: "Urbanisme et permis",
            keywords: ["urbanisme", "zonage", "permis", "construction", "lotissement", "amenagement"]
        ),
        ClassificationRule(
            code: "SEC-500",
            label: "Securite publique",
            keywords: ["incendie", "securite", "urgence", "police", "evacuation", "sinistre"]
        )
    ]
}
