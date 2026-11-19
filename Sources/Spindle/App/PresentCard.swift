import AppKit
import SwiftUI

/// What opens out of the present button: why to share, how, and this copy's code.
struct PresentCard: View {
    var accent: Color
    /// (Opens the profile card, for somebody with no account yet to have a code with.)
    var signUp: () -> Void = {}
    @ObservedObject private var account = AccountStore.shared

    var body: some View {
        // A code belongs to an account. (A copy built with no accounts keeps its made-up one, for show.)
        let code = account.open ? account.profile.flatMap { $0.code.isEmpty ? nil : $0.code } : Referral.localCode
        let brought = account.profile?.credit ?? 0
        VStack(alignment: .leading, spacing: 11) {
            Text(L("Give a present!", "プレゼントを贈りましょう！")).font(.system(size: 15, weight: .semibold))
            Text(
                L(
                    "Best way to back our little passion project? Share it! With a friend, with someone you love, or with the guy mugging you in a back alley. (Seriously though, don't. Just hand him the wallet.)",
                    "私たちの小さなプロジェクトを応援するなら、\nシェアしていただくのがいちばんです！\n友だちや家族に、ぜひ紹介してください。")
            )
            .font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.82)).lineSpacing(2.5).fixedSize(
                horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 7) {
                step(1, L("Send your code to a friend.", "友だちにコードを送ります。"))
                step(2, L("They get 2dle, and it asks them for a referral code.", "友だちが2dleを始めると、コードを聞かれます。"))
                step(
                    3,
                    L(
                        "They type yours in, and you both get a little something!",
                        "あなたのコードを入力すると、\n2人にちょっとしたプレゼントが届きます！"))
            }
            .padding(.top, 1)
            if let code {
                Text(L("Your referral code", "あなたの招待コード")).font(.system(size: 12, weight: .semibold)).foregroundStyle(
                    Color.white.opacity(0.6)
                )
                .frame(maxWidth: .infinity).padding(.top, 4)
                CodeTiles(code: code, copies: true).frame(maxWidth: .infinity)
                ShareButton(text: Referral.message(code)) {
                    wide(symbol: "square.and.arrow.up", L("Share Invite", "招待をシェア"))
                }
                .padding(.top, 3)
                // (The last thing on the card: it stands as near the foot as it does the sides.)
                .padding(.bottom, account.open && brought == 0 ? -6 : 0)
                if !account.open {
                    Text(L("Still a demo, so no presents just yet. Sorry!", "デモ版のため、まだプレゼントは届きません。すみません！"))
                        .font(.system(size: 10.5)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            } else {
                // (A code belongs to an account: said, so that the button is no surprise.)
                Text(
                    L(
                        "Your code lives in your account, so sharing needs you to sign up first.",
                        "コードはアカウントに保存されるので、\nシェアするには新規登録が必要です。")
                )
                .font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.82)).lineSpacing(2.5).fixedSize(
                    horizontal: false, vertical: true
                )
                .padding(.top, 3)
                Button(action: signUp) { wide(symbol: "person.badge.plus", L("Get my code", "コードを受け取る")) }
                    .buttonStyle(Tactile())
                    .padding(.top, 3).padding(.bottom, -6)
            }
        }
        .task { await account.refresh() }
        .padding(16)
        .frame(width: 348, alignment: .leading)
        .modifier(Island())
        // (Without glass to blur what is behind it, it has to be dark enough by itself to be read over the list.)
        .background(
            RoundedRectangle(cornerRadius: 18).fill(LiquidGlass.on ? Color.black.opacity(0.35) : Color(white: 0.075))
        )
        .shadow(color: .black.opacity(0.5), radius: 14, y: 5)
    }

    @ViewBuilder private func wide(symbol: String, _ title: String) -> some View {
        let face = HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
            Text(title).font(.system(size: 13.5, weight: .semibold))
        }
        .frame(maxWidth: .infinity).frame(height: 42).contentShape(RoundedRectangle(cornerRadius: 8))
        // (Ten in from the card's edge, with a corner of eight: 8 + 10 = 18, the card's own, so that the two curves are
        // drawn about one centre, as the card's and the window's are. The words above keep their sixteen.)
        if #available(macOS 26.0, *), LiquidGlass.on {
            face.glassEffect(.regular.tint(accent.opacity(0.55)).interactive(), in: .rect(cornerRadius: 8)).padding(
                .horizontal, -6)
        } else {
            face.background(RoundedRectangle(cornerRadius: 8).fill(accent)).padding(.horizontal, -6)
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text("\(number)").font(.system(size: 11, weight: .bold, design: .rounded))
                .frame(width: 19, height: 19).background(Circle().fill(accent))
            Text(text).font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.88)).fixedSize(
                horizontal: false, vertical: true)
        }
    }
}
