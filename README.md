# Black & White for iOS

A grid puzzle game for iPhone and iPad: clear a path of white squares across the grid before the clock runs out. Tapping a square locks it and flips the eight squares around it. Built with SpriteKit for the game and SwiftUI for everything around it. It's a native version of the original Black & White, which was written in Python with Pythonista.

## Running it

1. Open `BlackAndWhite.xcodeproj` in an Xcode with the **iOS 27 SDK**. The app still runs on **iOS 18 and later**.
2. Select the **BlackAndWhite** target → *Signing & Capabilities* and choose your team. The bundle identifier is `com.chriswilson.newblackandwhite`; change it if you're building under your own account.
3. Pick an iPhone or iPad and press **Run**. The game runs in portrait.

Run the unit tests with **Product → Test** (⌘U). They cover the grid rules, scoring and the solver (`BlackAndWhiteTests/BoardTests.swift`).

Debug builds show SpriteKit's frame rate, draw call, quad and node counters in the corner; release builds don't.

## Features

- **Home screen** with Play, high scores, settings, How to Play and the tutorial, over a moving mesh gradient of the game's colours.
- **Rounded islands:** in the rounded style, squares of the same colour join into smooth shapes. Corners round off where colours meet, diagonal neighbours join across, and black and locked squares form continuous walls.
- **Guided tutorial** played on the real game screen with a fixed practice board. Instruction cards sit on top, the clock is held, and only the tap each step asks for works. It runs on first launch and can be replayed from the home screen.
- **Power-ups:** flip every square, unlock a tapped square, or flip one square on its own.
- **Bonuses:** no white squares left outside the path, a power-up reward for big rounds, and a bonus star.
- **Colour schemes** (Classic, Ocean, Sunset, Forest, Neon, Pastel and Accessible, using colour-blind-friendly Okabe–Ito colours), plus pickers for full customisation, light/dark/automatic appearance and a configurable star colour.
- **Personal high scores** for each difficulty: your best and recent games, your Game Center best and worldwide rank, and a personal best synced across your devices with iCloud.
- Retro sound effects generated in code, haptics, and Reduce Motion support (fades instead of movement).

## Every grid can be won

When a round starts, the game checks that the grid can be won with normal taps alone (no power-ups) and re-rolls it if not. The check lives in `Board.solve()`:

- Squares on the winning path are never tapped, so each one is flipped once by every tapped neighbour, in any order.
- That turns "is there a path?" into a small set of XOR (GF(2)) equations, solved as a depth-first search builds the path out from the start square.
- The search has a step budget. A grid that runs out of budget counts as unproven and is re-rolled too (about 3% of the largest grids). That keeps the check to a few milliseconds.

## Rounded-island rendering

Each grid point inside the board looks at the four squares that meet there (`GameScene.shapeGridPoint`). A square's corner is rounded off when both squares beside it belong to a different island. The gap is filled by whichever island owns the point: a diagonal pair (joined across), else the colour with the most squares there, else a priority order with walls first. The owning square draws the fill as a small curved piece in its own colour, so it always matches, even mid-flip. Shapes are recalculated every frame, and textures are drawn at the screen's exact size and pixel density (`Game/Art.swift`) so curves stay smooth.

## Game Center

There is one leaderboard per difficulty. A score is submitted when a game ends with a score above zero. The high scores screen reads your best score, worldwide rank and date straight from GameKit, and has a button to open Game Center's full leaderboard.

Leaderboard IDs (set in `Support/GameCenter.swift`):

| Difficulty | Leaderboard ID |
| --- | --- |
| Easy | `com.chriswilson.blackandwhite.easy` |
| Regular | `com.chriswilson.blackandwhite.regular` |
| Hard | `com.chriswilson.blackandwhite.hard` |

### Setup in App Store Connect

1. **App ID:** the app's identifier needs **Game Center** and **iCloud** (key-value storage) enabled. With automatic signing, Xcode does this from `BlackAndWhite.entitlements`.
2. **App record:** create the app in App Store Connect with the same bundle ID.
3. **Leaderboards:** under *Services → Game Center → Leaderboards*, create three **Classic** leaderboards with the IDs above:
   - **Score format:** Integer.
   - **Order and submission:** sort High to Low, submission type Best Score.
   - **Localisation:** at least one, with a display name. Add one for your device's language too (e.g. English (UK) as well as English (U.S.)), otherwise titles show as "MISSING TITLE".
4. **Attach to the version:** in the app version's *Game Center* section, add all three leaderboards before submitting.
5. **Testing:** development builds use the Game Center sandbox as soon as the leaderboards exist; no uploaded binary is needed. Sign in on the device under Settings → Game Center.

