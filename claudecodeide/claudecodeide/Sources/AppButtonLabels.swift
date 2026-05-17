import Foundation

/// Локальные подписи только для кнопок. Меняй здесь — подставится везде в онбординге/пейволле.
enum AppButtonLabels {
    /// Кнопка подписки (онбординг и модалка «Choose your plan»). Для ревью Apple — «Subscribe»; после можно сменить и выкатить обновление.
    static let subscribe = "Subscribe"
}

/// Конфиг отображения цены только на экране пейвола (последний экран онбординга). Меняй без ревью.
enum AppPaywallPriceConfig {
    /// false = показывать как сейчас (например "$149.99 / year"). true = годовую цену в пересчёте на день (например "$0.41 / day").
    static let showYearlyPricePerDay = false
}

/// Ссылки на Terms of Use и Privacy Policy (онбординг, пейволы, More).
enum AppLegalLinks {
    static let termsOfUse = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
    static let privacyPolicy = "https://experts-draw-9pm.craft.me/TzOVehihMJTkKd"
}
