import Foundation
import MuniPreclassementCore
import OrchivisteKitContracts

private struct MetadataKeywordPayload: Codable {
    let term: String
    let score: Int
}

private struct MetadataReportPayload: Codable {
    let keywords: [MetadataKeywordPayload]?
    let summary: String?
    let suggestedTitle: String?

    enum CodingKeys: String, CodingKey {
        case keywords
        case summary
        case suggestedTitle = "suggested_title"
    }
}

private struct MuniReglesBundleManifestPayload: Codable {
    let bundleVersion: String
    let moduleVersion: String?

    enum CodingKeys: String, CodingKey {
        case bundleVersion = "bundle_version"
        case moduleVersion = "module_version"
    }
}

private struct MuniReglesClassificationEntryPayload: Codable {
    let code: String
    let label: String
    let path: String
}

private struct MuniReglesClassificationPlanPayload: Codable {
    let entries: [MuniReglesClassificationEntryPayload]
}

private struct MuniReglesBundlePayload: Codable {
    let manifest: MuniReglesBundleManifestPayload
    let classificationPlan: MuniReglesClassificationPlanPayload

    enum CodingKeys: String, CodingKey {
        case manifest
        case classificationPlan = "classification_plan"
    }
}

public enum CanonicalRunAdapterError: Error, Sendable {
    case unsupportedAction(String)
    case missingInput
    case invalidParameter(String, String)
    case sourceReadFailed(String)
    case metadataReportParseFailed(String)
    case reportWriteFailed(String)
    case runtimeFailure(String)

    var toolError: ToolError {
        switch self {
        case .unsupportedAction(let action):
            return ToolError(code: "UNSUPPORTED_ACTION", message: "Unsupported action: \(action)", retryable: false)
        case .missingInput:
            return ToolError(
                code: "MISSING_INPUT",
                message: "Provide input via text/source_path/input artifact or metadata_report_path.",
                retryable: false
            )
        case .invalidParameter(let parameter, let reason):
            return ToolError(code: "INVALID_PARAMETER", message: "Invalid parameter \(parameter): \(reason)", retryable: false)
        case .sourceReadFailed(let reason):
            return ToolError(code: "SOURCE_READ_FAILED", message: reason, retryable: false)
        case .metadataReportParseFailed(let reason):
            return ToolError(code: "METADATA_REPORT_PARSE_FAILED", message: reason, retryable: false)
        case .reportWriteFailed(let reason):
            return ToolError(code: "REPORT_WRITE_FAILED", message: reason, retryable: true)
        case .runtimeFailure(let reason):
            return ToolError(code: "RUNTIME_FAILURE", message: reason, retryable: false)
        }
    }
}

private struct ParsedMetadataSeed: Sendable {
    let summary: String?
    let suggestedTitle: String?
    let keywords: [SeedKeyword]
}

private struct CanonicalExecutionContext: Sendable {
    let input: PreclassificationInput
    let rules: [ClassificationRule]
    let rulesSource: String
    let rulesBundleVersion: String?
    let rulesModuleVersion: String?
    let rulesBundlePath: String?
    let rulesFallbackReason: String?
    let outputPath: String?
}

