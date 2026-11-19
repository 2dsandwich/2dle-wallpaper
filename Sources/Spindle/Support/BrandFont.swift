import AppKit
import CoreText
import SwiftUI

enum BrandFont {
    private static let registered: Void = {
        var error: Unmanaged<CFError>?
        CTFontManagerRegisterFontsForURL(Resources.url("fonts/ComforterBrush-Regular.ttf") as CFURL, .process, &error)
    }()

    static func wordmark(size: CGFloat) -> Font {
        _ = registered
        return .custom("ComforterBrush-Regular", size: size)
    }
}
