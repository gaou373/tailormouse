/// UI inspectors identify physical input, rather than another remapper's output.
/// A generated event can retain the physical device's sender ID, so endpoint
/// attribution alone cannot establish that it came from the mouse.
public enum InputInspectionOrigin {
    public static let tailorMouseTag: Int64 = 0x5441494c4f52

    public static func acceptsQuartz(processID: Int64, userData: Int64,
                                     remapperProcessIDs: Set<Int32>) -> Bool {
        guard userData != tailorMouseTag else { return false }
        return !remapperProcessIDs.contains(Int32(clamping: processID))
    }
}
