extension Provider {
    /// The provider's stable identifier in the saved card order. Never a
    /// translated name or the case's position.
    public var identifier: String {
        switch self {
        case .claude: "claude"
        case .codex: "codex"
        case .cursor: "cursor"
        }
    }

    /// Every provider exactly once: those in `order` where they first appear,
    /// then the missing ones in the default order.
    public static func order(completing order: [Provider]) -> [Provider] {
        (order + allCases).uniqued()
    }

    /// The card order saved as `stored`, a list of identifiers. Unknown
    /// identifiers are ignored; anything other than a list gives the default.
    public static func order(restoring stored: Any?) -> [Provider] {
        let identifiers = (stored as? [Any])?.compactMap { $0 as? String } ?? []
        return order(completing: identifiers.compactMap { identifier in allCases.first { $0.identifier == identifier } })
    }
}
