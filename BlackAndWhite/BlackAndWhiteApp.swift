import SwiftUI
import UIKit

@main
struct BlackAndWhiteApp: App {
    init() {
        Self.styleSegmentedPickers()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                // The rounded system font everywhere, to match the rounded squares.
                .fontDesign(.rounded)
                // On iPad, windows can't be made too small to play in.
                .frame(minWidth: Self.isPad ? 360 : nil, minHeight: Self.isPad ? 560 : nil)
        }
        .windowResizability(.contentMinSize)
    }

    private static let isPad = UIDevice.current.userInterfaceIdiom == .pad

    /// Segmented pickers (the difficulty pickers) are drawn by UIKit, which ignores SwiftUI's
    /// `.font` and `.fontDesign`, so their larger, rounded text is set here instead.
    private static func styleSegmentedPickers() {
        let base = UIFont.preferredFont(forTextStyle: .title3)
        var descriptor = base.fontDescriptor.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: UIFont.Weight.semibold]
        ])
        descriptor = descriptor.withDesign(.rounded) ?? descriptor
        // Size 0 keeps the text style's size, which follows the player's text size setting.
        let font = UIFont(descriptor: descriptor, size: 0)
        let appearance = UISegmentedControl.appearance()
        appearance.setTitleTextAttributes([.font: font], for: .normal)
        appearance.setTitleTextAttributes([.font: font], for: .selected)
    }
}
