import Foundation
import OrchivisteKitContracts
import Testing
@testable import MuniPreclassementCore
@testable import MuniPreclassementInterop

struct MuniPreclassementCoreTests {
    @Test
    func preclassifyIsDeterministicForSameInput() {
        let input = PreclassificationInput(
            text: "Budget municipal adopte avec budget annuel, taxe locale et subvention confirmee.",
            sourceKind: "inline_text",
            metadataKeywords: [
                SeedKeyword(term: "budget", weight: 4),
                SeedKeyword(term: "finance", weight: 3)
            ],
            maxSuggestions: 3
        )

        let first = MuniPreclassementRunner.preclassify(input: input, generatedAt: "2026-03-15T00:00:00Z")
        let second = MuniPreclassementRunner.preclassify(input: input, generatedAt: "2026-03-15T00:00:00Z")

        #expect(first == second)
        #expect(first.topClassCode != nil)
        #expect(first.topClassCode == second.topClassCode)
        #expect(first.topScore > 0)
    }

    @Test
    func canonicalRunWithInlineTextSucceeds() {
        let request = ToolRequest(
            requestID: "req-inline",
            tool: "MuniPreclassement",
            action: "run",
            parameters: [
                "text": .string("Budget budget taxe subvention depense finance budget."),
                "max_suggestions": .number(3)
            ]
        )

        let result = CanonicalRunAdapter.execute(request: request)

        #expect(result.status == .succeeded)
        #expect(result.errors.isEmpty)
        #expect(result.progressEvents.last?.status == .succeeded)
    }

    @Test
    func canonicalRunWithWeakSignalReturnsNeedsReview() {
        let request = ToolRequest(
            requestID: "req-weak",
            tool: "MuniPreclassement",
            action: "run",
            parameters: [
                "text": .string("note courte")
            ]
        )

        let result = CanonicalRunAdapter.execute(request: request)

        #expect(result.status == .needsReview)
        #expect(result.errors.isEmpty)
        #expect(result.progressEvents.last?.status == .needsReview)
    }

    @Test
    func canonicalRunUsesMuniMetadonneesReportAsSeed() throws {
        let tempDirectory = try makeTempDirectory(prefix: "muni-preclassement-seed")
        let metadataReportPath = tempDirectory.appendingPathComponent("metadata-report.json").path

        let metadataPayload = """
        {
          "summary": "Compte rendu financier municipal.",
          "suggested_title": "Budget Voirie Investissements",
          "keywords": [
            {"term": "budget", "score": 5},
            {"term": "voirie", "score": 4},
            {"term": "investissement", "score": 3}
          ]
        }
        """
        try metadataPayload.write(toFile: metadataReportPath, atomically: true, encoding: .utf8)

        let request = ToolRequest(
            requestID: "req-seed",
            tool: "MuniPreclassement",
            action: "run",
            parameters: [
                "metadata_report_path": .string(metadataReportPath)
            ]
        )

        let result = CanonicalRunAdapter.execute(request: request)

        #expect(result.status == .succeeded || result.status == .needsReview)
        #expect(result.errors.isEmpty)
        #expect(result.metadata["suggestions"] != nil)
    }

    @Test
    func canonicalRunFailsWithoutAnyInput() {
        let request = ToolRequest(
            requestID: "req-missing",
            tool: "MuniPreclassement",
            action: "run"
        )

        let result = CanonicalRunAdapter.execute(request: request)

        #expect(result.status == .failed)
        #expect(result.errors.first?.code == "MISSING_INPUT")
    }

    @Test
    func canonicalRunWritesPreclassificationReportArtifact() throws {
        let tempDirectory = try makeTempDirectory(prefix: "muni-preclassement-output")
        let outputPath = tempDirectory.appendingPathComponent("preclassification-report.json").path

        let request = ToolRequest(
            requestID: "req-output",
            tool: "MuniPreclassement",
            action: "run",
            parameters: [
                "text": .string("Projet de voirie et travaux d'aqueduc."),
                "output_report_path": .string(outputPath)
            ]
        )

        let result = CanonicalRunAdapter.execute(request: request)

        #expect(result.status == .succeeded || result.status == .needsReview)
        #expect(result.outputArtifacts.count == 1)
        #expect(result.outputArtifacts.first?.kind == .report)
        #expect(FileManager.default.fileExists(atPath: outputPath))
    }

    private func makeTempDirectory(prefix: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(prefix, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
}
