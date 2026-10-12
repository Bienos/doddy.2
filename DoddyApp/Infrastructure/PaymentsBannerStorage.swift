import DoddyCore
import Foundation

/// The Home payments banner's facts, kept on this iPhone only (never sent anywhere).
struct UserDefaultsPaymentsBannerStorage: PaymentsBannerStorage {
    func everEnabled() -> Bool { UserDefaults.standard.bool(forKey: PreferenceKey.paymentsEverEnabled) }
    func markEverEnabled() { UserDefaults.standard.set(true, forKey: PreferenceKey.paymentsEverEnabled) }
    func acknowledged() -> Int { UserDefaults.standard.integer(forKey: PreferenceKey.paymentsAcknowledgedUnresolved) }
    func setAcknowledged(_ count: Int) { UserDefaults.standard.set(count, forKey: PreferenceKey.paymentsAcknowledgedUnresolved) }
    func lastUnresolved() -> Int { UserDefaults.standard.integer(forKey: PreferenceKey.paymentsLastUnresolved) }
    func setLastUnresolved(_ count: Int) { UserDefaults.standard.set(count, forKey: PreferenceKey.paymentsLastUnresolved) }
}
