import CoreGraphics
import Foundation

// THE SHELL CATALOG.
//
// Each entry is a shell she could tell apart from every other one — see the
// note in `Firework.swift` for why this is not a hundred permutations of
// fourteen shapes.
//
// An entry differs from its siblings in at least one STRUCTURAL way: the break
// pattern, the flight, whether the stars split or twinkle, how long they hang,
// or the register it whirrs and blooms in. Colour is the last axis, never the
// only one — a recolouring is not a different firework.
struct FireworkDefinition: Identifiable, Equatable {
    let id: Int
    let name: String
    let kind: FireworkKind
    /// One calm line, in the fortune voice, for the journal.
    let flavor: String

    /// Its own paints. Fireworks do not borrow the pops' palette: a shell
    /// should not look like an orb that learned to fly.
    let paints: [PopPaint]

    /// Multiplier on the shell's hang time.
    let hang: CGFloat
    /// Pitch of the whirr as it climbs, in Hz at the start of the rise.
    let whirr: Double
    /// The voice its bloom is sounded with.
    let bloom: SoundVoice

    var burst: FireworkBurst {
        var spec = kind.burst
        spec.life *= hang
        return spec
    }
}

enum FireworkCatalog {

    static let all: [FireworkDefinition] = entries
    static let byID: [Int: FireworkDefinition] =
        Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static func definition(for id: Int) -> FireworkDefinition {
        byID[id] ?? all[0]
    }

    /// Shells whose paints and behaviour suit a given family, so a display on
    /// the ember road looks like the ember road.
    static func forFamily(_ family: PopFamily?) -> [FireworkDefinition] {
        guard let family else { return all }
        let band = familyBands[family] ?? []
        let matching = all.filter { band.contains($0.kind) }
        return matching.isEmpty ? all : matching
    }

    /// Which break patterns belong to which road. Every family gets at least
    /// three, so a display is never the same two shells over and over.
    private static let familyBands: [PopFamily: Set<FireworkKind>] = [
        .vesper:  [.peony, .chrysanthemum, .ring],
        .ember:   [.crackle, .fountain, .comet, .palm],
        .tide:    [.willow, .horsetail, .brocade],
        .bloom:   [.peony, .crossette, .palm],
        .frost:   [.crackle, .strobe, .ring],
        .chime:   [.strobe, .ring, .peony],
        .lantern: [.fountain, .horsetail, .willow],
        .current: [.serpent, .spinner, .comet],
        .prism:   [.crossette, .spinner, .crackle],
        .aurora:  [.willow, .brocade, .strobe],
    ]

    // MARK: - Paints
    //
    // Firework palettes: hotter and more luminous than the pops', because a
    // thing in the air at night IS brighter than a thing on a table — but
    // still inside the muted band. Nothing saturated, nothing pure white.

    private static func p(_ r: Double, _ g: Double, _ b: Double,
                          _ gr: Double, _ gg: Double, _ gb: Double) -> PopPaint {
        PopPaint(fill: PopColor(r: r / 255, g: g / 255, b: b / 255),
                 glow: PopColor(r: gr / 255, g: gg / 255, b: gb / 255))
    }

    private static let gold    = [p(240, 222, 178, 236, 200, 130)]
    private static let ember   = [p(240, 190, 160, 232, 150, 110)]
    private static let rose    = [p(240, 200, 210, 232, 165, 185)]
    private static let lilac   = [p(216, 200, 238, 195, 170, 232)]
    private static let sage    = [p(198, 226, 212, 168, 210, 190)]
    private static let ice     = [p(214, 230, 244, 180, 210, 240)]
    private static let cream   = [p(244, 238, 224, 236, 226, 200)]
    private static let sea     = [p(186, 218, 226, 150, 198, 214)]
    private static let dusk    = [p(206, 196, 224, 176, 164, 210)]
    private static let honey   = [p(238, 214, 168, 230, 190, 120)]

    private static func def(_ id: Int, _ name: String, _ kind: FireworkKind,
                            _ paints: [PopPaint], hang: CGFloat = 1,
                            whirr: Double = 300, bloom: SoundVoice = .breath,
                            _ flavor: String) -> FireworkDefinition {
        FireworkDefinition(id: id, name: name, kind: kind, flavor: flavor,
                           paints: paints, hang: hang, whirr: whirr, bloom: bloom)
    }

    // MARK: - The entries

