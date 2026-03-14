import Foundation

public enum MuniPreclassementRunner {
    public static func runPlaceholder(request: ToolRequest) -> ToolResult {
        let now = ISO8601DateFormatter().string(from: Date())

        return ToolResult(
            requestID: request.requestID,
            tool: "MuniPreclassement",
            status: .notImplemented,
            startedAt: now,
            finishedAt: now,
            progressEvents: [
                ProgressEvent(
                    requestID: request.requestID,
                    status: .notImplemented,
                    stage: "bootstrap",
                    percent: 100,
                    message: "MuniPreclassement scaffold is ready; business logic not implemented.",
                    occurredAt: now
                )
            ],
            outputArtifacts: [],
            errors: [
                ToolError(
                    code: "NOT_IMPLEMENTED",
                    message: "MuniPreclassement is scaffolded for CLI JSON V1 but processing logic is not implemented yet.",
                    retryable: false
                )
            ],
            summary: "MuniPreclassement returned a placeholder not_implemented result."
        )
    }
}
