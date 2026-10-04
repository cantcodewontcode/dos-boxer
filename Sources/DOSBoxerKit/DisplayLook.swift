import Foundation

/// How the DOS screen is drawn: crisp modern pixels, or the glow of the
/// monitors and TVs these games were made for.
public enum DisplayLook: String, CaseIterable, Identifiable, Codable, Sendable {
    case crispPixels
    case smooth
    case arcadeMonitor
    case familyTV

    public var id: Self { self }

    public var title: String {
        switch self {
        case .crispPixels: "Crisp Pixels"
        case .smooth: "Smooth"
        case .arcadeMonitor: "Arcade Monitor"
        case .familyTV: "Family TV"
        }
    }

    public var summary: String {
        switch self {
        case .crispPixels: "Sharp, even pixels."
        case .smooth: "Softened pixels."
        case .arcadeMonitor: "Scanlines and a colour mask, like a CRT monitor."
        case .familyTV: "A curved, glowing screen, like a home TV."
        }
    }

    /// The shader function that draws this look.
    var fragmentFunction: String {
        switch self {
        case .crispPixels: "crispFragment"
        case .smooth: "smoothFragment"
        case .arcadeMonitor: "arcadeFragment"
        case .familyTV: "tvFragment"
        }
    }

    /// The app-wide look (Settings), used unless a game has its own.
    public static let defaultsKey = "DisplayLook"

    public static var appDefault: DisplayLook {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(DisplayLook.init(rawValue:)) ?? .crispPixels
    }
}
