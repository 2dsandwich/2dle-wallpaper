import AppKit

// (Asked for help, a bare build says where the checks are and stops: it used to start the whole app, wallpaper and all.)
if CommandLine.arguments.contains("--help") || CommandLine.arguments.contains("-h") {
    print("2dle: the app starts with no arguments. Off-screen checks are `--snapshot <file> …`: see AGENTS.md, \"Build, run, check\".")
    exit(0)
}
if CommandLine.arguments.contains("--snapshot") {
    exit(SnapshotTool.run(CommandLine.arguments))
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// No Dock icon and not in the app switcher (owner, 2026-10-17): 2dle lives in the menu bar. (It was `.regular` from
// 2026-10-15 so as to be in Force Quit's list; quitting is in the menu-bar panel's ⋯ card.)
app.setActivationPolicy(.accessory)
/// The app's menu bar, in the language in use.
func appMenu() -> NSMenu {
    // (What a Dock app's menu bar has to have: Quit, Hide, and the editing keys for the name and code fields.)
    let bar = NSMenu()
    func menu(_ title: String, _ items: [NSMenuItem]) {
        let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let inside = NSMenu(title: title)
        items.forEach(inside.addItem)
        holder.submenu = inside
        bar.addItem(holder)
    }
    func item(_ title: String, _ action: Selector, _ key: String, _ mask: NSEvent.ModifierFlags = .command)
        -> NSMenuItem
    {
        let made = NSMenuItem(title: title, action: action, keyEquivalent: key)
        made.keyEquivalentModifierMask = mask
        return made
    }
    // (Named as macOS names them in each language.)
    menu(
        "2dle",
        [
            item(L("Hide 2dle", "2dleを隠す"), #selector(NSApplication.hide(_:)), "h"),
            item(
                L("Hide Others", "ほかを隠す"), #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item(L("Show All", "すべてを表示"), #selector(NSApplication.unhideAllApplications(_:)), ""),
            .separator(),
            item(L("Quit 2dle", "2dleを終了"), #selector(NSApplication.terminate(_:)), "q"),
        ])
    menu(
        L("Edit", "編集"),
        [
            item(L("Undo", "取り消す"), Selector(("undo:")), "z"),
            item(L("Redo", "やり直す"), Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item(L("Cut", "カット"), #selector(NSText.cut(_:)), "x"),
            item(L("Copy", "コピー"), #selector(NSText.copy(_:)), "c"),
            item(L("Paste", "ペースト"), #selector(NSText.paste(_:)), "v"),
            item(L("Select All", "すべてを選択"), #selector(NSText.selectAll(_:)), "a"),
        ])
    menu(
        L("Window", "ウインドウ"),
        [
            item(L("Minimize", "しまう"), #selector(NSWindow.performMiniaturize(_:)), "m"),
            item(L("Close", "閉じる"), #selector(NSWindow.performClose(_:)), "w"),
        ])
    return bar
}
app.mainMenu = appMenu()
app.run()
