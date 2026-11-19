import AppKit
import SwiftUI

// MARK: - The tour

/// The first-run tour of the panel: Masashi talking you round it, one thing at a time. Each step
/// darkens everything but the thing being talked about and types out what he has to say.
enum Tour: Int, CaseIterable {
    /// What he clears his throat with: not the same every time the tour is taken.
    /// (Which of them is picked once, so that a change of language mid-tour says the same one in the other.)
    private static let coughPick = Int.random(in: 0..<4)
    static var cough: String {
        [L("*coughs*", "（コホン）"), L("*ahem*", "（ゴホン）"), L("*clears throat*", "（せきばらい）"), L("*cough cough*", "（コホコホ）")][
            coughPick]
    }

    case hello, callMe, name, team, board, playback, allow, notify, weather, records, parcel, gotRecord, coughs, scenes,
        decks, clocks, settings, keepsakes, share,
        code, codeBad, codeGood, codeLater, codeTrouble, update, account, bye

    /// How a stretch of what is said is said.
    enum Voice { case plain, loud, drawn, aside }

    /// The tour has already been up to the profile button once (to say where a friend's code can be typed in later):
    /// the next time it is there, he says so.
    static var beenToProfile = false
    /// What they asked to be called, at the start of the tour (blank if they skipped it).
    static var called: String {
        MainActor.assumeIsolated { AccountStore.shared.profile.map { $0.name } ?? AccountStore.shared.localName }
    }

