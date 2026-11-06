import CodexIslandCore
import SwiftUI

struct DeepSeekUsageView: View {
    let usage: [DeepSeekUsageSummary]
    let connected: Bool
    let account: DeepSeekAccountSnapshot
    let language: InterfaceLanguage

    private func wallets(_ values: [DeepSeekBalance.Wallet]?) -> String {
        guard let values, !values.isEmpty else { return "—" }
        return values.map { "\($0.balance) \($0.currency)" }.joined(separator: " · ")
    }

    var body: some View {
        if connected || !usage.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("DeepSeek Harness").font(IslandTypography.section)
                    Spacer()
                    Text(
                        connected
                            ? language.text("Connected", "已连接")
                            : language.text("Disconnected · cached", "未连接 · 缓存数据")
                    )
                    .font(IslandTypography.caption).foregroundStyle(IslandPalette.subtitle)
                }
                switch account {
                case .signedOut:
                    Text(language.text("Harness account not signed in", "Harness 账号未登录"))
                        .font(IslandTypography.caption).foregroundStyle(IslandPalette.subtitle)
                case .unavailable:
                    Text(language.text("Account balance unavailable", "账号余额暂不可用"))
                        .font(IslandTypography.caption).foregroundStyle(IslandPalette.subtitle)
                case .balance(let balance):
                    Text(language.text("Balance", "余额") + ": " + wallets(balance.value))
                        .font(IslandTypography.body)
                    if let bonus = balance.bonusWallets, !bonus.isEmpty {
                        Text(language.text("Bonus", "赠送余额") + ": " + wallets(bonus))
                            .font(IslandTypography.caption).foregroundStyle(IslandPalette.subtitle)
                    }
                }
                Text(language.text("Local sessions · lifetime tokens", "本机会话 · 累计 Token"))
                    .font(IslandTypography.caption).foregroundStyle(IslandPalette.subtitle)
                Text(usage.reduce(0) { $0 + $1.tokens.totalTokens }.formatted())
                    .font(IslandTypography.section).monospacedDigit()
                ForEach(usage.prefix(3)) { session in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(session.title).font(IslandTypography.body).lineLimit(1)
                        Text("\(session.tokens.totalTokens.formatted()) tokens")
                            .font(IslandTypography.caption).foregroundStyle(IslandPalette.subtitle)
                        if let used = session.contextTokens, let limit = session.contextWindow, limit > 0 {
                            ProgressView(value: Double(max(0, min(used, limit))), total: Double(limit))
                                .tint(IslandPalette.accent)
                                .accessibilityLabel(language.text("Context usage", "上下文用量"))
                            Text(language.text("Context", "上下文") + " \(used.formatted()) / \(limit.formatted())")
                                .font(IslandTypography.caption).foregroundStyle(IslandPalette.subtitle)
                        }
                    }
                }
            }
            .padding(IslandLayout.cardPadding)
            .modifier(IslandSurface())
        }
    }
}
