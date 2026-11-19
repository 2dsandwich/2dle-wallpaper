import AppKit
import SwiftUI

extension SettingsView {
    // MARK: Parcels

    /// A record that has been earned and not yet opened is not brought out by itself any more: its parcel waits in the
    /// inbox (and macOS says that it has come), to be opened when it is wanted.
    func offerParcel() {
        Inbox.shared.sync()
    }

    /// Something in the inbox has had its "Open" pressed.
    func openFromInbox(_ item: Inbox.Item) {
        guard tour == nil, unboxing == nil, clockBox == nil, focusedRecord == nil else { return }
        switch item.kind {
        case .record:
            // (One laid out from the developer tools opens whether or not there really is such a parcel.)
            guard let style = RecordStyle(rawValue: item.what), collection.fresh.contains(style) || Inbox.shared.staging
            else {
                Inbox.shared.sync()
                return
            }
            shownRecord = style  // (so that the close-up is already laid out for it, and the record can be brought to the right place)
            withAnimation(.easeInOut(duration: 0.3)) { unboxing = style }
        case .clock:
            guard let style = ClockStyle(rawValue: item.what) else { return }
            bringClockBox(style)
        case .invite, .letter, .request, .browser:
            break
        }
    }

    /// A clock that has not been earned, or is still in its box, cannot stay on the desk.
    func putAwayLockedClock() {
        let style = settings.clockStyle
        if settings.clockEnabled, !style.isFree,
            Referral.needed(for: style) > invites || !openedClocks.contains(style.rawValue)
        {
            settings.clockEnabled = false
        }
    }

    var earnedUnopened: Set<ClockStyle> {
        Set(ClockStyle.earned.filter { Referral.needed(for: $0) <= invites && !openedClocks.contains($0.rawValue) })
    }

    func bringClockBox(_ style: ClockStyle) {
        thumbnails.drawClearClock(style)
        offeredClocks.insert(style)
        withAnimation(.easeInOut(duration: 0.3)) { clockBox = style }
    }

    /// A clock that has been earned waits in its box in the inbox, as a record does in its parcel.
    func offerClockBox() {
        Inbox.shared.sync()
    }
}