    /// What is said. (Written the way it would be spoken: the pauses are typed out as pauses. And marked for how it is
    /// said: `{!…}` is said loud, and shakes; `{~…}` is drawn out, and sways; `{_…}` is under his breath, small and pale.)
    var lines: String {
        switch self {
        case .hello:
            return L(
                "Hey! Welcome to our {~passion project}!\nI'm Masashi, and… umm… I'll be the one explaining things.",
                "こんにちは！\n私たちが{~夢中で作っているプロジェクト}へようこそ！\nMasashiです。えっと…私がご案内しますね。")
        case .callMe:
            return L(
                "First things first…\nwhat should we call you?",
                "まずはじめに…\nなんとお呼びすればいいですか？")
        case .name:
            return L(
                (Tour.called.isEmpty ? "" : "Nice to meet you, \(Tour.called)!\n")
                    + "So. This is 2dle.\n{_(It's pronounced “needle”.)}\nIt's our small passion project.",
                (Tour.called.isEmpty
                    ? "" : Tour.called.count > 9 ? "\(Tour.called)さん、\nはじめまして！\n" : "\(Tour.called)さん、はじめまして！\n")
                    + "こちらが2dleです。\n{_（「ニードル」と読みます）}\n私たちの小さなプロジェクトです。")
        case .team:
            return L(
                "Oh, and the team? Umm… it's just the two of us.\nTwo high schoolers from Tokyo, Japan, with a big love of music. We make this in our spare time!\nWe couldn't afford real turntables… so we coded one.\n{_A few months in, here we are.}\nWe've packed in our… {~wettest dreams} of music, records, and our desire to waste away on a chair, coding.",
                "そうそう、チームについてですが…\n実は、私たち2人だけなんです。\n音楽が大好きな、東京の高校生2人です。\n空いた時間にコツコツ作っています！\n本物のターンテーブルは買えなかったので…\nプログラミングで作ってしまいました。\n{_作り始めて数か月、ここまで来ました。}\n音楽とレコードへの{~思い}を、\nたっぷり詰め込みました。"
            )
        case .board:
            return L(
                "And this… is your menu board.",
                "そしてこれが…メニューボードです。")
        case .playback:
            return L(
                "Up here is playback. Play, pause, skip… the usual.\nOh, and 2dle kind of… {!spies} on your music apps, to know what's playing.\n{_Hmm. “Spies” sounds bad.} It politely eavesdrops.",
                "この上は再生のコントロールです。\n再生、一時停止、スキップ。おなじみの操作です。\nそれから、2dleは音楽アプリの様子を見て、\nいま何が流れているかを知るんです。")
        case .allow:
            return L(
                "For that, your Mac is going to ask if 2dle may talk to your music app.\nWithout it there's nothing for me to play along to… so this one's a must.",
                "このあと、Macから確認が表示されます。\n2dleが音楽アプリと連携するための許可です。\nこれがないと、曲に合わせて動けないので…\nこちらはぜひ許可してください。")
        case .notify:
            return L(
                "One more, and this one's up to you.\nTurn on notifications, and I'll tell you the moment a parcel turns up!",
                "もうひとつ、こちらはお好みでどうぞ。\n通知をオンにすると、荷物が届いたときに\nすぐお知らせします！")
        // (Where the Mac is, asked for here and not before: macOS's own question comes up only when Allow is pressed.)
        case .weather:
            return L(
                "And one more, also up to you.\nLet 2dle know roughly where your Mac is, and the scenes copy your weather, your sunrise and your sunset!",
                "もうひとつ、こちらもお好みでどうぞ。\nMacのおおよその場所を許可すると、\nシーンの天気や日の出・日の入りが\nあなたの街と同じになります！")
        case .records:
            return L(
                "Here's Records.\nThis is where you pick what spins on the turntable.\nEverything's locked for now, though…",
                "こちらはレコードです。\nターンテーブルで回すレコードを選べます。\nただ、今はまだ全部ロックされています…")
        case .parcel:
            return L(
                "…wait.\nDo you hear that{!???}\n{~Beep beep… vroom…}\nIs that… my dearest {!Amazoff}?!",
                "…あれ？\n何か聞こえませんか{!？？？}\n{~プップー…ブーン…}\nもしかして…{!荷物}が届いたのかも？！")
        case .gotRecord:
            return L(
                "And like that… you've got your first record!\nClassic black, huh.\n{_…or maybe the devs were just too lazy to model anything else.}",
                "これで…\nはじめてのレコードを手に入れました！\n定番の黒ですね。")
        case .coughs:
            return L(
                "{_" + Tour.cough
                    + "}\nAnyways… that's how you unlock records.\nYou get more of them by completing achievements!",
                "{_" + Tour.cough + "}\nというわけで、レコードはこうして手に入ります。\n実績を達成すると、もっと増えていきます！")
        case .scenes:
            return L(
                "Now… Scenes!\nThis is where your turntable lives. A library, a café, a cabin in the Alps…\nMy personal favourite is the Seaside.\n{_…if only I lived next to a beach.}",
                "次は…シーンです！\nターンテーブルを置く場所を選べます。\n図書館、カフェ、アルプスの山小屋…\n私のいちばんのお気に入りは、海辺のシーンです。\n{_…海の近くに住めたらいいのに。}")
        case .decks:
            return L(
                "Turntables!\nClassics, from the Thorens TD 160… all the way to the Technics SL-1200.\nUmm… they all play the same music.\n{_Don't tell anyone.}",
                "ターンテーブルです！\nThorens TD 160から、Technics SL-1200まで、\n名機がそろっています。\nえっと…どの機種でも、流れる音楽は同じです。")
        case .clocks:
            return L(
                "Next up… Clocks!\nDo you {~seriously} want me to tell you what it does?\n…\nThe Desk Clock's on the house!\nFive more are yours for sharing 2dle with your friends.",
                "次は…時計です！\n{~デスククロック}は最初から使えます！\n2dleを友だちに紹介すると、\nさらに5つの時計がもらえます。")
        case .settings:
            return L(
                "Down here, the settings. Just flick them!\nAnd no, the switches are totally {!NOT} hooked up to a piston contraption with a sheep in a boat.\n{_"
                    + Tour.cough + "}",
                "ここから下は設定です。\nスイッチを押すだけで切り替えられます！")
        case .keepsakes:
            return L(
                "Down here, two little buttons.\nThe camera saves a picture of your desk… and the one beside it films it.\n{_Go on, show it off. We won't mind.}",
                "この下に、小さなボタンが2つあります。\nカメラはデスクの画像を保存して…\nその隣のボタンは、動画を録画します。\n{_ぜひ、みんなにシェアしてくださいね。}")
        case .share:
            return L(
                "Speaking of sharing…\nThis is a passion-driven project, and I swear, we do {!NOT} have a crack product marketing team :(\nSo… I'm going to shove you in a VW minibus and set you out on the road.\nThis button is your ticket.",
                "シェアといえば…\n2dleは、私たちが好きで作っているものなので、\n宣伝の専門チームは{!いません}…\nよかったら、2dleを広めるのを手伝ってもらえませんか？\nこのボタンから、友だちを招待できます。"
            )
        case .code:
            return L(
                "Oh! And speaking of tickets…\nDid a friend send you here?\nIf they gave you a code, punch it in!",
                "あっ！そういえば…\n友だちから2dleを紹介されましたか？\n招待コードをもらっていたら、入力してください！")
        case .codeBad:
            return L(
                "Hmm… {!that one} doesn't ring a bell.\nCheck it with your friend, and have another go?",
                "うーん…{!そのコード}は見つかりませんでした。\n友だちに確認して、もう一度試してみてください。")
        case .codeGood:
            return L(
                "{!Wait.}\nDid I hear the Amazoff turn back around{!??}\n{~Vroom…}\nYou get another one!",
                "{!あれ？}\nまた車の音が聞こえませんか{!？？}\n{~ブーン…}\nもうひとつプレゼントがあります！")
        case .codeLater:
            return L(
                "No code? No problem!\nIf one turns up later, you can punch it in up here, in your profile.",
                "コードがなくても大丈夫です！\nあとからもらったときは、\nこの上のプロフィールから入力できます。")
        case .codeTrouble:
            return L(
                "Umm… I can't get hold of the depot right now.\n{_Typical.}\nI've kept your code, though! And you can always punch one in up here, in your profile.",
                "えっと…今はサーバーにつながらないみたいです。\nでも、コードはちゃんと保存しておきました！\nこの上のプロフィールからも、\nいつでも入力できます。")
        case .update:
            return L(
                "Oh, and this one's our {~beloved} button.\nIt gets you the newest version of the app!",
                "それから、私たちの{~お気に入り}のボタンです。\nアプリを最新のバージョンにできます！")
        case .account:
            return L(
                (Tour.beenToProfile
                    ? "Hey… here we are {~again}!\nYep, the little person up here. That's you.\n"
                    : "Oh, right! Up here… that's you.\n")
                    + "You can make an account, if you like. Totally optional!\nIt keeps your records in sync across your computers…\nand it's where profiles are going to live, one day.",
                (Tour.beenToProfile ? "あっ…{~また}ここに来ましたね！\nそう、この上の人のマークがあなたです。\n" : "そうそう！この上の…これがあなたです。\n")
                    + "よければ、アカウントを作ってみてください。\n作らなくても、もちろん大丈夫です！\nMac同士でレコードを同期できるようになり…\nいずれは、プロフィール機能も加わる予定です。")
        case .bye:
            return L(
                "Anyways… that was all.\nThank you for stopping by. We {~really, really} appreciate it.\nYou {!literally} mean the world to us… umm, you're the only reason we can keep going with this passion project.\nWe put our heart and soul into this. We hope you guys enjoy it!",
                "というわけで…案内はここまでです。\n来てくださって、{~本当に}ありがとうございます。\n皆さんがいてくれるから、\n私たちはこのプロジェクトを続けられます。\n心を込めて作りました。\n楽しんでいただけたらうれしいです！"
            )
        }
    }

