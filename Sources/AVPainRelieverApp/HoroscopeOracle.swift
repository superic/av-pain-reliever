import Foundation

/// A curated catalog of brief oracular pronouncements rendered on
/// the small fortune-paper slip in the About window. Voice: mystical,
/// declarative, mostly universal — never about audio, cameras,
/// devices, docks, or anything in the app itself. The app reading
/// the user's mind about their hardware would feel surveillance-y;
/// the oracle should be as universal as a paper fortune from a
/// restaurant.
///
/// Selected once per About-window appearance via `random()`; held in
/// `@State` for the lifetime of that window so the slip doesn't
/// change while the user is reading it.
///
/// Adding entries: keep them short (1-2 lines at the slip's ~280pt
/// width with italic body-serif), declarative (not advice-giving),
/// and mostly universal. Avoid: politics, fortune-cookie clichés
/// you've seen on a billion paper slips, anything that names a
/// piece of hardware or software, anything that could read as
/// telling the user what they're feeling right now.
enum HoroscopeOracle {
    static let catalog: [String] = [
        "The longest journey begins with a step you didn't notice.",
        "Three small choices today will look like one large one in retrospect.",
        "What you have configured will configure you back.",
        "A path that fits perfectly is itself a kind of warning.",
        "The door you avoided yesterday is the one that opens easily tomorrow.",
        "A small kindness compounds at a rate the calendar cannot show.",
        "The conversation you did not have today will find another shape tomorrow.",
        "What you carry travels with you. What you put down travels too.",
        "The quiet between two thoughts is older than either of them.",
        "You will be patient about the wrong thing. Begin anyway.",
        "Three things will happen this week. You will mistake the second for the first.",
        "Forgiveness is a door that swings both ways.",
        "Some questions ripen. Some questions rot. Tell the difference by the smell.",
        "The next room is closer than you think and farther than you fear.",
        "A truth said quickly is rarely the whole truth.",
        "What looks like luck has been practicing for years.",
        "The hand that holds the pen does not write the letter.",
        "The future is not a place. It is a habit.",
        "Today, an old idea will return wearing new clothes.",
        "Rest is not the opposite of work. It is the secret part of it.",
        "The map cannot tell you which way to lean.",
        "You will surprise yourself by Tuesday. The good kind.",
        "A small lie kept warm becomes a large one.",
        "The thing you keep meaning to do will mean to do you back.",
        "Listen for the silence that follows the question.",
        "The bridge you are building is also building you.",
        "Some endings arrive as a whisper. Honor the whisper.",
        "The friend you have not called is calling you in a way you cannot hear.",
        "Light bends around what you refuse to look at.",
        "A simple meal eaten slowly is a kind of prayer.",
        "The river does not negotiate with the rock. It outlasts it.",
        "What you praise grows. What you ignore quietly grows too.",
        "The story you keep telling about yourself is the one you keep becoming.",
        "Curiosity is older than fear and tends to win on the long count.",
        "Today, choose the harder kindness over the easier comfort.",
        "What you can name, you can carry. What you cannot name, carries you.",
        "The wind has no opinion about which way you wanted to sail.",
        "Trust the second answer when the first one came too fast.",
        "You will need a new word for something old. It will arrive.",
        "The empty cup is a question. The full cup is one too.",
        "Some debts are paid by someone you will never meet.",
        "A small joy noticed is a large joy made.",
        "The thing you fear losing is teaching you what to keep.",
        "Begin where you are. The other beginnings are imaginary.",
        "The truth often arrives in clothing you would not have chosen for it.",
        "Kindness is not a soft thing. It has bones.",
        "What you measure changes. What you cannot measure changes too.",
        "The letter you wrote in your head does not count, but it counted.",
        "The future is asking you a question it has not yet phrased.",
        "You will be remembered for one thing you did not plan.",
    ]

    /// Returns one horoscope at random. Falls back to a stable
    /// string if the catalog is somehow empty so the slip never
    /// renders blank.
    static func random() -> String {
        catalog.randomElement() ?? "The future is asking you a question it has not yet phrased."
    }
}
