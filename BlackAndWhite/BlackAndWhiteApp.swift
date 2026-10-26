import SwiftUI

@main
struct BlackAndWhiteApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                // The rounded system font everywhere, to match the rounded squares.
                .fontDesign(.rounded)
        }
    }
}
