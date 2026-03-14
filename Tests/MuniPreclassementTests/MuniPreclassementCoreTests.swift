import Testing
@testable import MuniPreclassementCore

struct MuniPreclassementCoreTests {
    @Test
    func placeholderReturnsNotImplementedStatus() {
        let request = ToolRequest(requestID: "req-1", tool: "MuniPreclassement", action: "run")
        let result = MuniPreclassementRunner.runPlaceholder(request: request)

        #expect(result.status == ToolStatus.notImplemented)
        #expect(result.errors.first?.code == "NOT_IMPLEMENTED")
        #expect(result.requestID == "req-1")
    }
}
