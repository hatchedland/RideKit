import SwiftUI
import UIKit

/// Ride Tracker's own icons live in Assets › Icons as template PDFs; generic ones (share, close,
/// search…) stay SF Symbols. These look up our asset first and fall back to a system symbol, so a
/// name can be either.
extension Image {
    init(icon name: String) {
        if UIImage(named: name) != nil {
            self.init(name)
        } else {
            self.init(systemName: name)
        }
    }
}

extension UIImage {
    /// Our asset if there is one, else the SF Symbol of that name.
    static func icon(_ name: String, configuration: UIImage.SymbolConfiguration? = nil) -> UIImage? {
        UIImage(named: name, in: nil, with: configuration) ?? UIImage(systemName: name, withConfiguration: configuration)
    }
}