If you use different leaderboard IDs, update `GameCenter.leaderboardID(for:)` to match.

### Achievements

27 achievements worth 825 of Game Center's 1,000 points, leaving 175 for adding more later. They're worked out in `Support/Achievements.swift` and don't count in the tutorial. Everything earned on a device is sent again at each Game Center sign-in, so nothing earned while signed out (or before an achievement was set up) is lost. In App Store Connect, under *Services → Game Center → Achievements*, each has the ID `com.chriswilson.blackandwhite.achievement.` followed by the suffix below, an image (1024×1024) and a localisation (title, plus descriptions before and after earning). Add them to the app version before submitting.

| ID suffix | Title | Description | Points |
| --- | --- | --- | --- |
| `score100` | Century | Score 100 in one game | 10 |
| `score250` | Rising Star | Score 250 in one game | 20 |
| `score500` | High Flyer | Score 500 in one game | 30 |
| `score1000` | Grandmaster | Score 1,000 in one game | 50 |
| `score1500` | Legend | Score 1,500 in one game | 75 |
| `score2000` | Unstoppable | Score 2,000 in one game | 100 |
| `hardScore500` | Hardcore | Score 500 in one game on Hard | 50 |
| `hardScore1000` | Diamond | Score 1,000 in one game on Hard | 80 |
| `level10` | Getting Going | Reach level 10 | 10 |
| `level20` | Into The Groove | Reach level 20 | 20 |
| `level30` | Against The Clock | Reach level 30 | 30 |
| `level40` | Nerves Of Steel | Reach level 40 | 40 |
| `level50` | Half Century | Reach level 50 | 50 |
| `noWhitesLeft` | Clean Sweep | Win a round with no white squares left over | 10 |
| `powerupReward` | Power Surge | Earn the power-up reward (no whites left, and a score of at least the grid size) | 20 |
| `starCollector` | Star Collector | Collect 100 stars over any number of games (shows progress) | 20 |
| `fullHouse` | Full House | Have 9 of every power-up at once | 30 |
| `starBonus` | Star Bonus | Collect a star for points with all power-ups full | 40 |
| `purist` | Purist | Reach level 10 without using a power-up | 20 |
| `trickyGrid` | Tricky Business | Win a tricky 4×4 penalty grid | 10 |
| `photoFinish` | Photo Finish | Win with under a second left | 10 |
| `noTapsNeeded` | Hands Free | Win a round without tapping a square or using a power-up | 10 |
| `oneTapWonder` | One Tap Wonder | Win a round with a single tap and no power-ups | 20 |
| `goodbyeStar` | Goodbye Star | **Hidden.** Destroy a star by tapping its square | 10 |
| `score0` | Sweet Nothing | **Hidden.** End a game with a score of zero or less | 20 |
| `zero` | Zero In | **Hidden.** Score exactly zero in a level | 20 |
| `goingDown` | Going Down | **Hidden.** Score below zero in a level | 20 |

Points and titles here match App Store Connect, where they're set; the code only needs the IDs to match.

## iCloud

Your best score at each difficulty, and when you set it, is kept in iCloud key-value storage (`NSUbiquitousKeyValueStore`, in `Support/HighScoreStore.swift`). Devices merge on launch and whenever another device changes it, always keeping the highest. The full game history stays on each device. Without iCloud, everything still works locally.

## Project layout

| Folder / file | What's there |
| --- | --- |
| `Game/Board.swift` | Grid rules, path check, scoring and the solver (no UI code) |
| `Game/GameScene.swift` | The SpriteKit game: layout, input, rounds, animation, corner rounding, tutorial mode |
| `Game/Nodes.swift` | Squares, power-up buttons and the timer |
| `Game/Art.swift` | Textures drawn in code: rounded squares, corner fills, the star, SF Symbol icons |
| `Game/Messages.swift` | The game's messages |
| `Support/GameSettings.swift` | Settings and colour schemes, saved in UserDefaults |
| `Support/HighScoreStore.swift` | Game history (JSON file) and iCloud-synced bests |
| `Support/GameCenter.swift` | Sign-in, score submission and leaderboard queries |
| `Support/SoundEngine.swift` | Retro sound effects synthesised at launch |
| `Views/ContentView.swift`, `GameCoordinator.swift` | App screen and the glue between the game and SwiftUI |
| `Views/HomeView.swift` | Home screen and the How to Play sheet |
| `Views/GameBackground.swift` | Mesh gradient background |
| `Views/TutorialView.swift` | The guided tutorial |
| `Views/SettingsView.swift`, `HighScoresView.swift`, `HelpView.swift` | Settings, high scores and help |

## Credits

Created by Chris Wilson, originally in Python using Pythonista.
