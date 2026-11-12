import KickstartExchange
import SwiftUI

/// A banner for another indie app, from Kickstart Exchange: free, privacy-conscious
/// cross-promotion that matches apps, not people (see the privacy policy). Shown at the
/// bottom of Settings and How to Play, out of the way of the game itself.
struct PromoBanner: View {
    /// The app's Kickstart Exchange API key, from exchange.kickstart.tools. (For a sample banner
    /// without an account, "preview" works in Debug builds and the Simulator only.)
    static let apiKey = "ks_live_jHl5I1upq4HIybKFJ_iOU-G7-5lkPx_tYuyXjecBp7U"

    var body: some View {
        ExchangeBannerAdView(apiKey: Self.apiKey)
            .exchangeAdCornerStyle(.rounded)
    }
}