    /// What is said, a stretch at a time, with how each stretch is said. (The marks themselves are not said.)
    var spoken: [(text: String, voice: Voice)] {
        var pieces: [(text: String, voice: Voice)] = []
        var run = ""
        var voice = Voice.plain
        let all = Array(lines)
        var index = 0
        func close() {
            if !run.isEmpty {
                pieces.append((run, voice))
                run = ""
            }
        }
        while index < all.count {
            let letter = all[index]
            if letter == "{", index + 1 < all.count,
                let marked = ["!": Voice.loud, "~": .drawn, "_": .aside][all[index + 1]]
            {
                close()
                voice = marked
                index += 2
            } else if letter == "}", voice != .plain {
                close()
                voice = .plain
                index += 1
            } else {
                run.append(letter)
                index += 1
            }
        }
        close()
        return pieces
    }

    /// The words alone.
    var words: String { spoken.map(\.text).joined() }

    /// What is lit up while it is said (nothing: the whole panel is darkened).
    var spot: String? {
        switch self {
        case .board: return "menu"
        case .playback, .allow: return "playback"
        case .records, .coughs: return "records"
        case .scenes: return "scenes"
        case .decks: return "decks"
        case .clocks: return "clocks"
        case .settings: return "settings"
        case .keepsakes: return "keepsakes"
        case .share: return "present"
        case .update: return "update"
        case .account, .codeLater, .codeTrouble: return "profile"
        default: return nil
        }
    }

    /// A friend's code is asked for.
    var asksCode: Bool { self == .code || self == .codeBad }

    /// What a click does next, said small under the words.
    var hint: String {
        switch self {
        case .parcel, .codeGood: return L("Click anywhere to get the door", "どこかをクリックして荷物を受け取る")
        case .bye: return L("Click anywhere to finish", "どこかをクリックして終了")
        // (The music app has to be asked: there is no going on without pressing Allow.)
        case .allow: return ""
        case .account, .notify, .weather: return L("Or click anywhere to carry on", "またはどこかをクリックして次へ")
        case .code, .codeBad: return L("Or click anywhere to skip", "またはどこかをクリックしてスキップ")
        // (A name has to be given: there is no going on without one.)
        case .callMe: return ""
        default: return L("Click anywhere to go on", "どこかをクリックして次へ")
        }
    }

    // MARK: Where it was left

    /// The name a step is kept under: its own name, so that a step added later never moves what was kept.
    var key: String { String(describing: self) }
    init?(key: String) {
        guard let found = Tour.allCases.first(where: { $0.key == key }) else { return nil }
        self = found
    }

    /// A run of the tour from the developer tools: everything is shown as to somebody new (the parcel too).
    static var asNew = false

    /// What is kept about the tour. (In a test render nothing is written to the defaults: it is kept in memory, starting
    /// from `SPINDLE_TOUR_SAVED=<step>` for where it was left and `SPINDLE_TOUR_PARCEL=1` for the parcel opened.)
    private static var memory: [String: Any] = {
        var kept: [String: Any] = [:]
        if let step = Testing.env("SPINDLE_TOUR_SAVED") { kept["tourStep"] = step }
        if Testing.env("SPINDLE_TOUR_PARCEL") != nil { kept["tourParcelOpened"] = true }
        return kept
    }()
    private static func kept(_ name: String) -> Any? {
        Testing.snapshot ? memory[name] : UserDefaults.standard.object(forKey: name)
    }
    private static func keep(_ value: Any?, as name: String) {
        if Testing.snapshot {
            memory[name] = value
        } else if let value {
            UserDefaults.standard.set(value, forKey: name)
        } else {
            UserDefaults.standard.removeObject(forKey: name)
        }
    }

    /// The step the tour was on when the panel or the app was last shut, until the tour is finished.
    /// (Only a first tour is taken up again: a replay, by somebody who has been through it, starts from hello each time.
    /// Owner, 2026-10-17.)
    static var left: Tour? {
        guard kept("onboarded") as? Bool != true else { return nil }
        return (kept("tourStep") as? String).flatMap(Tour.init(key:))
    }
    /// Kept as each step comes, with whether he has been up to the profile already. (Not on a replay: see `left`.)
    static func keep(_ step: Tour) {
        guard kept("onboarded") as? Bool != true else { return }
        keep(step.key, as: "tourStep")
        keep(beenToProfile, as: "tourBeenToProfile")
    }
    /// The tour is over: nothing is left to take up again, and the day it was finished is kept.
    static func finish() {
        keep(nil, as: "tourStep")
        keep(nil, as: "tourBeenToProfile")
        keep(Date(), as: "tourFinished")
        keep(true, as: "onboarded")
    }
    /// The first record's parcel has been opened in the tour (or the tour was finished before this was kept): it is not
    /// brought again, taken up again or taken a second time.
    static var parcelOpened: Bool {
        get { kept("tourParcelOpened") as? Bool == true || kept("onboarded") as? Bool == true }
        set { keep(newValue, as: "tourParcelOpened") }
    }
    /// Whether the parcel steps are part of this run.
    static var showsParcel: Bool { asNew || !parcelOpened }
    /// A friend's code is in already (counted, or kept for when there is an account): it is not asked for again.
    static var codeIn: Bool {
        MainActor.assumeIsolated { AccountStore.shared.profile?.referred == true } || Referral.pending != nil
    }

