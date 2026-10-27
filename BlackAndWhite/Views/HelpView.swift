import SwiftUI

/// A short guide to the rules and bonuses, adapted from the original html/info.html.
struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                section("The goal") {
                    Text("Clear a path of white squares through the grid from the start point on the left to the finish point on the right, before the clock runs out. Squares join through their edges, not their corners.")
                    Text("Levels are randomly generated and vary in grid size. As you progress, the clock gets faster.")
                    row("hand.tap.fill", "Tapping a square locks it and flips the eight squares around it from white to black or black to white.")
                    row("checkmark", "Tap the ✓ button to test your path! This will happen anyway when the time runs out!")
                }

                section("Scoring") {
                    Text("**+1** for each white square now in the path.")
                    Text("**−1** for each locked square.")
                    Text("**−1** for each white square left over.")
                    Text("Score zero or less and the next level will be on a tricky 4×4 grid.")
                }

                section("Bonuses") {
                    row("square.slash.fill", "**No whites left:** Leave no white squares outside the path for bonus points equal to the grid's rows plus columns. For example, both a 5x5 and 4x6 grid will give a bonus of 10 points.")
                    row("plus.square", "**Power-up reward:** If your score for a level is at least equal to the number of squares in the grid, you also get one of each power-up.")
                    row("star.fill", "**Star:** Catch the star in your path for an extra power-up. If your power-ups are all full, you get points equal to the level number instead; use this to get high scores later in the game!")
                }

                section("Power-ups") {
                    row("shuffle", "Flip all black and white squares at once.")
                    row("xmark", "Unlock a square you tapped.")
                    row("square.lefthalf.filled", "Flip one square without flipping those around it.")
                }
                
                Text("Black & White was created by Chris Wilson. It was originally written in Python using [Pythonista](https://apps.apple.com/gb/app/pythonista-3/id1085978097). The original repository can be found on [GitHub](https://github.com/chriswilson1982/black-and-white)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("How to Play")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title3.bold())
            content()
        }
    }

    /// A line with an icon, centred against the text however many lines it wraps to.
    /// `text` may use **bold** Markdown.
    private func row(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: symbol)
                .imageScale(.large)
                .frame(width: 32)
                .accessibilityHidden(true)
            Text(LocalizedStringKey(text))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