public enum CanonicalRunAdapter {
    public static func execute(request: ToolRequest) -> ToolResult {
        let startedAt = isoTimestamp()

        do {
            let context = try parseContext(from: request)
            let report = MuniPreclassementRunner.preclassify(
                input: context.input,
                rules: context.rules,
                generatedAt: isoTimestamp()
            )
            let finishedAt = isoTimestamp()

            let status: ToolStatus = report.confidenceLevel == .low ? .needsReview : .succeeded
            let summary = status == .succeeded
                ? "Preclassification completed successfully."
                : "Preclassification completed with review warnings."

            var outputArtifacts: [ArtifactDescriptor] = []
            if let outputPath = context.outputPath {
                try writeReport(report, toPath: outputPath)
                outputArtifacts.append(
                    ArtifactDescriptor(
                        id: "preclassification_report",
                        kind: .report,
                        uri: fileURI(forPath: outputPath),
                        mediaType: "application/json",
                        metadata: [
                            "top_score": .number(Double(report.topScore))
                        ]
                    )
                )
            }

            return makeResult(
                request: request,
                startedAt: startedAt,
                finishedAt: finishedAt,
                status: status,
                summary: summary,
                outputArtifacts: outputArtifacts,
                errors: [],
                metadata: resultMetadata(from: report, context: context)
            )
        } catch let adapterError as CanonicalRunAdapterError {
            let finishedAt = isoTimestamp()
            return makeFailureResult(
                request: request,
                startedAt: startedAt,
                finishedAt: finishedAt,
                errors: [adapterError.toolError],
                summary: "Canonical preclassification request failed."
            )
        } catch {
            let finishedAt = isoTimestamp()
            return makeFailureResult(
                request: request,
                startedAt: startedAt,
                finishedAt: finishedAt,
                errors: [CanonicalRunAdapterError.runtimeFailure(error.localizedDescription).toolError],
                summary: "Canonical preclassification request failed with an unexpected runtime error."
            )
        }
    }