    /// Where to take the tour up again, from the step it was left at: that step, unless it cannot be taken up as it
    /// stood. (`boxWaiting`: a clock that has been earned is still in its box.) Nil if there is nothing to take up.
    static func resumed(boxWaiting: Bool) -> Tour? {
        guard let left else { return nil }
        beenToProfile = kept("tourBeenToProfile") as? Bool ?? false
        switch left {
        // (He cannot greet anybody by a name that was never given.)
        case .name where called.isEmpty: return .callMe
        // (Opened already, he goes on from after it; if not, the van comes again. It is never brought twice.)
        case .parcel, .gotRecord: return showsParcel ? .parcel : .coughs
        // (A code turned down is asked for again; one taken in the meantime is not asked for at all.)
        case .code, .codeBad: return codeIn ? .update : .code
        // (The box the code earned, if it is still to be opened; if not, on.)
        case .codeGood: return boxWaiting ? .codeGood : .update
        case .codeLater, .codeTrouble:
            beenToProfile = true
            return .update
        // (Everything else is taken up as it stood: what macOS is asked for can be asked again, and a section that has
        // to be open for its light is opened by `enterTour`. The profile card was put away with the panel.)
        default: return left
        }
    }
}

/// The tour's light, going after what it is to light like a weight on a spring (critically damped, so it never overshoots):
/// moved on a little every frame, it keeps up with the list as it scrolls and with a section as it opens, and when it
/// is sent somewhere new it glides there. (Waiting for things to stop moving and then jumping, as it did, looked jagged.)
final class Follower {
    private(set) var rect: CGRect?
    private var speed = (x: CGFloat(0), y: CGFloat(0), w: CGFloat(0), h: CGFloat(0))
    private var last: Double?
    /// How quickly it catches up (radians a second): about a twentieth of a second behind something moving steadily.
    private let pull: CGFloat = 2 * .pi / 0.26

    func step(to target: CGRect, at now: Double) -> CGRect {
        // (A test render is one frame: it is there already.)
        if Testing.snapshot {
            rect = target
            return target
        }
        // (It first comes up out of nothing in the middle of the panel.)
        let from = rect ?? CGRect(x: 280, y: 425, width: 0, height: 0)
        let elapsed = CGFloat(min(max(now - (last ?? now), 0), 1.0 / 20))
        last = now
        let fade = exp(-pull * elapsed)
        func go(_ at: CGFloat, _ speed: inout CGFloat, _ to: CGFloat) -> CGFloat {
            let off = at - to
            let push = (speed + pull * off) * elapsed
            speed = (speed - pull * push) * fade
            return to + (off + push) * fade
        }
        let next = CGRect(
            x: go(from.minX, &speed.x, target.minX), y: go(from.minY, &speed.y, target.minY),
            width: max(go(from.width, &speed.w, target.width), 0),
            height: max(go(from.height, &speed.h, target.height), 0))
        rect = next
        return next
    }
}

/// Everything but a rounded window on to one part of the panel.
private struct Spotlight: Shape {
    var hole: CGRect
    var corner: CGFloat = 18
    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(hole.minX, hole.minY), AnimatablePair(hole.width, hole.height)) }
        set {
            hole = CGRect(
                x: newValue.first.first, y: newValue.first.second, width: newValue.second.first,
                height: newValue.second.second)
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        if hole.width > 1, hole.height > 1 {
            path.addRoundedRect(
                in: hole, cornerSize: CGSize(width: min(corner, hole.height / 2), height: min(corner, hole.height / 2)))
        }
        return path
    }
}

/// Marks on a stretch of the words, for the drawing of them to find: said loud, or drawn out.
/// (`born`: when its first letter was said. The feeling in it lasts three seconds from then, and it comes to rest.)
@available(macOS 15.0, *)
private struct LoudMark: TextAttribute { var born: Double }
@available(macOS 15.0, *)
private struct DrawnMark: TextAttribute { var born: Double }

/// Draws the words with their feeling in them: what is said loud shakes, letter by letter; what is drawn out sways.
/// Each for three seconds from when it is said, dying away over the last of them; after that the words stand still.
@available(macOS 15.0, *)
private struct SaidRenderer: TextRenderer {
    var time: Double
    /// (Nothing is moving any more: everything is drawn where it stands.)
    var still = false
    static let lasts = TourOverlay.feelingLasts

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        var count = 0.0
        for line in layout {
            for run in line {
                let loud = run[LoudMark.self]
                let drawn = run[DrawnMark.self]
                let age = time - (loud?.born ?? drawn?.born ?? .infinity)
                // (Full for most of its three seconds, and gone by the end of them.)
                let much = still || age < 0 ? 0 : min(max((SaidRenderer.lasts - age) / 0.9, 0), 1)
                guard much > 0 else {
                    context.draw(run)
                    count += Double(run.count)
                    continue
                }
                for letter in run {
                    var moved = context
                    if loud != nil {
                        moved.translateBy(
                            x: sin(time * 34 + count * 1.9) * 0.75 * much, y: cos(time * 29 + count * 2.6) * 0.85 * much
                        )
                    } else {
                        moved.translateBy(x: 0, y: sin(time * 4.2 - count * 0.55) * 1.7 * much)
                    }
                    moved.draw(letter)
                    count += 1
                }
            }
        }
    }
}

