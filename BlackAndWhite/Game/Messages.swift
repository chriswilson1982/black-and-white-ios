import Foundation

/// In-game messages, carried over from the original config.ini and extended.
/// Kept short (under about 30 characters) so they fit on one line on the smallest phones.
enum Messages {
    static let win = [
        "Well done!", "Nice one!", "Keep going!", "Excellent!", "More points!",
        "Ready for another?", "Good work!", "Congratulations!", "Brilliant!",
        "Great path!", "Path cleared!", "On a roll!", "Nicely done!", "Smooth!",
        "That's the way!", "Sharp thinking!",
    ]
    static let fail = [
        "Not so good!", "All things come to an end!", "Better luck next time!", "Game over!",
        "Unlucky or unskilled?", "Unlucky!", "Dead end!", "No way through!",
        "The grid wins this time!", "Back to the start!", "So close… or not?",
    ]
    static let zero = [
        "Pointless!", "Zero score!", "Sweet nothing!", "Exactly zero? Wow!", "Big fat nothing!", "Zero!",
        "Nothing gained!", "Perfectly balanced!", "Zero, zilch, nada!",
    ]
    static let negative = [
        "You lost points!", "You're going backwards!", "A higher score is better!",
        "Going down?", "That's not sustainable!", "Into the red!", "Less is not more!",
    ]
    static let noWhite = ["White square bonus!", "Clean sweep!", "Not a white square left!", "Spotless!"]
    static let reward = ["Power-up bonus!", "Power-ups all round!", "One of each power-up!"]
    static let punishment = [
        "Time for a tiny grid!", "Small and tricky!", "Time for 4×4 action!", "Small but beautiful!",
        "Tiny grid, big test!", "Think small!",
    ]
    static let hurry = [
        "Hurry up!", "The clock is ticking!", "There's not much time!", "Don't panic!",
        "Quick!", "Time's nearly up!", "Tick tock!",
    ]
    static let zeroFail = ["Finish where you started!", "You finish with nothing!", "Back where you began!"]
    static let negativeFail = ["We don't record negative scores!", "Below zero? Ouch!", "That's one way to play!"]
    static let quickFail = [
        "Fell at the first hurdle!", "Quickest fail ever!", "Over before it began!", "Level 1 wins this time!",
    ]

    static func pick(_ list: [String]) -> String {
        list.randomElement() ?? ""
    }
}
