import CodexIslandCore
import SwiftUI

struct DeepSeekUsageView: View {
    let usage: [DeepSeekUsageSummary]
    let connected: Bool
    let account: DeepSeekAccountSnapshot
    let language: InterfaceLanguage

    private var unavailableAmount: String {
        language.text("Unavailable", "暂不可用")
    }

    private func walletsText(_ wallets: [DeepSeekBalance.Wallet]?) -> String {
        DeepSeekBalancePresentation.walletsText(wallets, locale: language.locale) ?? unavailableAmount
    }

    var body: some View {
        if connected || !usage.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    IslandProviderBadge(provider: .deepSeek)
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
                    Text(language.text("Balance", "余额") + ": " + walletsText(balance.value))
                        .font(IslandTypography.body)
                    if let bonus = DeepSeekBalancePresentation.walletsText(
                        balance.bonusWallets, locale: language.locale
                    ) {
                        Text(language.text("Bonus", "赠送余额") + ": " + bonus)
                            .font(IslandTypography.caption).foregroundStyle(IslandPalette.subtitle)
                    }
                }
                Text(language.text("Local sessions · lifetime tokens", "本机会话 · 累计 Token"))
                    .font(IslandTypography.caption).foregroundStyle(IslandPalette.subtitle)
                Text(usage.reduce(0) { $0 + $1.tokens.totalTokens }.formatted())
                    .font(IslandTypography.section).monospacedDigit()
            }
            .padding(IslandLayout.cardPadding)
            .modifier(IslandSurface())
        }
    }
}
