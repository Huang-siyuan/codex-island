import Foundation

/// Balances arrive with full server precision; the panel only shows currency amounts to cents.
public enum DeepSeekBalancePresentation {
    public static func walletsText(
        _ wallets: [DeepSeekBalance.Wallet]?, locale: Locale = .current
    ) -> String? {
        guard let wallets, !wallets.isEmpty else {
            return nil
        }
        return wallets
            .map { "\(amountText($0.balance, locale: locale)) \($0.currency)" }
            .joined(separator: " · ")
    }

    public static func amountText(_ raw: String, locale: Locale = .current) -> String {
        guard let amount = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")) else {
            return raw
        }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? raw
    }
}
