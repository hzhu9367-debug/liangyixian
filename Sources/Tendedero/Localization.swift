import Foundation

private let isSpanish = Locale.preferredLanguages.first?.hasPrefix("es") ?? false
private let isChinese = Locale.preferredLanguages.first?.hasPrefix("zh") ?? false

/// Tiny two-language helper. The app has a handful of strings, so a full
/// .strings setup would be more ceremony than content.
func L(_ english: String, _ spanish: String, _ chinese: String? = nil) -> String {
    if isChinese, let chinese { return chinese }
    return isSpanish ? spanish : english
}
