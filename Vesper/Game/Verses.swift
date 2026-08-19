import Foundation

// The line that sits under "the field is quiet now." on the done card.
//
// WHY THESE ARE ORIGINAL AND UNATTRIBUTED. The owner asked for poetry
// excerpts and said, when the copyright problem was raised, to make them up
// if needed. Making them up is not the fallback here — it is the correct
// answer, for two reasons that both matter:
//
//   * Nearly all poetry a reader of this age would recognise is under
//     copyright. Shipping excerpts of it would be infringement, and the
//     public-domain subset that is safe is largely Victorian, which does not
//     sound like this game.
//   * The alternative — inventing lines and putting a real poet's name under
//     them — is worse than infringement. It misattributes work to people who
//     did not write it, and it is the kind of thing that outlives an apology.
//
// So: written for Vesper, credited to nobody, and never presented as anything
// else. There is no byline on the card and there is not going to be one.
//
// THE VOICE. Sentence case, like the fortunes and unlike the UI (07 §2's
// stated exception). One or two short lines. An image rather than a
// statement, and never an instruction — nothing here tells her to rest, to
// breathe, to let go, or to be kind to herself. She has just finished a quiet
// thing at the end of a long day; being told what to feel about it is the one
// way this could go wrong. The line observes something small, and stops.
//
// The bar for a new line: read it at 1 a.m. in a kitchen, tired, unable to
// sleep. If it asks anything of her, it is cut.
enum Verses {

    /// Drawn without repeats until the set is exhausted (see `Deck`).
    static let all: [String] = light + water + weather + night + small + time + growing

    // MARK: - Light

    private static let light: [String] = [
        "The lamp finds the corner it always finds.",
        "Afternoon comes in sideways and stays a while.",
        "There is a gold hour in every room, if you wait for it.",
        "Light collects in the shallow dish by the window.",
        "The morning arrives without needing to be noticed.",
        "Something bright is resting on the floorboards.",
        "A candle does most of its work after it is out.",
        "The window keeps a little of the day in it.",
        "Dust turns slowly through the last of the sun.",
        "The room is warmer for having been sat in.",
        "Everything looks softer from across the room.",
        "A single lit window is enough to steer by.",
        "The shine on the kettle is doing nothing in particular.",
        "Late light makes an ordinary wall worth looking at.",
        "The shadow of the chair has moved and said nothing.",
        "Somewhere a curtain is letting the morning in slowly.",
        "The glass holds more light than it needs to.",
        "There is a brightness that arrives only when it is quiet.",
        "The hallway is lit by a door left open somewhere.",
        "Evening puts its hand on everything at once.",
        "A lit window in the distance is a kind of company.",
        "The last of the sun leans against the wall.",
        "Light does not knock. It simply arrives.",
        "The room remembers the lamp after it is switched off.",
        "Warmth comes through the glass long after the sun has gone.",
        "There is a whole hour that belongs to no one.",
        "The ceiling has a pale square on it, and then it does not.",
        "Something gold is happening on the far side of the room.",
        "The morning is patient with the corners it has not reached.",
        "A held glass catches the window without meaning to.",
    ]

    // MARK: - Water

    private static let water: [String] = [
        "The kettle settles and the room settles with it.",
        "Rain finds the one loose gutter and plays it all night.",
        "The glass sweats gently onto the table.",
        "A drop travels the length of the window and arrives.",
        "The tide has been doing this for a very long time.",
        "Steam leaves the cup without being asked.",
        "The river is not going anywhere it has not been.",
        "Rain on a roof is the oldest lullaby there is.",
        "The bath goes still the moment you stop moving.",
        "Something has settled to the bottom and stayed there.",
        "Water finds the low place and rests in it.",
        "The lake is holding the whole sky and not straining.",
        "A puddle keeps the streetlight all night.",
        "The tap drips at the speed of thinking.",
        "Rain arrives and the day gets smaller and kinder.",
        "The sea puts everything back where it found it.",
        "A cup of tea is warm for exactly long enough.",
        "The rain stops and the roof keeps going a little longer.",
        "Ice gives in slowly and without complaint.",
        "The pond has closed over whatever was dropped in it.",
        "Water is patient in a way that looks like doing nothing.",
        "The fog is only a cloud that came down to see.",
        "A stream goes around the stone rather than through it.",
        "The washing-up water goes quiet when it is left.",
        "Somewhere a wave is arriving with no one to see it.",
        "The window is beaded and the room is dry.",
        "Rain makes the whole street sound closer.",
        "The well is deeper than the bucket ever goes.",
        "A slow drip is not a problem tonight.",
        "The kettle's small roar, and then its small silence.",
    ]

    // MARK: - Weather

    private static let weather: [String] = [
        "Snow makes the whole street speak more softly.",
        "The wind has been through the trees and moved on.",
        "There is weather happening to somebody else's window.",
        "The first cold day arrives and everyone mentions it.",
        "Leaves go where they are going without deciding.",
        "The storm passes over and takes its noise with it.",
        "Warm air comes in and the house lets its shoulders down.",
        "Frost has drawn on the glass and asked for nothing.",
        "The sky has been grey all day and meant no harm.",
        "A breeze moves the curtain and then does not.",
        "Autumn takes its time undressing the trees.",
        "The air smells like rain that has not arrived.",
        "Wind in a chimney is an old sound in a new house.",
        "The snow is level with everything it has covered.",
        "Clouds go by in no particular order.",
        "It is raining somewhere within earshot.",
        "The heat has gone out of the day and left the light.",
        "A branch moves, and then all of them do.",
        "The garden is wet and pleased about it.",
        "Weather is the world thinking out loud.",
        "There is a warm patch and a cold patch in every room.",
        "The last leaf is in no rush.",
        "A grey morning is still a morning.",
        "The wind drops and the whole field notices.",
        "Fog keeps the distance to a comfortable size.",
    ]