/// One step of the tour, over the panel.
struct TourOverlay: View {
    /// How long what is said with feeling goes on moving, in seconds.
    static let feelingLasts = 1.5
    let step: Tour
    /// What is being talked about, in the panel's own coordinates: the whole of it, even where the list has it out of sight.
    let spot: CGRect?
    /// What can be seen of the list, for something in it: the light is cut to this when it is drawn (and never more than
    /// 640 tall, so there is dark left to talk in). Followed whole and cut only as it is drawn, it moves with the list
    /// without shrinking and growing as the list scrolls.
    var clip: CGRect? = nil
    /// How round the corners of what is lit are (an island's, unless it is one of the round buttons).
    var corner: CGFloat = 18
    /// (The close-up of a record is dark already: nothing more is put over it.)
    var dims = true
    /// Something of the panel's own is out over the tour (the profile card, for signing in): the dark stays and closes
    /// over what was lit, nothing is said, and a click does nothing. Back again, he says it all over again.
    var away = false
    var accent: Color
    /// "Click anywhere" is said in words only until the first click of the tour.
    @Binding var hinted: Bool
    var next: () -> Void
    /// Sign up (true) or log in (false) has been pressed. (Only where there are accounts to be had.)
    var account: ((Bool) -> Void)? = nil
    /// "Allow" has been pressed, at the step that asks for what macOS has to be asked for.
    var allow: () -> Void = {}
    /// A friend's code as it is typed, what is done with it once it is all there, how many have been turned down, and
    /// whether one is being looked into. (For the steps that ask for one.)
    var code: Binding<String> = .constant("")
    var useCode: () -> Void = {}
    var refused = 0
    var checking = false

    /// Everything has been said and nothing has been clicked for a few seconds.
    @State private var waiting = false
    /// (The words under the caption, beating: there is more, when you are ready.)
    @State private var beat = false
    @State private var typed = 0
    @State private var typing: Task<Void, Never>?
    /// (An account has been asked for: there are none yet, and it says so.)
    @State private var asked = false
    /// When each stretch that is said with feeling was first said (by its place in `spoken`), and whether any of them is still moving.
    @State private var born: [Int: Double] = [:]
    @State private var moving = false
    @State private var resting: Task<Void, Never>?
    /// Where the light is: it goes after what is being talked about a frame at a time (see `Follower`), so that it moves
    /// with the list as it scrolls and with a section as it opens.
    @State private var follower = Follower()
    /// The name being typed at the start of the tour.
    @State private var calledDraft = Tour.called
    /// Goes up each time Return is pressed with no name typed: the box shakes.
    @State private var nameRefused = 0
    /// The longest a name can be: what fits beside the picture on the profile card.
    static let longestName = 18
    @FocusState private var naming: Bool

