/// One automatic attempt per process launch. Reopening a window must respect Stop.
public struct LaunchHandling {
    private var attempted = false
    public init() {}
    public mutating func shouldStart(enabled: Bool, preview: Bool) -> Bool {
        guard !preview, !attempted else { return false }
        attempted = true
        return enabled
    }
}