    // MARK: - Night

    private static let night: [String] = [
        "The house makes its small night sounds and settles.",
        "Nothing is expected of anyone at this hour.",
        "The street is doing very little and doing it well.",
        "Late is only early on the other side.",
        "The dark outside makes the room a room.",
        "Somebody else's light goes off across the way.",
        "The clock is going, and that is all it is doing.",
        "The day has put itself down.",
        "There is no traffic and no reason for any.",
        "Sleep will find its own way here.",
        "The night is wide and there is room in it.",
        "The last bus has gone and it does not matter.",
        "Everything has stopped asking.",
        "The dark is not empty, only unlit.",
        "The window has become a mirror and shows the room.",
        "Stars are old light that arrived tonight.",
        "The city is a low hum and nothing more.",
        "A dog barks twice, somewhere, and thinks better of it.",
        "The hallway light is enough for now.",
        "Tomorrow has not started and cannot be hurried.",
        "The pillow is cool on the other side.",
        "There is nobody who needs finding tonight.",
        "The moon has been up for hours without mentioning it.",
        "This hour belongs to whoever is awake in it.",
        "The heating clicks off and the quiet gets deeper.",
    ]

    // MARK: - Small things

    private static let small: [String] = [
        "The book is face down and holding its place.",
        "The chair keeps the shape of whoever sat in it.",
        "A cup, a spoon, and nothing else required.",
        "The coat still has the cold on it.",
        "Somebody folded this and put it here.",
        "The bread is out and the day can begin.",
        "There is a spare key in a dish somewhere.",
        "The plant has turned itself toward the window again.",
        "A photograph gets more true as it fades.",
        "The wooden spoon has been here longer than most things.",
        "Every house has one drawer that means well.",
        "The blanket is exactly heavy enough.",
        "A worn step is the record of everyone who used it.",
        "The jar was kept for a reason nobody remembers.",
        "There is bread and there is butter and that is dinner.",
        "The mug with the chip is the one that gets used.",
        "Socks on a radiator is a whole kind of hope.",
        "Someone left the good chair facing the window.",
        "The letter can be answered tomorrow.",
        "A pencil that has been sharpened many times.",
        "The doorframe has pencil marks and dates on it.",
        "This shirt has been washed a thousand times and is still here.",
        "The bowl holds whatever is put in it, without preference.",
        "A key turns and the day is over.",
        "The kitchen tidies itself if you give it ten minutes.",
    ]

    // MARK: - Time

    private static let time: [String] = [
        "The week has been long and is nearly not.",
        "Some days are for getting through, and that counts.",
        "It was heavy this morning and it is lighter now.",
        "Nothing needed deciding today after all.",
        "The list will still be there and will still be short.",
        "Whatever it was, it kept.",
        "Today did not require anything remarkable.",
        "There will be another one of these tomorrow.",
        "The hard part was earlier and it is not now.",
        "An hour ago is already a long time ago.",
        "It gets easier and then it gets easy.",
        "The thing that seemed urgent has gone quiet.",
        "Enough was done. That is the whole report.",
        "It will look different in the morning, as it always does.",
        "The month is turning and taking things with it.",
        "Slowly is still a speed.",
        "Nothing is behind schedule tonight.",
        "The year is going along without being pushed.",
        "Some evenings are only for ending the day.",
        "There is no version of this that had to be faster.",
        "What was left undone is still only undone.",
        "This is the part where nothing happens, and it is the best part.",
        "The waiting is over and nothing came of it, happily.",
        "It is later than it was, which is all it ever is.",
        "Rest is not a reward. It is just next.",
    ]

    // MARK: - Growing

    private static let growing: [String] = [
        "The garden did most of it without supervision.",
        "Something is coming up that was not planted.",
        "The tree is older than the house and says nothing about it.",
        "Roots go where the water is and take their time.",
        "The moss has taken the north side, as agreed.",
        "A seed is patient in a way that looks like nothing.",
        "The hedge has ideas of its own again.",
        "Things grow at night too.",
        "The apple falls when the apple is ready.",
        "There is green coming through the paving stones.",
        "Nothing in the garden is trying to impress anyone.",
        "The ivy has made the wall its own business.",
        "A cut stem in water will try anyway.",
        "The oldest tree here started as an accident.",
        "Growth is mostly waiting, from the outside.",
        "The bulbs are down there doing it in the dark.",
        "The field has been left alone and is doing well.",
        "Everything green began by pushing against something.",
        "The vine found the trellis without being shown.",
        "It is enough for a thing to be growing quietly.",
    ]

    // MARK: - Drawing

    /// Draws without repeating until the whole set has been seen.
    ///
    /// A repeat inside one evening is the failure that matters here — it turns
    /// a small gift into a slot machine — so this is a shuffled deck rather
    /// than a random pick.
    struct Deck {
        private var remaining: [String] = []
        private var rng = SystemRandomNumberGenerator()

        init() {}

        mutating func next() -> String {
            if remaining.isEmpty {
                remaining = Verses.all.shuffled(using: &rng)
            }
            return remaining.popLast() ?? ""
        }
    }
}
