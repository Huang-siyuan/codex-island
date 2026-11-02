import CodexIslandCore
import SwiftUI

struct SubscriptionQuotaView: View {
    @ObservedObject var viewModel: IslandViewModel
    let language: InterfaceLanguage
    @AppStorage("quotaWarningPercent") private var warningPercent = 80.0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(language.text("Subscription limits", "订阅额度")).font(IslandTypography.heading)
                Spacer()
                if viewModel.isQuotaRefreshing { ProgressView().controlSize(.small) }
                Button { viewModel.onQuotaRefreshRequested?() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(IslandButtonStyle())
                .disabled(viewModel.isQuotaRefreshing)
                .accessibilityLabel(language.text("Refresh subscription limits", "刷新订阅额度"))
            }
            if let response = viewModel.subscriptionQuota {
                ForEach(Array(response.limits.enumerated()), id: \.offset) { _, limit in
                    Text([limit.limitName ?? limit.limitId ?? "Codex", limit.planType?.uppercased()].compactMap { $0 }.joined(separator: " · "))
                        .font(IslandTypography.caption).foregroundStyle(IslandPalette.subtitle)
                    if let window = limit.primary { quotaWindow(window) }
                    if let window = limit.secondary { quotaWindow(window) }
                    if limit.primary == nil && limit.secondary == nil {
                        Text(language.text("No quota window reported", "账户未返回额度窗口"))
                    }
                }
            } else if !viewModel.isQuotaRefreshing {
                Text(language.text("Subscription limits unavailable. Sign in to Codex and refresh.", "暂时无法读取订阅额度，请登录 Codex 后刷新。"))
                    .foregroundStyle(IslandPalette.subtitle)
            }
            if viewModel.quotaRefreshFailed {
                Text(language.text("Refresh failed; any values above are from the last successful refresh.", "刷新失败；上方如有数据，为上次成功刷新的结果。"))
                    .font(IslandTypography.caption).foregroundStyle(IslandPalette.error)
            }
            if let refreshed = viewModel.quotaRefreshedAt {
                HStack(spacing: 4) {
                    Text(language.text("Updated", "更新于"))
                    Text(refreshed, style: .relative)
                }.font(IslandTypography.caption).foregroundStyle(IslandPalette.muted)
            }
            if let alert = viewModel.quotaAlertText {
                Text(alert).font(IslandTypography.caption).foregroundStyle(IslandPalette.quotaWarning)
                    .accessibilityIdentifier("quota.alert")
            }
        }
        .font(IslandTypography.body)
        .padding(IslandLayout.cardPadding)
        .modifier(IslandSurface())
    }

    private func quotaWindow(_ window: QuotaWindow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(window.windowDurationMins.map { minutes in
                    minutes >= 1440 ? language.text("\(minutes / 1440)-day window", "\(minutes / 1440) 天额度") : language.text("\(minutes / 60)-hour window", "\(minutes / 60) 小时额度")
                } ?? language.text("Usage window", "用量窗口"))
                Spacer()
                Text(language.text("\(Int(window.remainingPercent))% remaining", "剩余 \(Int(window.remainingPercent))%"))
            }
            ProgressView(value: min(100, max(0, window.usedPercent)), total: 100)
                .progressViewStyle(QuotaProgressStyle(color: window.usedPercent >= warningPercent ? IslandPalette.quotaWarning : IslandPalette.accent))
                .accessibilityLabel(language.text("Quota used", "额度已用"))
                .accessibilityValue("\(Int(min(100, max(0, window.usedPercent))))%")
            if let reset = window.resetsAt {
                HStack(spacing: 4) {
                    Text(language.text("Resets", "重置时间"))
                    Text(Date(timeIntervalSince1970: reset), format: .dateTime.month().day().hour().minute())
                }.font(IslandTypography.caption).foregroundStyle(IslandPalette.muted)
            }
        }
    }
}

/// Keep quota warning colors visible even when the accessory window is not key.
private struct QuotaProgressStyle: ProgressViewStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { geometry in
            Capsule().fill(IslandPalette.separator)
                .overlay(alignment: .leading) {
                    Capsule().fill(color)
                        .frame(width: geometry.size.width * (configuration.fractionCompleted ?? 0))
                }
        }
        .frame(height: 6)
    }
}