    private static let entries: [FireworkDefinition] = [
        // Peony — the archetype, clean and round.
        def(1,  "evening peony",   .peony, gold,  hang: 1.0, whirr: 300, bloom: .breath,
            "The first one is always the one you remember."),
        def(2,  "pale peony",      .peony, ice,   hang: 1.3, whirr: 340, bloom: .shimmer,
            "It opens slowly, as if deciding."),
        def(3,  "low peony",       .peony, ember, hang: 0.7, whirr: 240, bloom: .wood,
            "Close enough to hear the paper."),

        // Chrysanthemum — the same sphere, drawn in lines.
        def(4,  "chrysanthemum",   .chrysanthemum, honey, hang: 1.0, whirr: 310, bloom: .breath,
            "Every star leaves a thread behind it."),
        def(5,  "silver mum",      .chrysanthemum, ice,   hang: 1.4, whirr: 360, bloom: .glass,
            "Cold light, and plenty of it."),
        def(6,  "dusk mum",        .chrysanthemum, dusk,  hang: 1.1, whirr: 270, bloom: .shimmer,
            "The colour of the hour it belongs to."),

        // Willow — the quietest shell there is.
        def(7,  "willow",          .willow, gold,  hang: 1.5, whirr: 250, bloom: .breath,
            "It comes down more slowly than it went up."),
        def(8,  "green willow",    .willow, sage,  hang: 1.7, whirr: 230, bloom: .shimmer,
            "Long, soft, and in no hurry at all."),
        def(9,  "ghost willow",    .willow, cream, hang: 2.0, whirr: 210, bloom: .breath,
            "Barely there, and then not."),

        // Palm — trunk and branches.
        def(10, "palm",            .palm, honey, hang: 1.2, whirr: 260, bloom: .wood,
            "It grows, which is not what fire usually does."),
        def(11, "ember palm",      .palm, ember, hang: 1.0, whirr: 240, bloom: .crackle,
            "Thick branches, and a few sparks that stay."),

        // Crossette — stars that break again.
        def(12, "crossette",       .crossette, cream, hang: 0.9, whirr: 330, bloom: .glass,
            "It thinks better of itself halfway out."),
        def(13, "rose crossette",  .crossette, rose,  hang: 1.1, whirr: 350, bloom: .bell,
            "Four smaller ideas from one."),

        // Ring — the flat band.
        def(14, "ring",            .ring, ice,   hang: 1.0, whirr: 320, bloom: .bell,
            "A perfect circle, briefly."),
        def(15, "double ring",     .ring, lilac, hang: 1.3, whirr: 300, bloom: .glass,
            "One inside the other, almost."),
        def(16, "sea ring",        .ring, sea,   hang: 1.1, whirr: 280, bloom: .shimmer,
            "It opens like something under water."),

        // Comet — one streak that keeps going.
        def(17, "comet",           .comet, gold,  hang: 1.4, whirr: 380, bloom: .breath,
            "It has somewhere to be."),
        def(18, "blue comet",      .comet, ice,   hang: 1.6, whirr: 420, bloom: .glass,
            "Cold and fast and gone."),

        // Fountain — the one that stays down.
        def(19, "fountain",        .fountain, honey, hang: 1.0, whirr: 200, bloom: .crackle,
            "It never leaves the ground and does not mind."),
        def(20, "silver fountain", .fountain, ice,   hang: 1.2, whirr: 220, bloom: .glass,
            "A small bright argument with gravity."),

        // Crackle — many small breaks.
        def(21, "crackle",         .crackle, cream, hang: 0.6, whirr: 340, bloom: .crackle,
            "A hundred small sounds at once."),
        def(22, "ember crackle",   .crackle, ember, hang: 0.7, whirr: 300, bloom: .crackle,
            "Like a fire settling, but upward."),
        def(23, "frost crackle",   .crackle, ice,   hang: 0.5, whirr: 400, bloom: .glass,
            "Sharp, quick, and cold."),

        // Strobe — points that come and go.
        def(24, "strobe",          .strobe, cream, hang: 1.6, whirr: 310, bloom: .shimmer,
            "It cannot decide whether to be there."),
        def(25, "lilac strobe",    .strobe, lilac, hang: 1.8, whirr: 290, bloom: .bell,
            "Slow blinking, like something far away."),
        def(26, "sea strobe",      .strobe, sea,   hang: 1.5, whirr: 270, bloom: .shimmer,
            "Light on water, from above."),

        // Spinner — throws stars off its own turn.
        def(27, "spinner",         .spinner, gold,  hang: 1.0, whirr: 350, bloom: .breath,
            "It writes something on the way up."),
        def(28, "rose spinner",    .spinner, rose,  hang: 1.2, whirr: 330, bloom: .bell,
            "Round and round, and then open."),

        // Serpent — the erratic climb.
        def(29, "serpent",         .serpent, sage,  hang: 0.9, whirr: 290, bloom: .breath,
            "It takes the long way, for its own reasons."),
        def(30, "ember serpent",   .serpent, ember, hang: 1.0, whirr: 260, bloom: .crackle,
            "Nobody has ever been able to follow one."),

        // Brocade — the finale shell.
        def(31, "brocade",         .brocade, honey, hang: 1.6, whirr: 240, bloom: .breath,
            "The one they save for last."),
        def(32, "pale brocade",    .brocade, cream, hang: 1.9, whirr: 220, bloom: .shimmer,
            "It fills the whole sky and then lets it go."),
        def(33, "dusk brocade",    .brocade, dusk,  hang: 1.7, whirr: 200, bloom: .wood,
            "Heavy, warm, and slow to leave."),

        // Horsetail — barely rises, falls at once.
        def(34, "horsetail",       .horsetail, gold,  hang: 1.2, whirr: 210, bloom: .wood,
            "It falls almost as soon as it opens."),
        def(35, "rose horsetail",  .horsetail, rose,  hang: 1.4, whirr: 230, bloom: .drop,
            "Heavy stars, and a soft landing."),
        def(36, "sea horsetail",   .horsetail, sea,   hang: 1.3, whirr: 250, bloom: .drop,
            "Everything comes down eventually."),
    ]
}
