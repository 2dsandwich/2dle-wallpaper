import AppKit
import SceneKit
import simd

/// The books on the library's shelves. Every one is a real book, and no two are the same:
/// sets and series stand together in order, each volume with its own spine.
enum Bookshelf {
    enum Binding { case cloth, leather, paperback, jacket }

    struct Volume {
        let title: String, author: String
        let binding: Binding
        let colour: (CGFloat, CGFloat, CGFloat)
        let thick: Float, height: Float, depth: Float
        /// The number on the spine of one of a set ("III"), if it carries one.
        let number: String?
        /// Which typeface and ornament this run of books shares.
        let design: Int
        /// Kept lying on its side in a small pile, front board up.
        var flat = false
        /// Has fallen over to the left against the books before it, so its front board shows.
        var leans = false
    }

    private static let roman = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]

    static let catalogue: [Volume] = {
        var all: [Volume] = []
        var design = 0
        func run(
            _ author: String, _ titles: [String], _ binding: Binding, _ colour: (CGFloat, CGFloat, CGFloat),
            thick: Float, height: Float, numbered: Bool = false, flat: Bool = false
        ) {
            design += 1
            let depth: Float = binding == .paperback ? 0.110 : (binding == .jacket ? 0.150 : 0.140)
            for (k, title) in titles.enumerated() {
                // (A set is cut to one size; odd volumes of one author vary a little.)
                let wobble = Float((k * 7 + design * 3) % 5) * 0.0016
                all.append(
                    Volume(
                        title: title, author: author, binding: binding, colour: colour,
                        thick: thick + (numbered ? 0 : wobble), height: height, depth: depth,
                        number: numbered ? roman[k % roman.count] : nil, design: design, flat: flat,
                        leans: k == 0 && !flat && !numbered && design % 3 == 1))
            }
        }
        func set(
            _ author: String, _ title: String, volumes: Int, _ binding: Binding, _ colour: (CGFloat, CGFloat, CGFloat),
            thick: Float, height: Float
        ) {
            run(
                author, Array(repeating: title, count: volumes), binding, colour, thick: thick, height: height,
                numbered: true)
        }
        // Upper shelf: the sets.
        run(
            "Conan Doyle",
            [
                "A Study in Scarlet", "The Sign of Four", "The Adventures of Sherlock Holmes",
                "The Memoirs of Sherlock Holmes", "The Hound of the Baskervilles",
                "The Return of Sherlock Holmes", "The Valley of Fear", "His Last Bow",
                "The Case-Book of Sherlock Holmes",
            ], .cloth, (0.34, 0.08, 0.07), thick: 0.026, height: 0.205)
        set(
            "Gibbon", "The Decline and Fall of the Roman Empire", volumes: 6, .leather, (0.20, 0.12, 0.07),
            thick: 0.043, height: 0.232)
        run(
            "Jane Austen",
            [
                "Sense and Sensibility", "Pride and Prejudice", "Mansfield Park", "Emma", "Northanger Abbey",
                "Persuasion",
            ], .cloth, (0.11, 0.22, 0.15), thick: 0.027, height: 0.198)
        set("Tolstoy", "War and Peace", volumes: 4, .cloth, (0.09, 0.15, 0.26), thick: 0.036, height: 0.215)
        run(
            "Tolstoy", ["Anna Karenina", "Resurrection", "Childhood, Boyhood, Youth"], .cloth, (0.09, 0.15, 0.26),
            thick: 0.038, height: 0.215)
        run(
            "Dickens",
            [
                "The Pickwick Papers", "Oliver Twist", "Nicholas Nickleby", "David Copperfield", "Bleak House",
                "Hard Times", "Little Dorrit", "A Tale of Two Cities",
                "Great Expectations", "Our Mutual Friend",
            ], .leather, (0.36, 0.10, 0.08), thick: 0.040, height: 0.222)
        run(
            "Proust",
            [
                "Swann's Way", "Within a Budding Grove", "The Guermantes Way", "Sodom and Gomorrah", "The Captive",
                "The Fugitive", "Time Regained",
            ], .cloth, (0.62, 0.56, 0.44), thick: 0.031, height: 0.208)
        run("Dante", ["Inferno", "Purgatorio", "Paradiso"], .leather, (0.10, 0.10, 0.11), thick: 0.030, height: 0.226)
        run(
            "Dostoevsky",
            ["Notes from Underground", "Crime and Punishment", "The Idiot", "Demons", "The Brothers Karamazov"], .cloth,
            (0.28, 0.12, 0.19), thick: 0.036, height: 0.212)
        run(
            "Dumas",
            ["The Three Musketeers", "Twenty Years After", "The Vicomte de Bragelonne", "The Count of Monte Cristo"],
            .cloth, (0.40, 0.16, 0.06), thick: 0.041, height: 0.218)
        set("Victor Hugo", "Les Misérables", volumes: 3, .leather, (0.10, 0.25, 0.27), thick: 0.040, height: 0.228)
        run(
            "Trollope",
            [
                "The Warden", "Barchester Towers", "Doctor Thorne", "Framley Parsonage", "The Small House at Allington",
                "The Last Chronicle of Barset",
            ], .cloth, (0.45, 0.33, 0.18), thick: 0.030, height: 0.200)
        run(
            "Shakespeare", ["Comedies", "Histories", "Tragedies", "Sonnets and Poems"], .leather, (0.16, 0.20, 0.30),
            thick: 0.046, height: 0.236)
        run("Homer", ["The Iliad", "The Odyssey"], .cloth, (0.52, 0.38, 0.12), thick: 0.034, height: 0.214, flat: true)
        run("Virgil", ["The Aeneid"], .cloth, (0.52, 0.38, 0.12), thick: 0.030, height: 0.214)
        run("Ovid", ["Metamorphoses"], .cloth, (0.52, 0.38, 0.12), thick: 0.032, height: 0.214)
        run(
            "The Brontës", ["Jane Eyre", "Villette", "Wuthering Heights", "The Tenant of Wildfell Hall"], .cloth,
            (0.20, 0.17, 0.12), thick: 0.032, height: 0.202)
        run(
            "George Eliot", ["Adam Bede", "The Mill on the Floss", "Silas Marner", "Middlemarch", "Daniel Deronda"],
            .cloth, (0.10, 0.25, 0.27), thick: 0.035, height: 0.206)
        run(
            "Thomas Hardy",
            [
                "Far from the Madding Crowd", "The Return of the Native", "Tess of the d'Urbervilles",
                "Jude the Obscure",
            ], .cloth, (0.11, 0.22, 0.15), thick: 0.030, height: 0.204)
        run("Melville", ["Typee", "Moby-Dick", "Billy Budd"], .cloth, (0.09, 0.15, 0.26), thick: 0.034, height: 0.220)
        run(
            "Mark Twain",
            ["The Adventures of Tom Sawyer", "Adventures of Huckleberry Finn", "Life on the Mississippi"], .cloth,
            (0.45, 0.33, 0.18), thick: 0.030, height: 0.210)
        run(
            "Balzac", ["Eugénie Grandet", "Père Goriot", "Lost Illusions", "Cousin Bette"], .leather,
            (0.34, 0.08, 0.07), thick: 0.032, height: 0.216)
        run(
            "Zola", ["Thérèse Raquin", "L'Assommoir", "Nana", "Germinal"], .leather, (0.20, 0.17, 0.12), thick: 0.032,
            height: 0.216)
        run(
            "Chekhov", ["Stories", "Plays", "Letters"], .cloth, (0.62, 0.56, 0.44), thick: 0.033, height: 0.208,
            flat: true)
        run("Gogol", ["Dead Souls"], .cloth, (0.28, 0.12, 0.19), thick: 0.030, height: 0.208)
        run("Turgenev", ["Fathers and Sons"], .cloth, (0.28, 0.12, 0.19), thick: 0.024, height: 0.208)
        // Lower shelf, in the middle where the hand goes first: the books about records and the people who made them...
        run(
            "Peter Guralnick", ["Last Train to Memphis", "Careless Love", "Sweet Soul Music"], .jacket,
            (0.10, 0.10, 0.11), thick: 0.040, height: 0.234)
        run("Bob Dylan", ["Chronicles: Volume One"], .jacket, (0.78, 0.74, 0.64), thick: 0.026, height: 0.226)
        run("Patti Smith", ["Just Kids", "M Train"], .jacket, (0.90, 0.88, 0.82), thick: 0.024, height: 0.214)
        run("Keith Richards", ["Life"], .jacket, (0.10, 0.10, 0.11), thick: 0.042, height: 0.236)
        run("Miles Davis", ["Miles: The Autobiography"], .jacket, (0.12, 0.20, 0.44), thick: 0.034, height: 0.230)
        run(
            "Alex Ross", ["The Rest Is Noise", "Listen to This"], .jacket, (0.70, 0.16, 0.12), thick: 0.040,
            height: 0.234)
        run("David Byrne", ["How Music Works"], .jacket, (0.92, 0.90, 0.86), thick: 0.032, height: 0.226)
        run(
            "Simon Reynolds", ["Rip It Up and Start Again", "Energy Flash", "Retromania"], .jacket, (0.92, 0.78, 0.10),
            thick: 0.036, height: 0.232)
        run("Jon Savage", ["England's Dreaming"], .jacket, (0.86, 0.30, 0.50), thick: 0.040, height: 0.232)
        run(
            "Greil Marcus", ["Mystery Train", "Lipstick Traces"], .jacket, (0.16, 0.16, 0.18), thick: 0.030,
            height: 0.228)
        run(
            "Michael Azerrad", ["Our Band Could Be Your Life"], .jacket, (0.82, 0.80, 0.74), thick: 0.036, height: 0.228
        )
        run("McNeil & McCain", ["Please Kill Me"], .jacket, (0.74, 0.10, 0.10), thick: 0.032, height: 0.224)
        run("Ian MacDonald", ["Revolution in the Head"], .jacket, (0.20, 0.36, 0.56), thick: 0.032, height: 0.224)
        run("Jeff Chang", ["Can't Stop Won't Stop"], .jacket, (0.90, 0.52, 0.08), thick: 0.038, height: 0.228)
        run(
            "Ted Gioia", ["The History of Jazz", "Delta Blues"], .jacket, (0.14, 0.26, 0.34), thick: 0.038,
            height: 0.234)
        run(
            "Lester Bangs", ["Psychotic Reactions and Carburetor Dung"], .jacket, (0.86, 0.82, 0.30), thick: 0.030,
            height: 0.220)
        run("Nick Hornby", ["High Fidelity", "31 Songs"], .jacket, (0.16, 0.46, 0.50), thick: 0.024, height: 0.214)
        run("Oliver Sacks", ["Musicophilia"], .jacket, (0.30, 0.20, 0.44), thick: 0.032, height: 0.228)
        run("Daniel Levitin", ["This Is Your Brain on Music"], .jacket, (0.92, 0.90, 0.86), thick: 0.028, height: 0.224)
        run("Brian Eno", ["A Year with Swollen Appendices"], .jacket, (0.84, 0.60, 0.66), thick: 0.034, height: 0.218)
        run("Questlove", ["Mo' Meta Blues"], .jacket, (0.10, 0.10, 0.11), thick: 0.028, height: 0.226, flat: true)
        run(
            "Viv Albertine", ["Clothes, Music, Boys"], .jacket, (0.92, 0.90, 0.86), thick: 0.030, height: 0.222,
            flat: true)
        run("Peter Hook", ["Unknown Pleasures"], .jacket, (0.06, 0.06, 0.07), thick: 0.030, height: 0.226, flat: true)
        run("Hanif Abdurraqib", ["Go Ahead in the Rain"], .jacket, (0.74, 0.20, 0.14), thick: 0.020, height: 0.208)
        // ...and after them the paperbacks.
        run(
            "George Orwell",
            [
                "Down and Out in Paris and London", "Burmese Days", "Homage to Catalonia", "Animal Farm",
                "Nineteen Eighty-Four",
            ], .paperback, (0.86, 0.42, 0.10), thick: 0.016, height: 0.180)
        run(
            "P. G. Wodehouse",
            [
                "The Inimitable Jeeves", "Carry On, Jeeves", "Very Good, Jeeves", "Right Ho, Jeeves",
                "The Code of the Woosters", "Joy in the Morning",
            ], .paperback, (0.86, 0.42, 0.10), thick: 0.015, height: 0.180)
        run(
            "Agatha Christie",
            [
                "The Mysterious Affair at Styles", "The Murder of Roger Ackroyd", "Murder on the Orient Express",
                "The ABC Murders", "Death on the Nile", "And Then There Were None",
            ],
            .paperback, (0.16, 0.42, 0.30), thick: 0.015, height: 0.180)
        run(
            "Raymond Chandler", ["The Big Sleep", "Farewell, My Lovely", "The Lady in the Lake", "The Long Goodbye"],
            .paperback, (0.16, 0.42, 0.30), thick: 0.016, height: 0.180)
        run(
            "Dashiell Hammett", ["Red Harvest", "The Maltese Falcon", "The Thin Man"], .paperback, (0.10, 0.10, 0.11),
            thick: 0.014, height: 0.178)
        run(
            "Virginia Woolf", ["Mrs Dalloway", "To the Lighthouse", "Orlando", "The Waves"], .paperback,
            (0.42, 0.50, 0.56), thick: 0.014, height: 0.196)
        run(
            "James Joyce", ["Dubliners", "A Portrait of the Artist as a Young Man", "Ulysses"], .paperback,
            (0.42, 0.50, 0.56), thick: 0.019, height: 0.196)
        run(
            "F. Scott Fitzgerald", ["This Side of Paradise", "The Great Gatsby", "Tender Is the Night"], .paperback,
            (0.14, 0.24, 0.42), thick: 0.014, height: 0.196)
        run(
            "Hemingway",
            ["The Sun Also Rises", "A Farewell to Arms", "For Whom the Bell Tolls", "The Old Man and the Sea"],
            .paperback, (0.14, 0.24, 0.42), thick: 0.015, height: 0.196)
        run(
            "Steinbeck", ["Of Mice and Men", "The Grapes of Wrath", "East of Eden"], .paperback, (0.60, 0.20, 0.14),
            thick: 0.019, height: 0.196)
        run(
            "Kafka", ["Metamorphosis", "The Trial", "The Castle"], .paperback, (0.10, 0.10, 0.11), thick: 0.014,
            height: 0.196)
        run(
            "Camus", ["The Stranger", "The Plague", "The Fall"], .paperback, (0.78, 0.74, 0.64), thick: 0.012,
            height: 0.186)
        run(
            "Isaac Asimov", ["Foundation", "Foundation and Empire", "Second Foundation"], .paperback,
            (0.30, 0.16, 0.44), thick: 0.016, height: 0.178)
        run(
            "Frank Herbert", ["Dune", "Dune Messiah", "Children of Dune"], .paperback, (0.74, 0.46, 0.14), thick: 0.024,
            height: 0.178)
        run(
            "Ursula K. Le Guin",
            ["A Wizard of Earthsea", "The Tombs of Atuan", "The Farthest Shore", "The Left Hand of Darkness"],
            .paperback, (0.10, 0.34, 0.40), thick: 0.014, height: 0.178)
        run(
            "Douglas Adams",
            [
                "The Hitchhiker's Guide to the Galaxy", "The Restaurant at the End of the Universe",
                "Life, the Universe and Everything", "So Long, and Thanks for All the Fish", "Mostly Harmless",
            ],
            .paperback, (0.12, 0.12, 0.30), thick: 0.014, height: 0.178)
        run(
            "Natsume Sōseki", ["I Am a Cat", "Botchan", "Kokoro"], .paperback, (0.78, 0.74, 0.64), thick: 0.016,
            height: 0.186)
        run(
            "Kawabata", ["Snow Country", "Thousand Cranes", "The Sound of the Mountain"], .paperback,
            (0.78, 0.74, 0.64), thick: 0.012, height: 0.186)
        run(
            "Tanizaki", ["Some Prefer Nettles", "The Makioka Sisters", "In Praise of Shadows"], .paperback,
            (0.78, 0.74, 0.64), thick: 0.016, height: 0.186)
        run(
            "Mishima", ["Spring Snow", "Runaway Horses", "The Temple of Dawn", "The Decay of the Angel"], .paperback,
            (0.62, 0.12, 0.14), thick: 0.018, height: 0.186)
        run(
            "Haruki Murakami", ["A Wild Sheep Chase", "Norwegian Wood", "Kafka on the Shore"], .paperback,
            (0.90, 0.88, 0.82), thick: 0.019, height: 0.196)
        set("Haruki Murakami", "1Q84", volumes: 3, .paperback, (0.90, 0.88, 0.82), thick: 0.020, height: 0.196)
        return all
    }()

    /// The books that lie flat show their front boards, and each has a place in the atlas for one:
    /// three cells wide, in the bottom row, to the right of the last spines.
    private(set) static var coverSlots: [Int: Int] = {
        var slots: [Int: Int] = [:]
        for (index, book) in catalogue.enumerated() where (book.flat || book.leans) && slots.count < 30 {
            slots[index] = slots.count
        }
        return slots
    }()
    /// The same for back boards: a book standing at the edge of a gap, or fallen over, shows one side or the other.
    private(set) static var backSlots: [Int: Int] = [:]
    private static let slotCount = 30 + 21 * 4
    private static var planned = ""

    /// Works out, before anything is drawn, which books will have a board in view once the
    /// shelves are filled (the ones beside a gap, at the end of a bay, next to a pile, or
    /// leaning), so that each can be given its front or back cover. `fill` is the same filling
    /// the scene is about to do, run once without making anything.
    static func plan(_ fill: ((_ index: Int, _ front: Bool) -> Void) -> Void) {
        var fronts: [Int] = []
        var backs: [Int] = []
        for (index, book) in catalogue.enumerated() where book.flat || book.leans { fronts.append(index) }
        fill { index, front in
            if front {
                if !fronts.contains(index) { fronts.append(index) }
            } else if !backs.contains(index) {
                backs.append(index)
            }
        }
        var slots: [Int: Int] = [:]
        var behind: [Int: Int] = [:]
        for index in fronts where slots.count < slotCount { slots[index] = slots.count }
        for index in backs where slots.count + behind.count < slotCount { behind[index] = slots.count + behind.count }
        coverSlots = slots
        backSlots = behind
        planned = "\(fronts.count).\(backs.count).\(fronts.reduce(0, &+) &+ backs.reduce(0, &+) &* 3)"
    }

    /// (The first nine are in the fourth row to the right of the spines, the next twenty-one along
    /// the fifth, and the rest in rows of twenty-one in the strip under the spines.)
    private static func coverRect(_ slot: Int) -> CGRect {
        if slot < 9 {
            return CGRect(x: CGFloat(34 + slot * 3) * 64, y: atlasHeight - 4 * 512 + 200, width: 192, height: 288)
        }
        if slot < 30 {
            return CGRect(x: CGFloat((slot - 9) * 3) * 64, y: atlasHeight - 5 * 512 + 200, width: 192, height: 288)
        }
        return CGRect(x: CGFloat((slot - 30) % 21) * 192, y: CGFloat((slot - 30) / 21) * 288, width: 192, height: 288)
    }

    /// Where the books about music begin.
    static var firstJacket: Int { catalogue.firstIndex { $0.binding == .jacket } ?? 0 }

    // MARK: The spines

    /// Spines are 64 px wide and 512 high, 64 to a row, four rows; the last cell is page edges.
    static let cells = 320
    private static let atlasHeight: CGFloat = 2560 + 4 * 288  // (five rows of spines, and under them four of covers)

    /// Every spine side by side in one picture, so the whole wall of books is one material and
    /// one piece of geometry: the colour, and (at half the size) where there is gold leaf.
    static func atlas() -> (colour: CGImage, metal: CGImage) {
        let colour = Mat.cached("bookshelf.spines.5.\(planned)") {
            Tex.draw(width: 4096, height: Int(atlasHeight)) { ctx, _ in paint(ctx, metal: false) }
        }
        let metal = Mat.cached("bookshelf.gilt.4.\(planned)") {
            Tex.draw(width: 2048, height: Int(atlasHeight / 2)) { ctx, _ in
                ctx.scaleBy(x: 0.5, y: 0.5)
                paint(ctx, metal: true)
            }
        }
        return (colour, metal)
    }

    static func material() -> SCNMaterial {
        let atlas = atlas()
        let material = Mat.pbr(.white, roughness: 0.82)
        material.diffuse.contents = atlas.colour
        material.diffuse.mipFilter = .linear
        material.diffuse.maxAnisotropy = 8
        material.metalness.contents = atlas.metal
        return material
    }

    /// Where a spine's cell sits in the atlas, in pixels from the bottom left.
    private static func cell(_ index: Int) -> CGPoint {
        CGPoint(x: CGFloat(index % 64) * 64, y: atlasHeight - CGFloat(index / 64 + 1) * 512)
    }

    /// Lettering down a spine: top to bottom, as English books have it, in one line if it fits
    /// at a readable size and otherwise in two.
    private static func letter(
        _ text: String, in ctx: CGContext, x: CGFloat, top: CGFloat, length: CGFloat, font names: [String],
        size: CGFloat, colour: NSColor, tracking: CGFloat = 0.04
    ) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        defer { NSGraphicsContext.restoreGraphicsState() }
        func attributes(_ s: CGFloat) -> [NSAttributedString.Key: Any] {
            let font =
                names.lazy.compactMap { NSFont(name: $0, size: s) }.first
                ?? NSFont.systemFont(ofSize: s, weight: .semibold)
            return [.font: font, .foregroundColor: colour, .kern: s * tracking]
        }
        var lines = [text]
        var s = size
        while s > 15, (text as NSString).size(withAttributes: attributes(s)).width > length { s -= 1 }
        if (text as NSString).size(withAttributes: attributes(s)).width > length {
            // Break at the space nearest the middle and set it in two lines.
            let words = text.split(separator: " ").map(String.init)
            var best = 1
            var gap = Int.max
            for k in 1..<max(words.count, 2) {
                let d = abs(
                    words.prefix(k).joined(separator: " ").count - words.dropFirst(k).joined(separator: " ").count)
                if d < gap {
                    gap = d
                    best = k
                }
            }
            lines = [words.prefix(best).joined(separator: " "), words.dropFirst(best).joined(separator: " ")].filter {
                !$0.isEmpty
            }
            s = min(size, 22)
            while s > 10, lines.contains(where: { ($0 as NSString).size(withAttributes: attributes(s)).width > length })
            { s -= 1 }
        }
        ctx.saveGState()
        ctx.translateBy(x: x + 32, y: top)
        ctx.rotate(by: -.pi / 2)
        for (k, line) in lines.enumerated() {
            let extent = (line as NSString).size(withAttributes: attributes(s))
            let across: CGFloat = lines.count == 1 ? -extent.height / 2 : (k == 0 ? 1 : -extent.height - 1)
            (line as NSString).draw(
                at: CGPoint(x: (length - extent.width) / 2, y: across), withAttributes: attributes(s))
        }
        ctx.restoreGState()
    }

    private static func paint(_ ctx: CGContext, metal: Bool) {
        ctx.setFillColor(Tex.gray(0))
        ctx.fill(CGRect(x: 0, y: 0, width: 4096, height: atlasHeight))
        var rng = SeededRandom(seed: 711)
        let serif = [
            ["Baskerville-SemiBold", "Baskerville"], ["Didot-Bold", "Didot"],
            ["HoeflerText-Black", "HoeflerText-Regular"], ["BigCaslon-Medium", "Baskerville"],
            ["Cochin-Bold", "Cochin"],
        ]
        let sans = [
            ["Futura-Bold", "Futura-Medium"], ["HelveticaNeue-CondensedBold", "HelveticaNeue-Bold"],
            ["GillSans-Bold", "GillSans"], ["AvenirNextCondensed-Bold", "AvenirNext-Bold"],
            ["DINCondensed-Bold", "HelveticaNeue-Bold"],
        ]
        for (index, book) in catalogue.prefix(cells - 1).enumerated() {
            let origin = cell(index)
            let x = origin.x
            let y0 = origin.y
            let area = CGRect(x: x, y: y0, width: 64, height: 512)
            let c = book.colour
            let pale = c.0 * 0.3 + c.1 * 0.59 + c.2 * 0.11 > 0.5
            let base = Tex.rgb(c.0, c.1, c.2)
            let gold = NSColor(srgbRed: 0.86, green: 0.70, blue: 0.36, alpha: 1)
            let white = NSColor(white: 1, alpha: 1)
            let ink =
                pale
                ? NSColor(srgbRed: 0.10, green: 0.09, blue: 0.08, alpha: 1)
                : NSColor(srgbRed: 0.93, green: 0.90, blue: 0.82, alpha: 1)
            ctx.saveGState()
            ctx.clip(to: area)
            switch book.binding {
            case .cloth, .leather:
                let leather = book.binding == .leather
                // Not every binder used gold: some of these are lettered in silver, some in black or a colour.
                let foils = [
                    gold, gold, NSColor(srgbRed: 0.80, green: 0.81, blue: 0.80, alpha: 1), gold,
                    NSColor(srgbRed: 0.82, green: 0.50, blue: 0.30, alpha: 1),
                    NSColor(srgbRed: 0.90, green: 0.86, blue: 0.74, alpha: 1),
                ]
                let inked = book.design % 7 == 3
                let gilt =
                    metal ? (inked ? NSColor.black : white) : (pale || inked ? ink : foils[book.design % foils.count])
                /// A panel of tooling: small repeated ornaments, as on the spines of subscription sets.
                func tooling(_ box: CGRect, _ kind: Int) {
                    ctx.setFillColor(gilt.cgColor)
                    ctx.setStrokeColor(gilt.cgColor)
                    ctx.setLineWidth(1.1)
                    ctx.stroke(box.insetBy(dx: 1.5, dy: 1.5))
                    switch kind % 4 {
                    case 0:  // a diaper of small lozenges
                        for row in 0..<Int(box.height / 11) {
                            for column in 0..<4 {
                                let c = CGPoint(
                                    x: box.minX + 9 + CGFloat(column) * (box.width - 18) / 3 + (row % 2 == 0 ? 0 : 6),
                                    y: box.minY + 8 + CGFloat(row) * 11)
                                guard c.x < box.maxX - 5 else { continue }
                                ctx.move(to: CGPoint(x: c.x - 3.4, y: c.y))
                                ctx.addLine(to: CGPoint(x: c.x, y: c.y + 4))
                                ctx.addLine(to: CGPoint(x: c.x + 3.4, y: c.y))
                                ctx.addLine(to: CGPoint(x: c.x, y: c.y - 4))
                                ctx.closePath()
                                ctx.fillPath()
                            }
                        }
                    case 1:  // a flower in the middle with sprays to the corners
                        let c = CGPoint(x: box.midX, y: box.midY)
                        for k in 0..<8 {
                            let a = CGFloat(k) / 8 * 2 * .pi
                            ctx.fillEllipse(
                                in: CGRect(x: c.x + cos(a) * 8 - 3, y: c.y + sin(a) * 8 - 3, width: 6, height: 6))
                        }
                        ctx.fillEllipse(in: CGRect(x: c.x - 3.5, y: c.y - 3.5, width: 7, height: 7))
                        for (dx, dy) in [(CGFloat(1), CGFloat(1)), (-1, 1), (1, -1), (-1, -1)] {
                            ctx.move(to: CGPoint(x: c.x + dx * 12, y: c.y + dy * 12))
                            ctx.addQuadCurve(
                                to: CGPoint(
                                    x: box.midX + dx * (box.width / 2 - 6), y: box.midY + dy * (box.height / 2 - 6)),
                                control: CGPoint(x: c.x + dx * 20, y: c.y + dy * 8))
                            ctx.strokePath()
                        }
                    case 2:  // frames within frames
                        for k in 1...3 { ctx.stroke(box.insetBy(dx: CGFloat(k) * 5.5, dy: CGFloat(k) * 5.5)) }
                    default:  // a running vine
                        ctx.move(to: CGPoint(x: box.midX, y: box.minY + 5))
                        for k in 0..<Int((box.height - 10) / 10) {
                            let y = box.minY + 5 + CGFloat(k) * 10
                            let side: CGFloat = k % 2 == 0 ? 1 : -1
                            ctx.addQuadCurve(
                                to: CGPoint(x: box.midX, y: y + 10), control: CGPoint(x: box.midX + side * 13, y: y + 5)
                            )
                            ctx.fillEllipse(in: CGRect(x: box.midX + side * 12 - 3, y: y + 3, width: 6, height: 5))
                        }
                        ctx.strokePath()
                    }
                }
                if !metal {
                    ctx.setFillColor(base)
                    ctx.fill(area)
                    for _ in 0..<(leather ? 120 : 280) {  // the weave of the cloth, or the grain of the hide
                        ctx.setFillColor(Tex.gray(rng.unit() < 0.5 ? 1 : 0, rng.range(0.03, 0.09)))
                        ctx.fill(
                            CGRect(
                                x: x + rng.range(0, 64), y: y0 + rng.range(24, 512),
                                width: leather ? rng.range(1, 3) : rng.range(2, 9),
                                height: leather ? rng.range(1, 3) : 1))
                    }
                }
                ctx.setFillColor(gilt.cgColor)
                if leather {
                    // Raised bands, each with a gold line either side.
                    for band in [CGFloat(452), 372, 196, 116] {
                        if !metal {
                            ctx.setFillColor(Tex.gray(0, 0.28))
                            ctx.fill(CGRect(x: x, y: y0 + band - 5, width: 64, height: 10))
                            ctx.setFillColor(Tex.gray(1, 0.10))
                            ctx.fill(CGRect(x: x, y: y0 + band + 2, width: 64, height: 2))
                        }
                        ctx.setFillColor(gilt.cgColor)
                        ctx.fill(CGRect(x: x + 3, y: y0 + band + 8, width: 58, height: 1.8))
                        ctx.fill(CGRect(x: x + 3, y: y0 + band - 10, width: 58, height: 1.8))
                    }
                    if !metal {
                        ctx.setFillColor(
                            [
                                Tex.rgb(0.42, 0.07, 0.05), Tex.rgb(0.05, 0.05, 0.05, 0.85), Tex.rgb(0.08, 0.20, 0.13),
                                Tex.rgb(0.07, 0.10, 0.24), Tex.rgb(0.05, 0.05, 0.05, 0.85),
                            ][book.design % 5])
                        ctx.fill(CGRect(x: x + 4, y: y0 + 208, width: 56, height: 152))
                    }
                    letter(
                        book.title.uppercased(), in: ctx, x: x, top: y0 + 356, length: 144,
                        font: serif[book.design % serif.count], size: 20, colour: gilt, tracking: 0.08)
                    letter(
                        book.author.uppercased(), in: ctx, x: x, top: y0 + 442, length: 62,
                        font: serif[book.design % serif.count], size: 12, colour: gilt, tracking: 0.1)
                    if let number = book.number {
                        letter(
                            number, in: ctx, x: x, top: y0 + 178, length: 54, font: serif[book.design % serif.count],
                            size: 24, colour: gilt)
                    } else {
                        ctx.setFillColor(gilt.cgColor)
                        ctx.saveGState()
                        ctx.translateBy(x: x + 32, y: y0 + 156)
                        ctx.rotate(by: .pi / 4)
                        ctx.fill(CGRect(x: -7, y: -7, width: 14, height: 14))
                        ctx.restoreGState()
                    }
                    ctx.setFillColor(gilt.cgColor)
                    tooling(CGRect(x: x + 7, y: y0 + 32, width: 50, height: 70), book.design)
                    if book.number != nil {
                        tooling(CGRect(x: x + 7, y: y0 + 466, width: 50, height: 36), book.design + 2)
                    }
                } else {
                    let style = book.design % 3
                    for line
                        in (style == 0
                        ? [CGFloat(486), 478, 60, 52]
                        : (style == 1 ? [CGFloat(488), 46] : [CGFloat(484), 480, 470, 68, 58, 54]))
                    {
                        ctx.fill(CGRect(x: x + 3, y: y0 + line, width: 58, height: style == 1 ? 5 : 2.2))
                    }
                    letter(
                        book.title, in: ctx, x: x, top: y0 + 462, length: book.number == nil ? 250 : 210,
                        font: serif[book.design % serif.count], size: 25, colour: gilt)
                    if let number = book.number {
                        letter(
                            number, in: ctx, x: x, top: y0 + 240, length: 40, font: serif[book.design % serif.count],
                            size: 24, colour: gilt)
                    }
                    letter(
                        book.author.uppercased(), in: ctx, x: x, top: y0 + 196, length: 118,
                        font: serif[book.design % serif.count], size: 13, colour: gilt, tracking: 0.1)
                    if style == 2 {
                        ctx.setStrokeColor(gilt.cgColor)
                        ctx.setLineWidth(1.6)
                        ctx.stroke(CGRect(x: x + 6, y: y0 + 204, width: 52, height: 264))
                    }
                    if style != 1, book.design % 2 == 0 {
                        tooling(CGRect(x: x + 9, y: y0 + 30, width: 46, height: 42), book.design + 1)
                    }
                }
            case .paperback:
                guard !metal else { break }
                // Bands of colour either side of a cream panel that carries the title.
                ctx.setFillColor(base)
                ctx.fill(area)
                let cream = Tex.rgb(0.86, 0.81, 0.68)
                let whole = book.design % 3 == 0
                if !pale || !whole {
                    ctx.setFillColor(pale ? Tex.rgb(0.80, 0.76, 0.66) : cream)
                    ctx.fill(CGRect(x: x, y: y0 + (whole ? 96 : 150), width: 64, height: whole ? 330 : 240))
                }
                let dark = NSColor(srgbRed: 0.10, green: 0.09, blue: 0.08, alpha: 1)
                let top: CGFloat = whole ? 418 : 382
                letter(
                    book.title, in: ctx, x: x, top: y0 + top, length: book.number == nil ? 150 : 96,
                    font: sans[book.design % sans.count], size: 21, colour: dark, tracking: 0.02)
                if let number = book.number {
                    letter(
                        "BOOK " + number, in: ctx, x: x, top: y0 + top - 104, length: 60,
                        font: sans[book.design % sans.count], size: 13, colour: dark, tracking: 0.1)
                }
                letter(
                    book.author.uppercased(), in: ctx, x: x, top: y0 + top - 164, length: (whole ? 152 : 62),
                    font: sans[book.design % sans.count], size: 11, colour: dark, tracking: 0.08)
                // The publisher's mark at the foot, and at the head the series number.
                ctx.setFillColor(pale ? Tex.rgb(0.10, 0.09, 0.08) : cream)
                ctx.fillEllipse(in: CGRect(x: x + 20, y: y0 + 42, width: 24, height: 30))
                ctx.setFillColor(base)
                ctx.fillEllipse(in: CGRect(x: x + 26, y: y0 + 49, width: 12, height: 16))
                for _ in 0..<Int(rng.range(0, 4)) {  // a spine that has been opened flat
                    ctx.setFillColor(Tex.gray(1, rng.range(0.25, 0.6)))
                    ctx.fill(CGRect(x: x + rng.range(6, 56), y: y0 + 24, width: rng.range(1.2, 3), height: 488))
                }
            case .jacket:
                guard !metal else { break }
                ctx.setFillColor(base)
                ctx.fill(area)
                let style = book.design % 4
                let accent =
                    pale
                    ? NSColor(srgbRed: 0.76, green: 0.16, blue: 0.12, alpha: 1)
                    : NSColor(srgbRed: 0.96, green: 0.80, blue: 0.24, alpha: 1)
                if style == 1 {
                    ctx.setFillColor(accent.cgColor)
                    ctx.fill(CGRect(x: x, y: y0 + 24, width: 64, height: 84))
                }
                if style == 2 {
                    ctx.setFillColor(ink.withAlphaComponent(0.9).cgColor)
                    ctx.fill(CGRect(x: x, y: y0 + 430, width: 64, height: 82))
                }
                letter(
                    style == 3 ? book.title : book.title.uppercased(), in: ctx, x: x,
                    top: y0 + (style == 2 ? 420 : 494), length: 268,
                    font: style % 2 == 0 ? sans[book.design % sans.count] : serif[book.design % serif.count],
                    size: 30, colour: style == 0 ? accent : ink, tracking: 0.02)
                letter(
                    book.author.uppercased(), in: ctx, x: x, top: y0 + 212, length: 100,
                    font: sans[(book.design + 1) % sans.count], size: 13,
                    colour: style == 1 ? (pale ? white : NSColor.black) : ink, tracking: 0.08)
                // The publisher's device, and the shine of a laminated jacket where it has creased.
                ctx.setStrokeColor(ink.cgColor)
                ctx.setLineWidth(2)
                ctx.stroke(CGRect(x: x + 22, y: y0 + 40, width: 20, height: 26))
                ctx.setFillColor(Tex.gray(1, 0.07))
                ctx.fill(CGRect(x: x + 44, y: y0 + 24, width: 6, height: 488))
            }
            if !metal {
                // What time does to a spine: sunned at the head, rubbed pale along the joints, a
                // chip out of the headcap, and on some a library's label.
                if let fade = CGGradient(
                    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                    colors: [Tex.rgb(0.90, 0.84, 0.70, rng.range(0.10, 0.46)), Tex.rgb(0.90, 0.84, 0.70, 0)] as CFArray,
                    locations: [0, 1])
                {
                    ctx.drawLinearGradient(
                        fade, start: CGPoint(x: x, y: y0 + 512), end: CGPoint(x: x, y: y0 + rng.range(200, 420)),
                        options: [])
                }
                ctx.setFillColor(Tex.gray(1, rng.range(0.14, 0.36)))
                ctx.fill(CGRect(x: x, y: y0 + 24, width: 3.5, height: 488))
                ctx.fill(CGRect(x: x + 60.5, y: y0 + 24, width: 3.5, height: 488))
                if rng.unit() < 0.22 {
                    ctx.setFillColor(Tex.rgb(0.80, 0.74, 0.60, 0.9))
                    ctx.fillEllipse(
                        in: CGRect(
                            x: x + rng.range(4, 44), y: y0 + 504, width: rng.range(8, 20), height: rng.range(8, 14)))
                }
                if rng.unit() < 0.07 {
                    ctx.setFillColor(Tex.rgb(0.92, 0.90, 0.84))
                    ctx.fill(CGRect(x: x + 10, y: y0 + 78, width: 44, height: 34))
                    ctx.setFillColor(Tex.gray(0.1, 0.8))
                    for k in 0..<3 {
                        ctx.fill(CGRect(x: x + 15, y: y0 + 86 + CGFloat(k) * 8, width: rng.range(18, 34), height: 3))
                    }
                }
                // Head and tail are where a spine goes first: frayed pale, sometimes torn right down.
                let frayed = Tex.rgb(0.80, 0.74, 0.62, rng.range(0.35, 0.8))
                for (edge, grow) in [(y0 + 512, CGFloat(-1)), (y0 + 24, 1)] {
                    for _ in 0..<Int(rng.range(3, 9)) {
                        let w = rng.range(3, 11)
                        let h = rng.range(2, rng.unit() < 0.10 ? 34 : 9)
                        ctx.setFillColor(frayed)
                        ctx.fillEllipse(
                            in: CGRect(
                                x: x + rng.range(0, 64 - w), y: (grow < 0 ? edge - h : edge) - h * 0.4, width: w,
                                height: h * 1.8))
                    }
                }
                if book.binding == .leather || book.binding == .cloth, rng.unit() < 0.5 {
                    // Cracks along the joints of an old binding.
                    ctx.setStrokeColor(Tex.rgb(0.05, 0.03, 0.02, 0.5))
                    ctx.setLineWidth(1.2)
                    for side in [x + 5, x + 59] {
                        var p = CGPoint(x: side, y: y0 + rng.range(60, 200))
                        ctx.move(to: p)
                        for _ in 0..<Int(rng.range(4, 12)) {
                            p.x += rng.range(-2, 2)
                            p.y += rng.range(10, 34)
                            ctx.addLine(to: p)
                        }
                        ctx.strokePath()
                    }
                }
                if book.binding == .jacket, rng.unit() < 0.4 {
                    // A dust jacket torn at the top and mended with tape gone brown.
                    ctx.setFillColor(Tex.rgb(0.86, 0.82, 0.74, 0.9))
                    ctx.move(to: CGPoint(x: x + rng.range(4, 30), y: y0 + 512))
                    ctx.addLine(to: CGPoint(x: x + rng.range(20, 44), y: y0 + rng.range(440, 480)))
                    ctx.addLine(to: CGPoint(x: x + rng.range(40, 60), y: y0 + 512))
                    ctx.closePath()
                    ctx.fillPath()
                    ctx.setFillColor(Tex.rgb(0.62, 0.48, 0.22, 0.45))
                    ctx.fill(CGRect(x: x + 6, y: y0 + rng.range(420, 450), width: 52, height: 22))
                }
                for _ in 0..<Int(rng.range(5, 14)) {  // scuffs, and stains
                    ctx.setFillColor(Tex.gray(rng.unit() < 0.6 ? 1 : 0, rng.range(0.08, 0.26)))
                    ctx.fill(
                        CGRect(
                            x: x + rng.range(0, 56), y: y0 + rng.range(24, 500), width: rng.range(3, 16),
                            height: rng.range(1, 4)))
                }
                if rng.unit() < 0.18 {
                    let r = rng.range(10, 26)
                    ctx.setFillColor(Tex.rgb(0.24, 0.16, 0.08, rng.range(0.10, 0.24)))
                    ctx.fillEllipse(
                        in: CGRect(x: x + rng.range(-10, 50), y: y0 + rng.range(40, 460), width: r * 2, height: r * 2.6)
                    )
                }
                ctx.setFillColor(base)
                ctx.fill(CGRect(x: x, y: y0, width: 64, height: 24))  // the boards
            }
            ctx.restoreGState()
        }
        // Front boards for the ones that lie flat: the title set large, the author under it, a frame.
        for (index, slot) in coverSlots {
            let book = catalogue[index]
            let box = coverRect(slot)
            let c = book.colour
            let pale = c.0 * 0.3 + c.1 * 0.59 + c.2 * 0.11 > 0.5
            let gilt =
                metal
                ? NSColor.white
                : (book.binding == .jacket || pale
                    ? (pale
                        ? NSColor(srgbRed: 0.10, green: 0.09, blue: 0.08, alpha: 1)
                        : NSColor(srgbRed: 0.93, green: 0.90, blue: 0.82, alpha: 1))
                    : NSColor(srgbRed: 0.86, green: 0.70, blue: 0.36, alpha: 1))
            ctx.saveGState()
            ctx.clip(to: box)
            if !metal {
                ctx.setFillColor(Tex.rgb(c.0, c.1, c.2))
                ctx.fill(box)
                for _ in 0..<900 {
                    ctx.setFillColor(Tex.gray(rng.unit() < 0.5 ? 1 : 0, rng.range(0.03, 0.08)))
                    ctx.fill(
                        CGRect(
                            x: box.minX + rng.range(0, 192), y: box.minY + rng.range(0, 288), width: rng.range(2, 8),
                            height: 1))
                }
            }
            if book.binding != .jacket || metal == false {
                if book.binding != .jacket {
                    ctx.setStrokeColor(gilt.cgColor)
                    ctx.setLineWidth(2)
                    ctx.stroke(box.insetBy(dx: 12, dy: 12))
                    ctx.setLineWidth(1)
                    ctx.stroke(box.insetBy(dx: 17, dy: 17))
                }
                if book.binding != .jacket || !metal {
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
                    let style = NSMutableParagraphStyle()
                    style.alignment = .center
                    style.lineHeightMultiple = 0.92
                    let face =
                        (book.binding == .jacket ? sans : serif)[book.design % 5].lazy.compactMap {
                            NSFont(name: $0, size: book.title.count > 18 ? 24 : 32)
                        }.first ?? NSFont.systemFont(ofSize: 28, weight: .semibold)
                    ((book.binding == .jacket ? book.title.uppercased() : book.title) as NSString).draw(
                        with: CGRect(x: box.minX + 22, y: box.minY + 120, width: 148, height: 130),
                        options: [.usesLineFragmentOrigin],
                        attributes: [.font: face, .foregroundColor: gilt, .paragraphStyle: style], context: nil)
                    let small =
                        serif[book.design % 5].lazy.compactMap { NSFont(name: $0, size: 15) }.first
                        ?? NSFont.systemFont(ofSize: 15)
                    (book.author.uppercased() as NSString).draw(
                        with: CGRect(x: box.minX + 22, y: box.minY + 34, width: 148, height: 40),
                        options: [.usesLineFragmentOrigin],
                        attributes: [.font: small, .foregroundColor: gilt, .paragraphStyle: style, .kern: 1.5],
                        context: nil)
                    NSGraphicsContext.restoreGraphicsState()
                    ctx.setFillColor(gilt.cgColor)
                    ctx.saveGState()
                    ctx.translateBy(x: box.midX, y: box.minY + 98)
                    ctx.rotate(by: .pi / 4)
                    ctx.fill(CGRect(x: -6, y: -6, width: 12, height: 12))
                    ctx.restoreGState()
                }
            }
            if !metal {
                // Handled: corners knocked pale, a ring where a cup was put down on it, dust.
                for corner in [
                    CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
                    CGPoint(x: box.minX, y: box.maxY), CGPoint(x: box.maxX, y: box.maxY),
                ] {
                    ctx.setFillColor(Tex.rgb(0.84, 0.78, 0.66, 0.55))
                    ctx.fillEllipse(in: CGRect(x: corner.x - 12, y: corner.y - 12, width: 24, height: 24))
                }
                if slot % 3 == 0 {
                    ctx.setStrokeColor(Tex.rgb(0.30, 0.20, 0.12, 0.28))
                    ctx.setLineWidth(3)
                    ctx.addArc(
                        center: CGPoint(x: box.minX + 120, y: box.minY + 90), radius: 34, startAngle: 0.3,
                        endAngle: 5.2, clockwise: false)
                    ctx.strokePath()
                }
                for _ in 0..<14 {
                    ctx.setStrokeColor(Tex.gray(1, rng.range(0.10, 0.28)))
                    ctx.setLineWidth(rng.range(0.6, 1.4))
                    let p = CGPoint(x: box.minX + rng.range(0, 192), y: box.minY + rng.range(0, 288))
                    let a = rng.range(0, 6.28)
                    let l = rng.range(10, 60)
                    ctx.move(to: p)
                    ctx.addLine(to: CGPoint(x: p.x + cos(a) * l, y: p.y + sin(a) * l))
                    ctx.strokePath()
                }
            }
            ctx.restoreGState()
        }
        // Back boards. A cloth or leather binding has nothing printed on its back, only the grain of
        // the cloth, a border pressed into it blind, and wear; a jacket or a paperback has what the
        // papers said about it, the publisher's device, a price and a bar code.
        for (index, slot) in backSlots {
            let book = catalogue[index]
            let box = coverRect(slot)
            let c = book.colour
            let pale = c.0 * 0.3 + c.1 * 0.59 + c.2 * 0.11 > 0.5
            ctx.saveGState()
            ctx.clip(to: box)
            if !metal {
                ctx.setFillColor(Tex.rgb(c.0, c.1, c.2))
                ctx.fill(box)
                for _ in 0..<1100 {
                    ctx.setFillColor(Tex.gray(rng.unit() < 0.5 ? 1 : 0, rng.range(0.03, 0.08)))
                    ctx.fill(
                        CGRect(
                            x: box.minX + rng.range(0, 192), y: box.minY + rng.range(0, 288), width: rng.range(2, 8),
                            height: 1))
                }
                let ink =
                    pale
                    ? NSColor(srgbRed: 0.12, green: 0.11, blue: 0.10, alpha: 0.82)
                    : NSColor(srgbRed: 0.93, green: 0.90, blue: 0.82, alpha: 0.82)
                if book.binding == .jacket || book.binding == .paperback {
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
                    let style = NSMutableParagraphStyle()
                    style.alignment = .left
                    style.lineHeightMultiple = 0.95
                    let praise = [
                        "“A masterpiece. I have not read anything like it in years.”",
                        "“Unforgettable. It stays with you long after the last page.”",
                        "“The best thing its author has written, and that is saying a great deal.”",
                        "“Wise, funny and exact. Read it twice.”",
                        "“A book to press on everyone you know.”",
                    ]
                    let from = [
                        "The Observer", "The New York Times", "The Guardian", "The Times Literary Supplement",
                        "London Review of Books",
                    ]
                    var y = box.maxY - 24
                    for k in 0..<3 {
                        let text = praise[(index + k * 2) % praise.count] as NSString
                        let font = NSFont(name: "Baskerville-Italic", size: 12.5) ?? NSFont.systemFont(ofSize: 12)
                        let size = text.boundingRect(
                            with: CGSize(width: 156, height: 200), options: [.usesLineFragmentOrigin],
                            attributes: [.font: font, .paragraphStyle: style])
                        text.draw(
                            with: CGRect(x: box.minX + 18, y: y - size.height, width: 156, height: size.height),
                            options: [.usesLineFragmentOrigin],
                            attributes: [.font: font, .foregroundColor: ink, .paragraphStyle: style], context: nil)
                        y -= size.height + 3
                        (from[(index + k) % from.count].uppercased() as NSString).draw(
                            at: CGPoint(x: box.minX + 18, y: y - 10),
                            withAttributes: [
                                .font: NSFont.systemFont(ofSize: 7.5, weight: .semibold), .foregroundColor: ink,
                                .kern: 0.8,
                            ])
                        y -= 26
                    }
                    (book.author.uppercased() as NSString).draw(
                        at: CGPoint(x: box.minX + 18, y: box.minY + 20),
                        withAttributes: [
                            .font: NSFont.systemFont(ofSize: 8, weight: .semibold), .foregroundColor: ink, .kern: 1.2,
                        ])
                    NSGraphicsContext.restoreGraphicsState()
                    // The bar code, on its white patch.
                    let patch = CGRect(x: box.maxX - 74, y: box.minY + 16, width: 58, height: 38)
                    ctx.setFillColor(Tex.gray(0.96))
                    ctx.fill(patch)
                    var x = patch.minX + 5
                    while x < patch.maxX - 5 {
                        let w = rng.range(0.7, 2.2)
                        ctx.setFillColor(Tex.gray(0.06))
                        ctx.fill(CGRect(x: x, y: patch.minY + 8, width: w, height: 25))
                        x += w + rng.range(0.7, 1.8)
                    }
                } else {
                    // Blind tooling: pressed in, so a shade darker along one side of the line and lighter along the other.
                    for (dx, tone) in [(CGFloat(0), Tex.gray(0, 0.30)), (1.2, Tex.gray(1, 0.14))] {
                        ctx.setStrokeColor(tone)
                        ctx.setLineWidth(1.6)
                        ctx.stroke(box.insetBy(dx: 13, dy: 13).offsetBy(dx: dx, dy: -dx))
                        ctx.stroke(box.insetBy(dx: 19, dy: 19).offsetBy(dx: dx, dy: -dx))
                        ctx.saveGState()
                        ctx.translateBy(x: box.midX + dx, y: box.midY - dx)
                        ctx.rotate(by: .pi / 4)
                        ctx.stroke(CGRect(x: -11, y: -11, width: 22, height: 22))
                        ctx.restoreGState()
                    }
                }
                // Handled: corners knocked pale, shelf rub along the bottom, scratches.
                for corner in [
                    CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
                    CGPoint(x: box.minX, y: box.maxY), CGPoint(x: box.maxX, y: box.maxY),
                ] {
                    ctx.setFillColor(Tex.rgb(0.84, 0.78, 0.66, 0.5))
                    ctx.fillEllipse(in: CGRect(x: corner.x - 11, y: corner.y - 11, width: 22, height: 22))
                }
                ctx.setFillColor(Tex.rgb(0.84, 0.78, 0.66, 0.22))
                ctx.fill(CGRect(x: box.minX, y: box.minY, width: 192, height: 5))
                for _ in 0..<12 {
                    ctx.setStrokeColor(Tex.gray(1, rng.range(0.08, 0.24)))
                    ctx.setLineWidth(rng.range(0.6, 1.4))
                    let p = CGPoint(x: box.minX + rng.range(0, 192), y: box.minY + rng.range(0, 288))
                    let a = rng.range(0, 6.28)
                    let l = rng.range(10, 60)
                    ctx.move(to: p)
                    ctx.addLine(to: CGPoint(x: p.x + cos(a) * l, y: p.y + sin(a) * l))
                    ctx.strokePath()
                }
            }
            ctx.restoreGState()
        }
        if !metal {  // the last cell: page edges
            let origin = cell(cells - 1)
            ctx.setFillColor(Tex.rgb(0.80, 0.74, 0.60))
            ctx.fill(CGRect(x: origin.x, y: origin.y, width: 64, height: 512))
            for k in 0..<60 {
                ctx.setFillColor(Tex.rgb(0.42, 0.34, 0.22, rng.range(0.15, 0.5)))
                ctx.fill(CGRect(x: origin.x + CGFloat(k) * 1.07, y: origin.y, width: 0.45, height: 512))
            }
        }
    }

    // MARK: Shelving

    /// Adds one book to a mesh that will carry the whole shelf: standing, with its spine a tall
    /// strip facing +Z, or lying flat with its spine to the front. A bound book is made as one
    /// is: two boards that stand a little proud of the pages all round, a spine that is rounded
    /// across its width, and the block of pages set in between. `lean` turns the whole book about
    /// a lower corner, which stays on the shelf: to the right if positive, to the left if negative.
    static func add(
        _ index: Int, to mesh: inout MeshBuilder, min a: SIMD3<Float>, max b: SIMD3<Float>, flat: Bool = false,
        lean: Float = 0
    ) {
        let book = catalogue[index]
        let column = Float(index % 64)
        let row = Float(index / 64)
        let H = Float(atlasHeight)
        let u0 = (column * 64 + 1.5) / 4096
        let u1 = ((column + 1) * 64 - 1.5) / 4096
        let uMid = (u0 + u1) / 2
        func v(_ local: Float) -> Float { (row * 512 + local) / H }
        let top = v(2)
        let bottom = v(488)
        let strip = v(498)
        let last = Float(cells - 1)
        let pages0 = ((last.truncatingRemainder(dividingBy: 64)) * 64 + 2) / 4096
        let pages1 = pages0 + 60.0 / 4096
        let pagesTop = (Float((cells - 1) / 64) * 512 + 50) / H
        let pagesBottom = (Float((cells - 1) / 64) * 512 + 460) / H
        let c = cos(abs(lean))
        let s = sin(abs(lean))
        func at(_ x: Float, _ y: Float, _ z: Float) -> SIMD3<Float> {
            if lean >= 0 {
                let dx = x - b.x
                let dy = y - a.y
                return SIMD3(b.x + dx * c + dy * s, a.y - dx * s + dy * c, z)
            }
            let dx = x - a.x
            let dy = y - a.y
            return SIMD3(a.x + dx * c - dy * s, a.y + dx * s + dy * c, z)
        }
        func turned(_ n: SIMD3<Float>) -> SIMD3<Float> {
            lean >= 0
                ? SIMD3(n.x * c + n.y * s, -n.x * s + n.y * c, n.z) : SIMD3(n.x * c - n.y * s, n.x * s + n.y * c, n.z)
        }
        func quad(_ p: [SIMD3<Float>], _ uv: [SIMD2<Float>], _ n: SIMD3<Float>) {
            let i = (0..<4).map { mesh.vertex(p[$0], n, uv[$0]) }
            mesh.triangle(i[0], i[1], i[2])
            mesh.triangle(i[0], i[2], i[3])
        }
        let board = [SIMD2(u0, strip), SIMD2(u1, strip), SIMD2(u1, strip + 0.002), SIMD2(u0, strip + 0.002)]
        let pages = [
            SIMD2(pages0, pagesTop), SIMD2(pages1, pagesTop), SIMD2(pages1, pagesBottom), SIMD2(pages0, pagesBottom),
        ]
        var cover = board
        if let slot = coverSlots[index] {
            let box = coverRect(slot)
            let cu0 = Float(box.minX + 2) / 4096
            let cu1 = Float(box.maxX - 2) / 4096
            let cvTop = (H - Float(box.maxY) + 2) / H
            let cvBottom = (H - Float(box.minY) - 2) / H
            // Lying flat: head to the left and spine towards us. Standing: spine to the left as you face the board.
            cover =
                flat
                ? [SIMD2(cu0, cvTop), SIMD2(cu0, cvBottom), SIMD2(cu1, cvBottom), SIMD2(cu1, cvTop)]
                : [SIMD2(cu0, cvBottom), SIMD2(cu1, cvBottom), SIMD2(cu1, cvTop), SIMD2(cu0, cvTop)]
        }
        var back = board
        if let slot = backSlots[index] {
            let box = coverRect(slot)
            let cu0 = Float(box.minX + 2) / 4096
            let cu1 = Float(box.maxX - 2) / 4096
            let cvTop = (H - Float(box.maxY) + 2) / H
            let cvBottom = (H - Float(box.minY) - 2) / H
            // (Seen from behind, the spine is on the right.)
            back = [SIMD2(cu0, cvBottom), SIMD2(cu1, cvBottom), SIMD2(cu1, cvTop), SIMD2(cu0, cvTop)]
        }
        if flat {
            // (Lying down it is seen from above and in front: the spine, the board on top, and the page edges at head and tail.)
            let front = [at(a.x, a.y, b.z), at(b.x, a.y, b.z), at(b.x, b.y, b.z), at(a.x, b.y, b.z)]
            quad(front, [SIMD2(u0, top), SIMD2(u0, bottom), SIMD2(u1, bottom), SIMD2(u1, top)], SIMD3(0, 0, 1))
            quad([at(a.x, b.y, b.z), at(b.x, b.y, b.z), at(b.x, b.y, a.z), at(a.x, b.y, a.z)], cover, SIMD3(0, 1, 0))
            let inset: Float = book.binding == .paperback ? 0 : 0.003
            let lip = (b.y - a.y) * 0.16
            quad(
                [
                    at(a.x + inset, a.y + lip, a.z), at(a.x + inset, a.y + lip, b.z), at(a.x + inset, b.y - lip, b.z),
                    at(a.x + inset, b.y - lip, a.z),
                ], pages, SIMD3(-1, 0, 0))
            quad(
                [
                    at(b.x - inset, a.y + lip, b.z), at(b.x - inset, a.y + lip, a.z), at(b.x - inset, b.y - lip, a.z),
                    at(b.x - inset, b.y - lip, b.z),
                ], pages, SIMD3(1, 0, 0))
            if inset > 0 {  // the two boards' edges, above and below the pages
                for (y0, y1) in [(a.y, a.y + lip), (b.y - lip, b.y)] {
                    quad(
                        [at(a.x, y0, a.z), at(a.x, y0, b.z), at(a.x, y1, b.z), at(a.x, y1, a.z)], board, SIMD3(-1, 0, 0)
                    )
                    quad(
                        [at(b.x, y0, b.z), at(b.x, y0, a.z), at(b.x, y1, a.z), at(b.x, y1, b.z)], board, SIMD3(1, 0, 0))
                }
            }
            return
        }
        let bound = book.binding != .paperback
        let wide = b.x - a.x
        let boardThick: Float = bound ? min(0.0026, wide * 0.16) : 0.0004
        let sunk: Float = bound ? 0.0032 : 0.0004
        // The spine: on a bound book a real curve from one joint to the other, standing well proud
        // in the middle; on a paperback a low swell where the glue and the reading have rounded it, so the light still
        // rolls across it. (Flat, the paperbacks read as prints pasted on the shelf.)
        let round: Float = bound ? min(0.0052, wide * 0.19) : min(0.0022, wide * 0.10)
        _ = uMid
        let steps = bound ? 8 : 6
        var lower: [UInt32] = []
        var upper: [UInt32] = []
        for k in 0...steps {
            let t = Float(k) / Float(steps)
            let x = a.x + wide * t
            let rise = sin(.pi * t)
            let slope = cos(.pi * t) * .pi * round / max(wide, 0.001)
            let normal = turned(simd_normalize(SIMD3(-slope, 0, 1)))
            let z = b.z - round + round * rise
            let u = u0 + (u1 - u0) * t
            lower.append(mesh.vertex(at(x, a.y, z), normal, SIMD2(u, bottom)))
            upper.append(mesh.vertex(at(x, b.y, z), normal, SIMD2(u, top)))
        }
        for k in 0..<steps {
            mesh.triangle(lower[k], lower[k + 1], upper[k + 1])
            mesh.triangle(lower[k], upper[k + 1], upper[k])
        }
        // The two boards: their outer faces (which may carry the front cover and the back) and their top edges.
        quad(
            [at(a.x, a.y, a.z), at(a.x, a.y, b.z - round), at(a.x, b.y, b.z - round), at(a.x, b.y, a.z)], back,
            turned(SIMD3(-1, 0, 0)))
        quad(
            [at(b.x, a.y, b.z - round), at(b.x, a.y, a.z), at(b.x, b.y, a.z), at(b.x, b.y, b.z - round)], cover,
            turned(SIMD3(1, 0, 0)))
        let up = turned(SIMD3(0, 1, 0))
        quad(
            [
                at(a.x, b.y, b.z - round), at(a.x + boardThick, b.y, b.z - round), at(a.x + boardThick, b.y, a.z),
                at(a.x, b.y, a.z),
            ], board, up)
        quad(
            [
                at(b.x - boardThick, b.y, b.z - round), at(b.x, b.y, b.z - round), at(b.x, b.y, a.z),
                at(b.x - boardThick, b.y, a.z),
            ], board, up)
        // The head of the spine, and behind it the pages: lower than the boards, and hollowed where the spine rounds.
        let headband = b.z - round - (bound ? 0.004 : 0.0005)
        quad(
            [
                at(a.x + boardThick, b.y, b.z - round), at(b.x - boardThick, b.y, b.z - round),
                at(b.x - boardThick, b.y, headband), at(a.x + boardThick, b.y, headband),
            ], board, up)
        quad(
            [
                at(a.x + boardThick, b.y - sunk, headband), at(b.x - boardThick, b.y - sunk, headband),
                at(b.x - boardThick, b.y - sunk, a.z + sunk), at(a.x + boardThick, b.y - sunk, a.z + sunk),
            ], pages, up)
        if bound {  // the little walls the boards make round the sunk pages
            quad(
                [
                    at(a.x + boardThick, b.y - sunk, headband), at(a.x + boardThick, b.y - sunk, a.z),
                    at(a.x + boardThick, b.y, a.z), at(a.x + boardThick, b.y, headband),
                ], board, turned(SIMD3(1, 0, 0)))
            quad(
                [
                    at(b.x - boardThick, b.y - sunk, a.z), at(b.x - boardThick, b.y - sunk, headband),
                    at(b.x - boardThick, b.y, headband), at(b.x - boardThick, b.y, a.z),
                ], board, turned(SIMD3(-1, 0, 0)))
            quad(
                [
                    at(a.x + boardThick, b.y - sunk, headband), at(a.x + boardThick, b.y, headband),
                    at(b.x - boardThick, b.y, headband), at(b.x - boardThick, b.y - sunk, headband),
                ], board, SIMD3(0, 0, -1))
        }
    }

    /// Fills a stretch of shelf from the catalogue, in order, the way a used shelf looks: the
    /// odd gap where one is out, the last of a run leaning into it, now and then a couple
    /// laid flat on their sides. `next` is the book the stretch starts from, and is moved on.
    static func shelve(
        into mesh: inout MeshBuilder, next: inout Int, left: Float, right: Float, shelf y: Float, clear: Float,
        front z: Float, seed: UInt64,
        space: (at: Float, wide: Float)? = nil
    ) {
        arrange(
            next: &next, left: left, right: right, shelf: y, clear: clear, front: z, seed: seed, space: space,
            place: { index, low, high, flat, lean in add(index, to: &mesh, min: low, max: high, flat: flat, lean: lean)
            }, shows: { _, _ in })
    }

    /// The same filling, without making anything: only reporting which boards will be in view.
    static func survey(
        next: inout Int, left: Float, right: Float, shelf y: Float, clear: Float, front z: Float, seed: UInt64,
        space: (at: Float, wide: Float)? = nil, shows: (_ index: Int, _ front: Bool) -> Void
    ) {
        arrange(
            next: &next, left: left, right: right, shelf: y, clear: clear, front: z, seed: seed, space: space,
            place: { _, _, _, _, _ in }, shows: shows)
    }

    /// (`space` keeps a width of the shelf empty from a given point on: books stop short of it and start again beyond.)
    private static func arrange(
        next: inout Int, left: Float, right: Float, shelf y: Float, clear: Float, front z: Float, seed: UInt64,
        space: (at: Float, wide: Float)? = nil,
        place: (_ index: Int, _ low: SIMD3<Float>, _ high: SIMD3<Float>, _ flat: Bool, _ lean: Float) -> Void,
        shows: (_ index: Int, _ front: Bool) -> Void
    ) {
        var last: Int? = nil  // the book standing at the right-hand end of what has been put in so far
        var open = false  // there is nothing against the left side of whatever comes next
        var rng = SeededRandom(seed: seed)
        let count = min(catalogue.count, cells - 1)
        var x = left + Float(rng.range(0.0, 0.008))
        var propped = false  // the last book put in is leaning on whatever comes next
        var stood = false  // the last thing put in was a book standing upright
        var kept = space == nil
        while x < right - 0.016 {
            let book = catalogue[next % count]
            let roll = rng.unit()
            if !kept, let space, !propped, x + (book.flat ? 0.245 : book.thick) > space.at {
                // The space that was asked for: whatever stood before it shows its board, and the next starts clear of it.
                // (The books that would have stood there are the ones that are out: those after it stand where they
                // always do, so the row reads the same with the space as without it.)
                kept = true
                let resume = space.at + space.wide
                while x < resume {
                    let out = catalogue[next % count]
                    x += out.flat ? 0.245 : out.thick + 0.0015
                    next += 1
                }
                stood = false
                if let last { shows(last, true) }
                last = nil
                open = true
                continue
            }
            // (Never in the middle of a set: only where one author's books end.)
            let boundary = catalogue[(next + count - 1) % count].design != book.design
            if book.flat, !propped {
                guard right - x > 0.25 else { break }
                // A small pile on its side, biggest at the bottom, none of them quite square to the next.
                var level = y
                while catalogue[next % count].flat, level + catalogue[next % count].thick < y + clear - 0.008 {
                    let lying = catalogue[next % count]
                    let inset = Float(rng.range(0, 0.014))
                    place(
                        next % count, SIMD3(x + inset, level, z - lying.depth - Float(rng.range(0.004, 0.016))),
                        SIMD3(x + inset + lying.height, level + lying.thick, z - Float(rng.range(0.004, 0.016))), true,
                        0)
                    level += lying.thick
                    next += 1
                    if catalogue[next % count].design != lying.design, catalogue[next % count].binding != lying.binding
                    {
                        break
                    }
                }
                x += 0.245
                stood = false
                // (A pile is lower than the books either side of it: both show a board over it.)
                if let last { shows(last, true) }
                last = nil
                open = true
            } else if boundary, roll < 0.22, !propped, !book.leans {
                x += Float(rng.range(0.022, 0.07))  // a gap where one is out on loan
                stood = false
                if let last { shows(last, true) }
                last = nil
                open = true
            } else {
                guard x + book.thick < right else { break }
                let height = min(book.height, clear - 0.012)
                let set = Float(rng.range(0.003, 0.018)) + (book.number != nil ? 0 : Float(rng.range(0, 0.006)))
                if book.leans, stood, !propped, x - left > 0.08, right - x > book.thick + height * 0.24 + 0.02 {
                    // The first of this run has gone over to the left, against the last of the run before:
                    // its head rests on that book and its front board faces up and out.
                    let lean = Float(rng.range(0.15, 0.21))
                    x += height * sin(lean) - 0.0008
                    place(
                        next % count, SIMD3(x, y, z - set - book.depth), SIMD3(x + book.thick, y + height, z - set),
                        false, -lean)
                    x += book.thick * cos(lean) + 0.0015
                    stood = false
                    // (Fallen over: its front board faces up and one way, its back down and the other; from somewhere each is seen.)
                    shows(next % count, true)
                    shows(next % count, false)
                    last = next % count
                    open = false
                } else {
                    place(
                        next % count, SIMD3(x, y, z - set - book.depth), SIMD3(x + book.thick, y + height, z - set),
                        false, 0)
                    x += book.thick + Float(rng.range(0.0002, 0.0012))
                    stood = true
                    if open { shows(next % count, false) }
                    last = next % count
                    open = false
                }
                propped = false
                next += 1
            }
        }
        if let last, right - x > 0.006 { shows(last, true) }
    }
}
