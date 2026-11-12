import KickstartExchange
import SwiftUI

/// A banner for another indie app, from Kickstart Exchange: free, privacy-conscious
/// cross-promotion that matches apps, not people (see the privacy policy). Shown at the
/// bottom of Settings and How to Play, out of the way of the game itself.
struct PromoBanner: View {
    /// The app's Kickstart Exchange API key (from exchange.kickstart.tools), read from
    /// `Kickstart.plist` ("ExchangeAPIKey"). That file is kept out of Git, so the key isn't
    /// published with the source. Without it, "preview" shows a sample banner in Debug builds
    /// and the Simulator only, and nothing in release builds.
    static let apiKey: String = {
        if let url = Bundle.main.url(forResource: "Kickstart", withExtension: "plist"),
           let values = NSDictionary(contentsOf: url),
           let key = values["ExchangeAPIKey"] as? String, !key.isEmpty {
            return key
        }
        #if DEBUG
        print("Kickstart.plist is missing: using the preview key, so release builds would show no banner.")
        #endif
        return "preview"
    }()

    var body: some View {
        ExchangeBannerAdView(apiKey: Self.apiKey)
            .exchangeAdCornerStyle(.rounded)
    }
}
