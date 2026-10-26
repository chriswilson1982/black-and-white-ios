import SwiftUI

/// A short guide to the rules and bonuses, adapted from the original html/info.html.
struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                section("The goal") {
                    Text("Clear a path of white squares from the start on the left to the finish on the right, "
                         + "before the clock runs out. Squares join through their edges, not their corners.")
                    row("hand.tap.fill", "Tapping a square locks it and flips the eight squares around it.")
                    row("checkmark", "Tap the ✓ button to test your path.")
                }

                section("Scoring") {
                    Text("+1 for each square in the path, −1 for each white square left over and each "
                         + "locked square. Score zero or less and the next grid is a tricky 4×4.")
                }

                section("Bonuses") {
                    row("square.fill", "**No whites left:** leave no white squares outside the path for a bonus "
                        + "of the grid's rows plus columns.")
                    row("plus.square.fill", "**Power-up reward:** if that round scores at least the number of "
                        + "squares in the grid, you also get one of each power-up.")
                    row("star.fill", "**Star:** get it into your path for an extra power-up. If your power-ups "
                        + "are all full, you get points equal to the level instead.")
                }

                section("Power-ups") {
                    row("shuffle", "Flip every square")
                    row("xmark", "Unlock a square you tapped")
                    row("square.lefthalf.filled", "Flip one square on its own")
                }

                Text("Black & White was created by Chris Wilson, originally in Python using Pythonista.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("How to Play")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.bold())
            content()
        }
    }

    /// A line with an icon. `text` may use **bold** Markdown.
    private func row(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .frame(width: 28)
                .accessibilityHidden(true)
            Text(LocalizedStringKey(text))
        }
    }
}
