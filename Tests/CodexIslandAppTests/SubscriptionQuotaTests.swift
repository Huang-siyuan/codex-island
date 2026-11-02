import Foundation
import Testing
@testable import CodexIslandCore

private func quota(_ percent: Double, reset: Int = 1000, account: String = "a") throws -> SubscriptionQuotaResponse {
    try JSONDecoder().decode(SubscriptionQuotaResponse.self, from: Data("""
    {"accountId":"\(account)","rateLimits":{"limitId":"codex","planType":"pro","primary":{"usedPercent":\(percent),"windowDurationMins":10080,"resetsAt":\(reset)}}}
    """.utf8))
}

@Test func quotaAlertsDeduplicateEscalateAndReset() throws {
    var tracker = QuotaAlertTracker()
    #expect(tracker.update(try quota(79), threshold: 80).isEmpty)
    #expect(tracker.update(try quota(80), threshold: 80).map(\.kind) == [.warning])
    #expect(tracker.update(try quota(90), threshold: 80).isEmpty)
    #expect(tracker.update(try quota(100), threshold: 80).map(\.kind) == [.exhausted])
    #expect(tracker.update(try quota(100), threshold: 80).isEmpty)
    #expect(tracker.update(try quota(0, reset: 2000), threshold: 80).map(\.kind) == [.reset])
    #expect(tracker.update(try quota(85, reset: 2000), threshold: 80).map(\.kind) == [.warning])
}

@Test func quotaAccountSwitchDoesNotReportReset() throws {
    var tracker = QuotaAlertTracker()
    _ = tracker.update(try quota(100), threshold: 80)
    #expect(tracker.update(try quota(10, account: "b"), threshold: 80).isEmpty)
    #expect(try quota(120).rateLimits.primary?.remainingPercent == 0)
}

@Test func quotaThresholdChangeAndMultipleWindows() throws {
    var tracker = QuotaAlertTracker()
    #expect(tracker.update(try quota(75), threshold: 80).isEmpty)
    #expect(tracker.update(try quota(75), threshold: 70).map(\.kind) == [.warning])
    let response = try JSONDecoder().decode(SubscriptionQuotaResponse.self, from: Data(#"{"rateLimits":{},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":100},"secondary":{"usedPercent":85}}}}"#.utf8))
    #expect(tracker.update(response, threshold: 80).map(\.kind) == [.exhausted, .warning])
}