    private var letters: [Character] { Array(step.words) }
    private var done: Bool { typed >= letters.count }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if dims {
                Color.black.opacity(0.78).frame(width: 560, height: PanelWindow.barHeight + 1).offset(
                    y: -PanelWindow.barHeight - 1)
                TimelineView(.animation) { time in
                    let hole = cut(follower.step(to: target, at: time.date.timeIntervalSinceReferenceDate))
                    ZStack(alignment: .topLeading) {
                        Spotlight(hole: hole, corner: corner).fill(
                            Color.black.opacity(0.78), style: FillStyle(eoFill: true))
                        if hole.width > 4, hole.height > 4 {
                            RoundedRectangle(cornerRadius: min(corner, hole.height / 2)).stroke(
                                Color.white.opacity(0.42), lineWidth: 1.2
                            )
                            .frame(width: hole.width, height: hole.height).offset(x: hole.minX, y: hole.minY)
                        }
                    }
                }
            } else {
                Color.black.opacity(0.001)
            }
            // (The words travel with the light: from one place to the next, not from nowhere.)
            let place = captionPlace
            caption
                .frame(width: 560, height: max(place.space.height, 1), alignment: place.top ? .top : .bottom)
                .position(x: 280, y: place.space.midY)
                .animation(.spring(response: 0.55, dampingFraction: 0.86), value: place.space)
                .opacity(away ? 0 : 1).animation(.easeInOut(duration: 0.25), value: away)
                .allowsHitTesting(!away)
        }
        .frame(width: 560, height: 850)
        .contentShape(Rectangle())
        .onTapGesture { if !away { advance() } }
        // (Typed out once a step. Coming back to it from the profile card it is all there already, and is not said again.)
        .task(id: step) { await type() }
    }

    /// What of a place in the list can be seen: cut to the list's window, and to 640 tall. (Wholly out of sight, nothing,
    /// where it went out.)
    private func cut(_ rect: CGRect) -> CGRect {
        guard let clip, rect.width > 0 || rect.height > 0 else { return rect }
        var seen = rect.intersection(clip)
        if seen.isNull {
            let y = rect.midY < clip.midY ? clip.minY : clip.maxY
            return CGRect(x: rect.midX, y: y, width: 0, height: 0)
        }
        if seen.height > 640 { seen.size.height = 640 }
        return seen
    }

    /// Where the light is going: what is being talked about, or (with nothing, or with the profile card out over it) shut
    /// to nothing where it was.
    private var target: CGRect {
        guard let spot, !away else {
            let at = away ? (spot ?? follower.rect).map { CGPoint(x: $0.midX, y: $0.midY) } : nil
            return CGRect(x: at?.x ?? 280, y: at?.y ?? 425, width: 0, height: 0)
        }
        return spot
    }

    /// Where the middle of the words goes: in the dark, clear of whatever is lit. Below it if there is room, above it if not; in
    /// the middle of the panel if nothing is.
    /// Where the words go: in the dark, never over what is lit. Below it if there is room, hanging from just under it; above
    /// it if not, standing on just over it; and if neither has room, whichever has more. (`top`: hung from the top of
    /// the space, rather than stood on its foot.)
    private var captionPlace: (space: CGRect, top: Bool) {
        // (About how tall the words will be when they are all out: so many lines of so many letters.)
        // (Japanese letters are each about twice as wide.)
        let across = Language.inJapanese ? (dims ? 25.0 : 29.0) : (dims ? 46.0 : 56.0)
        let lines = step.words.split(separator: "\n", omittingEmptySubsequences: false).reduce(0) {
            $0 + max(1, Int(ceil(Double($1.count) / across)))
        }
        let tall =
            CGFloat(lines) * 26 + 34
            + (step == .account || step == .allow || step == .notify || step == .weather ? 52 : 0)
            + (step.asksCode ? 72 : 0) + (step == .callMe ? 52 : 0) + (step == .hello ? 38 : 0)
        // (Over the close-up of a record: right at the top, clear of the record.)
        if !dims { return (CGRect(x: 0, y: 20, width: 560, height: tall + 20), true) }
        guard let spot = spot.map(cut), spot.width > 1, !away else {
            return (CGRect(x: 0, y: 425 - tall / 2, width: 560, height: tall), true)
        }
        let below = CGRect(x: 0, y: spot.maxY + 16, width: 560, height: max(850 - 10 - (spot.maxY + 16), 0))
        let above = CGRect(x: 0, y: 40, width: 560, height: max(spot.minY - 14 - 40, 0))
        if below.height >= tall { return (below, true) }
        if above.height >= tall { return (above, false) }
        return below.height >= above.height ? (below, true) : (above, false)
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 10) {
            said
                .lineSpacing(5.5)
                .shadow(color: .black.opacity(0.8), radius: 6, y: 1)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if step == .account {
                // The two ways in, once he has said what they are for. (Neither has to be taken: a click anywhere else goes on.)
                HStack(spacing: 10) {
                    accountButton(L("Sign up", "新規登録"), filled: true)
                    accountButton(L("Log in", "ログイン"), filled: false)
                }
                .opacity(done ? 1 : 0).animation(.easeInOut(duration: 0.3), value: done)
                .allowsHitTesting(done)
                .padding(.top, 4)
            }
            if step == .hello {
                // The language, once he has said hello and who he is: each offered in its own words, as in the account
                // settings. (Owner, 2026-10-17: after the introduction, not from the first letter. Changed, the panel is
                // drawn again in it and he says hello again: the tour itself is kept above that, on this step.)
                languages
                    .opacity(done ? 1 : 0).animation(.easeInOut(duration: 0.3), value: done)
                    .allowsHitTesting(done)
                    .padding(.top, 4)
            }
            if step == .allow || step == .notify || step == .weather {
                // The asking itself: macOS puts up its own questions when this is pressed. (It need not be: a click anywhere else goes on.)
                accountButton(L("Allow", "許可する"), filled: true, action: allow)
                    .opacity(done ? 1 : 0).animation(.easeInOut(duration: 0.3), value: done)
                    .allowsHitTesting(done)
                    .padding(.top, 4)
            }
            if step.asksCode {
                // Somewhere to type it: the tiles a code is given out in. (It need not be: a click anywhere else goes on.)
                CodeField(code: code, refused: refused, busy: checking, submit: useCode)
                    .opacity(done ? 1 : 0).animation(.easeInOut(duration: 0.3), value: done)
                    .allowsHitTesting(done)
                    .padding(.top, 6)
            }
            // What a click does next. Said in words until the first click of the tour; after that only when nothing has been
            // clicked for a while, and then it beats, to say there is more when you are ready.
            if step == .callMe {
                // Somewhere to type a name, in glass: Return or the arrow keeps it and goes on. There is no going on without
                // one, and no more than `longestName` letters (the count stands at the end of the box).
                nameBox
                    .modifier(Shake(travel: CGFloat(nameRefused)))
                    .animation(.linear(duration: 0.45), value: nameRefused)
                    .opacity(done ? 1 : 0).animation(.easeInOut(duration: 0.3), value: done)
                    .allowsHitTesting(done)
                    .padding(.top, 6)
                    .onChange(of: done) { _, now in if now { naming = true } }
            }
            let offers = step == .account || step == .notify || step == .weather || step.asksCode || step == .callMe
            Text(
                asked
                    ? Account.notYet + L(" ", "")
                        + step.hint.replacingOccurrences(of: "Or click", with: "Click").replacingOccurrences(
                            of: "または", with: "") : step.hint
            )
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(Color.white.opacity(waiting ? (beat ? 0.95 : 0.35) : 0.5))
            .scaleEffect(waiting && beat ? 1.035 : 1, anchor: .leading)
            .opacity(done && (hinted || offers || waiting) ? 1 : 0).animation(.easeInOut(duration: 0.3), value: done)
            .frame(height: 16, alignment: .leading)
            .padding(.top, 2)
        }
        .frame(width: dims ? 440 : 500)
        .task(id: "\(step.rawValue).\(done)") {
            withAnimation(.easeOut(duration: 0.2)) {
                waiting = false
                beat = false
            }
            guard done else { return }
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.4)) { waiting = true }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { beat = true }
        }
    }

    /// English or 日本語, each in its own words, on the panel's own glass segments.
    private var languages: some View {
        HStack(spacing: 8) {
            Image(systemName: "globe").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(
                Color.white.opacity(0.6))
            GlassSegments(
                options: Language.allCases, title: { $0.title }, tint: accent,
                selection: Binding(
                    get: { Language.current },
                    set: { chosen in
                        Settings.shared.choose(chosen)
                    })
            )
            .frame(width: 160)
        }
    }

    private func accountButton(_ title: String, filled: Bool, action: (() -> Void)? = nil) -> some View {
        Button {
            if let action {
                action()
            } else if AccountStore.shared.open, let account {
                account(title == L("Sign up", "新規登録"))
            } else {
                withAnimation(.easeInOut(duration: 0.2)) { asked = true }
            }
        } label: {
            let face = Text(title).font(.system(size: 13, weight: .semibold)).frame(width: 128, height: 38)
                .contentShape(Capsule())
            if #available(macOS 26.0, *), LiquidGlass.on {
                face.glassEffect(
                    filled ? .regular.tint(accent.opacity(0.7)).interactive() : .regular.interactive(), in: .capsule)
            } else {
                face.background(Capsule().fill(filled ? accent : Color.white.opacity(0.14)))
            }
        }
        .buttonStyle(Tactile())
    }

    /// The words, drawn with their feeling in them where the system can (what is loud shakes, what is drawn out sways).
    @ViewBuilder private var said: some View {
        if #available(macOS 15.0, *), step.spoken.contains(where: { $0.voice == .loud || $0.voice == .drawn }) {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !moving)) { moment in
                words.textRenderer(SaidRenderer(time: moment.date.timeIntervalSinceReferenceDate, still: !moving))
            }
        } else {
            words
        }
    }

    /// The words as far as they have been said: the rest are there, keeping their place, but cannot be seen yet. Each
    /// stretch is set as it is said: loud is heavy and bright, drawn out leans, and an aside is small and pale.
    private var words: Text {
        var all = Text("")
        var place = 0
        let finished = typed >= letters.count
        for (number, piece) in step.spoken.enumerated() {
            let run = Array(piece.text)
            // (Said and settled; the two newest letters, still coming up; and what has not been said yet.)
            let settled = max(0, min(run.count, (finished ? typed : typed - 2) - place))
            let out = max(0, min(run.count, typed - place))
            for (from, to, shade) in [(0, settled, 1.0), (settled, out, 0.57), (out, run.count, 0.0)] where to > from {
                var part = Text(String(run[from..<to]))
                switch piece.voice {
                case .plain:
                    part = part.font(.system(size: 16.5, weight: .medium)).foregroundColor(
                        Color.white.opacity(0.96 * shade))
                case .loud:
                    part = part.font(.system(size: 17, weight: .heavy)).foregroundColor(Color.white.opacity(shade))
                case .drawn:
                    part = part.font(.system(size: 16.5, weight: .medium).italic()).foregroundColor(
                        Color.white.opacity(0.96 * shade))
                case .aside:
                    part = part.font(.system(size: 14, weight: .regular)).foregroundColor(
                        Color.white.opacity(0.6 * shade))
                }
                if #available(macOS 15.0, *) {
                    if piece.voice == .loud { part = part.customAttribute(LoudMark(born: born[number] ?? .infinity)) }
                    if piece.voice == .drawn { part = part.customAttribute(DrawnMark(born: born[number] ?? .infinity)) }
                }
                all = all + part
            }
            place += run.count
        }
        return all
    }

    /// A click while he is still talking finishes the sentence; one after that moves on.
    /// The name typed at the start: kept (on the account, for somebody signed in), and on with the tour.
    private func keepName() {
        let name = calledDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            MenuSound.play(.error)
            nameRefused += 1
            naming = true
            return
        }
        let account = AccountStore.shared
        // (Kept here at once, so that the next step greets them by it; the server is told after.)
        account.localName = name
        if account.profile != nil {
            account.nameNow(name)
            Task { _ = await account.rename(to: name) }
        }
        naming = false
        next()
    }

    /// The box the name is typed in: Liquid Glass where the system has it, a pale pane where it does not; the count of
    /// letters and the arrow that goes on stand at its end.
    @ViewBuilder private var nameBox: some View {
        let ready = !calledDraft.trimmingCharacters(in: .whitespaces).isEmpty
        let field = HStack(spacing: 8) {
            TextField(L("Your name", "お名前"), text: $calledDraft)
                .textFieldStyle(.plain).font(.system(size: 15, weight: .semibold)).focused($naming)
                .onChange(of: calledDraft) { _, typed in
                    if typed.count > Self.longestName {
                        calledDraft = String(typed.prefix(Self.longestName))
                        MenuSound.play(.error)
                    }
                }
                .onSubmit(keepName)
            Text("\(calledDraft.count)/\(Self.longestName)")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(Color.white.opacity(calledDraft.count >= Self.longestName ? 0.85 : 0.45))
            Button(action: keepName) {
                Image(systemName: "arrow.right").font(.system(size: 12, weight: .bold))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(ready ? accent : Color.white.opacity(0.10)))
                    .contentShape(Circle())
            }
            .buttonStyle(Tactile())
            .opacity(ready ? 1 : 0.5)
        }
        .padding(.leading, 14).padding(.trailing, 5).frame(width: 280, height: 38)
        if #available(macOS 26.0, *), LiquidGlass.on {
            field.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            field.background(Capsule().fill(Color(white: 0.17)))
                .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 0.8))
        }
    }

    private func advance() {
        hinted = false
        withAnimation(.easeOut(duration: 0.2)) {
            waiting = false
            beat = false
        }
        if done {
            // (The music app has to be asked: a click anywhere else does not go on from that.)
            // (Nor without a name: a click puts the typing back in the box.)
            if step == .callMe { naming = true } else if step != .allow { next() }
        } else {
            typing?.cancel()
            typed = letters.count
            // (Whatever had not been said yet is said now, all at once.)
            let now = Date().timeIntervalSinceReferenceDate
            for (number, piece) in step.spoken.enumerated() where piece.voice == .loud || piece.voice == .drawn {
                if born[number] == nil { born[number] = now }
            }
            stir()
        }
    }

    /// Something said with feeling has just been said: the words move, and three seconds after the last of it they are still again.
    private func stir() {
        moving = true
        resting?.cancel()
        resting = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64((TourOverlay.feelingLasts + 0.15) * 1_000_000_000))
            if !Task.isCancelled { moving = false }
        }
    }

    /// Types it out as it would be said: a breath at a comma, longer at a full stop, longer still at a trailing-off, and an "umm" drawn out.
    private func type() async {
        typed = 0
        asked = false
        born = [:]
        moving = false
        resting?.cancel()
        // (Where each stretch that is said with feeling begins, counted in letters.)
        var begins: [Int: Int] = [:]
        var place = 0
        for (number, piece) in step.spoken.enumerated() {
            if piece.voice == .loud || piece.voice == .drawn { begins[place] = number }
            place += piece.text.count
        }
        let all = letters
        let lower = Array(step.words.lowercased())
        let job = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 260_000_000)
            var dragging = 0
            for index in all.indices {
                if Task.isCancelled { return }
                typed = index + 1
                if let number = begins[index] {
                    born[number] = Date().timeIntervalSinceReferenceDate
                    stir()
                }
                let letter = all[index]
                // He mumbles as he goes: a syllable for every other letter, and the last word of a question goes up.
                // (Japanese is said a sound to a letter. Mumble only knows the Latin ones, so each is given one of them to say.)
                if Language.inJapanese, letter.isLetter, !letter.isASCII {
                    let sound = Array("kasatonamiru")[Int(letter.unicodeScalars.first?.value ?? 0) % 12]
                    Mumble.shared.say(sound, place: index, asking: all[index...].prefix(4).contains("？"))
                } else if letter.isLetter, index % 2 == 0 {
                    let ahead = all[index...].prefix(14)
                    Mumble.shared.say(
                        letter, place: index,
                        asking: ahead.firstIndex(of: "?").map { mark in !all[index..<mark].contains(" ") } ?? false)
                }
                // (Japanese says more in a letter: it is typed out a little slower.)
                var wait = Language.inJapanese ? 0.065 : 0.032
                if index + 2 < lower.count, lower[index] == "u" || lower[index] == "h", lower[index + 1] == "m",
                    lower[index + 2] == "m",
                    index == 0 || !lower[index - 1].isLetter
                {
                    dragging = 3
                }
                if dragging > 0 {
                    wait = 0.085
                    dragging -= 1
                }
                switch letter {
                case ",", ":": wait = 0.19
                case ".", "!", "?", ")":
                    wait =
                        index + 1 < all.count
                            && (all[index + 1] == "?" || all[index + 1] == "!" || all[index + 1] == ")") ? 0.03 : 0.36
                case "…": wait = 0.46
                case "\n": wait = 0.34
                case "*": wait = 0.12
                case "、": wait = 0.19
                case "。", "！", "？", "）":
                    wait =
                        index + 1 < all.count
                            && (all[index + 1] == "？" || all[index + 1] == "！" || all[index + 1] == "）") ? 0.03 : 0.36
                default: break
                }
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
        }
        typing = job
        await job.value
    }
}

/// Where the things the tour talks about are, for lighting them up.
struct TourSpots: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// True while the tour is being given. (Only then is anybody told where the things it talks about are.)
private struct TouringKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var touring: Bool {
        get { self[TouringKey.self] }
        set { self[TouringKey.self] = newValue }
    }
}

/// Says where a part of the panel is, while the tour is on. Where a thing is changes with every step the list is scrolled,
/// and each change is passed all the way up the panel: with no tour to hear it, that was most of the work of scrolling.
private struct TourSpotMark: ViewModifier {
    let name: String
    @Environment(\.touring) private var touring

    func body(content: Content) -> some View {
        // (Said from behind it, which is exactly its size, so that what is marked is the same view whether the tour is on or not.
        // And added to whatever is marked inside it, not put in its place: a marked section can hold marked things.)
        content
            .background {
                if touring { Color.clear.anchorPreference(key: TourSpots.self, value: .bounds) { [name: $0] } }
            }
            .id("tour." + name)
    }
}

extension View {
    /// Marks a part of the panel as something the tour can point at (and scroll to).
    func tourSpot(_ name: String) -> some View { modifier(TourSpotMark(name: name)) }
}