    private static func parseContext(from request: ToolRequest) throws -> CanonicalExecutionContext {
        try validateAction(request.action)

        let inlineText = try optionalStringParameter("text", in: request)
        let sourcePath = try optionalStringParameter("source_path", in: request)
        let outputPath = try optionalStringParameter("output_report_path", in: request)

        let maxSuggestions = try optionalIntParameter("max_suggestions", in: request) ?? 3
        guard (1...5).contains(maxSuggestions) else {
            throw CanonicalRunAdapterError.invalidParameter("max_suggestions", "expected integer in range 1...5")
        }

        let rulesContext = try resolveRulesContext(from: request)
        let metadataSeed = try resolveMetadataSeed(from: request)

        let resolvedText: String
        let sourceKind: String
        if let inlineText, !inlineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            resolvedText = inlineText
            sourceKind = "inline_text"
        } else if let sourcePath {
            resolvedText = try readText(fromPath: sourcePath)
            sourceKind = "source_path"
        } else if let inputPath = firstInputArtifactPath(in: request) {
            resolvedText = try readText(fromPath: inputPath)
            sourceKind = "input_artifact"
        } else {
            let combined = [metadataSeed.suggestedTitle, metadataSeed.summary]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: ". ")
            resolvedText = combined
            sourceKind = metadataSeed.keywords.isEmpty ? "unknown" : "metadata_report"
        }

        if resolvedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && metadataSeed.keywords.isEmpty {
            throw CanonicalRunAdapterError.missingInput
        }

        let input = PreclassificationInput(
            text: resolvedText,
            sourceKind: sourceKind,
            metadataKeywords: metadataSeed.keywords,
            maxSuggestions: maxSuggestions
        )

        return CanonicalExecutionContext(
            input: input,
            rules: rulesContext.rules,
            rulesSource: rulesContext.source,
            rulesBundleVersion: rulesContext.bundleVersion,
            rulesModuleVersion: rulesContext.moduleVersion,
            rulesBundlePath: rulesContext.bundlePath,
            rulesFallbackReason: rulesContext.fallbackReason,
            outputPath: outputPath
        )
    }

    private static func validateAction(_ rawAction: String) throws {
        let normalized = rawAction.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "run", "preclassify":
            return
        default:
            throw CanonicalRunAdapterError.unsupportedAction(rawAction)
        }
    }

    private static func optionalStringParameter(_ key: String, in request: ToolRequest) throws -> String? {
        guard let value = request.parameters[key] else {
            return nil
        }

        switch value {
        case .string(let rawValue):
            let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return ""
            }
            switch key {
            case "source_path", "metadata_report_path", "output_report_path", "regles_bundle_path", "bundle_path":
                return resolvePathFromURIOrPath(trimmed)
            default:
                return trimmed
            }
        default:
            throw CanonicalRunAdapterError.invalidParameter(key, "expected string")
        }
    }

    private static func optionalIntParameter(_ key: String, in request: ToolRequest) throws -> Int? {
        guard let value = request.parameters[key] else {
            return nil
        }

        switch value {
        case .number(let numberValue):
            guard numberValue.rounded() == numberValue else {
                throw CanonicalRunAdapterError.invalidParameter(key, "expected integer value")
            }
            return Int(numberValue)
        default:
            throw CanonicalRunAdapterError.invalidParameter(key, "expected number")
        }
    }

    private static func resolveMetadataSeed(from request: ToolRequest) throws -> ParsedMetadataSeed {
        if let explicitPath = try optionalStringParameter("metadata_report_path", in: request), !explicitPath.isEmpty {
            return try parseMetadataSeed(fromPath: explicitPath)
        }

        if let reportArtifact = request.inputArtifacts.first(where: { $0.kind == .report }) {
            return try parseMetadataSeed(fromPath: resolvePathFromURIOrPath(reportArtifact.uri))
        }

        return ParsedMetadataSeed(summary: nil, suggestedTitle: nil, keywords: [])
    }

    private static func resolveRulesContext(from request: ToolRequest) throws -> (
        rules: [ClassificationRule],
        source: String,
        bundleVersion: String?,
        moduleVersion: String?,
        bundlePath: String?,
        fallbackReason: String?
    ) {
        let bundlePath = try resolveMuniReglesBundlePath(from: request)
        guard let bundlePath, !bundlePath.isEmpty else {
            return (
                rules: DefaultClassificationProfile.rules,
                source: "fallback_local",
                bundleVersion: nil,
                moduleVersion: nil,
                bundlePath: nil,
                fallbackReason: nil
            )
        }

        guard let bundle = try? parseMuniReglesBundle(fromPath: bundlePath) else {
            return (
                rules: DefaultClassificationProfile.rules,
                source: "fallback_local",
                bundleVersion: nil,
                moduleVersion: nil,
                bundlePath: bundlePath,
                fallbackReason: "bundle_unreadable_or_invalid"
            )
        }

        let mappedRules = mapRules(from: bundle)
        guard !mappedRules.isEmpty else {
            return (
                rules: DefaultClassificationProfile.rules,
                source: "fallback_local",
                bundleVersion: normalizedNonEmpty(bundle.manifest.bundleVersion),
                moduleVersion: normalizedNonEmpty(bundle.manifest.moduleVersion),
                bundlePath: bundlePath,
                fallbackReason: "bundle_contains_no_usable_rules"
            )
        }

        return (
            rules: mappedRules,
            source: "muniregles_bundle",
            bundleVersion: normalizedNonEmpty(bundle.manifest.bundleVersion),
            moduleVersion: normalizedNonEmpty(bundle.manifest.moduleVersion),
            bundlePath: bundlePath,
            fallbackReason: nil
        )
    }

    private static func resolveMuniReglesBundlePath(from request: ToolRequest) throws -> String? {
        if let explicitPath = try optionalStringParameter("regles_bundle_path", in: request), !explicitPath.isEmpty {
            return explicitPath
        }

        if let legacyPath = try optionalStringParameter("bundle_path", in: request), !legacyPath.isEmpty {
            return legacyPath
        }

        let supportedIDs: Set<String> = ["regles_bundle", "bundle"]
        guard let artifact = request.inputArtifacts.first(where: { supportedIDs.contains($0.id.lowercased()) }) else {
            return nil
        }

        let resolved = resolvePathFromURIOrPath(artifact.uri).trimmingCharacters(in: .whitespacesAndNewlines)
        return resolved.isEmpty ? nil : resolved
    }

    private static func parseMuniReglesBundle(fromPath path: String) throws -> MuniReglesBundlePayload {
        let fileURL = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(MuniReglesBundlePayload.self, from: data)
    }

    private static func mapRules(from bundle: MuniReglesBundlePayload) -> [ClassificationRule] {
        var seenCodes: Set<String> = []

        return bundle.classificationPlan.entries.compactMap { entry in
            let code = entry.code.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = entry.label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !code.isEmpty, !label.isEmpty else {
                return nil
            }
            guard seenCodes.insert(code).inserted else {
                return nil
            }

            let keywords = normalizedTokens(from: "\(label) \(entry.path)")
            guard !keywords.isEmpty else {
                return nil
            }

            return ClassificationRule(code: code, label: label, keywords: keywords)
        }
    }

    private static func normalizedTokens(from value: String) -> [String] {
        let normalized = value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 }

        var deduped: [String] = []
        var seen: Set<String> = []
        for token in normalized where seen.insert(token).inserted {
            deduped.append(token)
        }
        return Array(deduped.prefix(24))
    }

    private static func normalizedNonEmpty(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func parseMetadataSeed(fromPath path: String) throws -> ParsedMetadataSeed {
        let fileURL = URL(fileURLWithPath: path)

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw CanonicalRunAdapterError.sourceReadFailed(
                "Unable to read metadata report at \(path): \(error.localizedDescription)"
            )
        }

        if let payload = try? JSONDecoder().decode(MetadataReportPayload.self, from: data) {
            let keywords = (payload.keywords ?? []).map { SeedKeyword(term: $0.term, weight: $0.score) }
            return ParsedMetadataSeed(summary: payload.summary, suggestedTitle: payload.suggestedTitle, keywords: keywords)
        }

        if let toolResult = try? JSONDecoder().decode(ToolResult.self, from: data) {
            return ParsedMetadataSeed(
                summary: jsonString(from: toolResult.metadata["summary"]),
                suggestedTitle: jsonString(from: toolResult.metadata["suggested_title"]),
                keywords: parseKeywords(fromToolMetadata: toolResult.metadata)
            )
        }

        throw CanonicalRunAdapterError.metadataReportParseFailed(
            "Unsupported JSON structure for metadata report at \(path)."
        )
    }

    private static func parseKeywords(fromToolMetadata metadata: [String: JSONValue]) -> [SeedKeyword] {
        guard case .array(let entries)? = metadata["keywords"] else {
            return []
        }

        return entries.compactMap { value in
            guard case .object(let object) = value,
                  let term = jsonString(from: object["term"]),
                  let score = jsonInt(from: object["score"]) else {
                return nil
            }
            return SeedKeyword(term: term, weight: score)
        }
    }

    private static func jsonString(from value: JSONValue?) -> String? {
        guard case .string(let raw)? = value else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func jsonInt(from value: JSONValue?) -> Int? {
        guard case .number(let raw)? = value else {
            return nil
        }
        guard raw.rounded() == raw else {
            return nil
        }
        return Int(raw)
    }

    private static func firstInputArtifactPath(in request: ToolRequest) -> String? {
        request.inputArtifacts
            .first(where: { $0.kind == .input })
            .map { resolvePathFromURIOrPath($0.uri) }
    }

    private static func readText(fromPath path: String) throws -> String {
        let fileURL = URL(fileURLWithPath: path)

        do {
            return try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            do {
                let data = try Data(contentsOf: fileURL)
                return String(decoding: data, as: UTF8.self)
            } catch {
                throw CanonicalRunAdapterError.sourceReadFailed(
                    "Unable to read source text at \(path): \(error.localizedDescription)"
                )
            }
        }
    }

    private static func writeReport(_ report: PreclassificationReport, toPath path: String) throws {
        do {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(report)
            try data.write(to: url, options: .atomic)
        } catch {
            throw CanonicalRunAdapterError.reportWriteFailed(
                "Unable to write preclassification report at \(path): \(error.localizedDescription)"
            )
        }
    }

    private static func resultMetadata(
        from report: PreclassificationReport,
        context: CanonicalExecutionContext
    ) -> [String: JSONValue] {
        var metadata: [String: JSONValue] = [
            "source_kind": .string(report.sourceKind),
            "top_score": .number(Double(report.topScore)),
            "confidence_level": .string(report.confidenceLevel.rawValue),
            "rules_source": .string(context.rulesSource),
            "rules_count": .number(Double(context.rules.count)),
            "suggestions": .array(
                report.suggestions.map { suggestion in
                    .object([
                        "class_code": .string(suggestion.classCode),
                        "class_label": .string(suggestion.classLabel),
                        "score": .number(Double(suggestion.score)),
                        "matched_terms": .array(suggestion.matchedTerms.map { .string($0) }),
                        "rationale": .string(suggestion.rationale)
                    ])
                }
            )
        ]

        if let topCode = report.topClassCode {
            metadata["top_class_code"] = .string(topCode)
        }
        if let topLabel = report.topClassLabel {
            metadata["top_class_label"] = .string(topLabel)
        }
        if let bundleVersion = context.rulesBundleVersion {
            metadata["rules_bundle_version"] = .string(bundleVersion)
        }
        if let moduleVersion = context.rulesModuleVersion {
            metadata["rules_module_version"] = .string(moduleVersion)
        }
        if let bundlePath = context.rulesBundlePath {
            metadata["rules_bundle_path"] = .string(bundlePath)
        }
        if let fallbackReason = context.rulesFallbackReason {
            metadata["rules_fallback_reason"] = .string(fallbackReason)
        }
        if !report.warnings.isEmpty {
            metadata["warnings"] = .array(report.warnings.map { .string($0) })
        }

        return metadata
    }

    private static func makeResult(
        request: ToolRequest,
        startedAt: String,
        finishedAt: String,
        status: ToolStatus,
        summary: String,
        outputArtifacts: [ArtifactDescriptor],
        errors: [ToolError],
        metadata: [String: JSONValue]
    ) -> ToolResult {
        ToolResult(
            requestID: request.requestID,
            tool: request.tool,
            status: status,
            startedAt: startedAt,
            finishedAt: finishedAt,
            progressEvents: [
                ProgressEvent(
                    requestID: request.requestID,
                    status: .running,
                    stage: "load_input",
                    percent: 20,
                    message: "Canonical request parsed.",
                    occurredAt: startedAt
                ),
                ProgressEvent(
                    requestID: request.requestID,
                    status: .running,
                    stage: "classify",
                    percent: 75,
                    message: "Deterministic preclassification executed.",
                    occurredAt: finishedAt
                ),
                ProgressEvent(
                    requestID: request.requestID,
                    status: status,
                    stage: "preclassification_complete",
                    percent: 100,
                    message: summary,
                    occurredAt: finishedAt
                )
            ],
            outputArtifacts: outputArtifacts,
            errors: errors,
            summary: summary,
            metadata: metadata
        )
    }

    private static func makeFailureResult(
        request: ToolRequest,
        startedAt: String,
        finishedAt: String,
        errors: [ToolError],
        summary: String
    ) -> ToolResult {
        ToolResult(
            requestID: request.requestID,
            tool: request.tool,
            status: .failed,
            startedAt: startedAt,
            finishedAt: finishedAt,
            progressEvents: [
                ProgressEvent(
                    requestID: request.requestID,
                    status: .running,
                    stage: "load_input",
                    percent: 20,
                    message: "Canonical request parsed.",
                    occurredAt: startedAt
                ),
                ProgressEvent(
                    requestID: request.requestID,
                    status: .failed,
                    stage: "preclassification_failed",
                    percent: 100,
                    message: summary,
                    occurredAt: finishedAt
                )
            ],
            outputArtifacts: [],
            errors: errors,
            summary: summary,
            metadata: ["action": .string(request.action)]
        )
    }

    private static func resolvePathFromURIOrPath(_ candidate: String) -> String {
        guard let url = URL(string: candidate), url.isFileURL else {
            return candidate
        }
        return url.path
    }

    private static func fileURI(forPath path: String) -> String {
        URL(fileURLWithPath: path).absoluteString
    }

    private static func isoTimestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
