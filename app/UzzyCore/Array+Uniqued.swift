extension Array where Element: Hashable {
    /// The elements without repeats, in the order they first appear.
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
