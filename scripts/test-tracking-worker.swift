// Exercises the actual NativePointer scheduler with a fake backend. No devices,
// event taps, settings files or user permissions are read or changed.
import Foundation
import TailorMouseCore

private final class FakePointer: PointerHardwareWorking {
    var message = "fake"
    var systemAcceleration = 0.8
    var supported = true
    var configuration: () -> ProfileConfiguration = { ProfileConfiguration() }
    var profile: () -> MouseProfile = { MouseProfile() }
    var captureWiredReference: (NativePointerValues) -> Void = { _ in }
    var failed: (String) -> Void = { _ in }
    let entered = DispatchSemaphore(value: 0)
    var block: DispatchSemaphore?
    var writes: [Double] = []
    var restored = false
    var starts = 0
    var inspectCount = 0
    var failNext = false
    func inspect() { precondition(!Thread.isMainThread); inspectCount += 1; message = "inspected" }
    func start() {
        precondition(!Thread.isMainThread)
        starts += 1; entered.signal()
        block?.wait(); block = nil
        writes.append(profile().pointerSensitivity ?? 1)
        restored = false
        if failNext { failNext = false; failed("simulated failure") }
        message = "applied"
    }
    func stop() { restored = true; message = "restored" }
}
private func pump(until condition: () -> Bool, timeout: TimeInterval = 2) {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
    precondition(condition(), "Worker completion timed out")
}
@main struct TrackingWorkerChecks {
    static func main() {
        // Stop waits for a landed write then restores; its stale completion may
        // not republish "applied", start another write or clear a later flight.
        do {
            let fake = FakePointer(); let barrier = DispatchSemaphore(value: 0); fake.block = barrier
            let pointer = NativePointer(hardware: fake)
            pointer.start(); precondition(fake.entered.wait(timeout: .now()+2) == .success)
            DispatchQueue.global().asyncAfter(deadline: .now()+0.04) { barrier.signal() }
            pointer.stop()
            precondition(fake.restored && fake.writes.count == 1 && pointer.message == "restored")
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
            precondition(pointer.message == "restored")
        }
        // A busy poll cannot accumulate unbounded jobs; the latest edit wins.
        do {
            let fake = FakePointer(); let barrier = DispatchSemaphore(value: 0); fake.block = barrier
            let pointer = NativePointer(hardware: fake)
            var value = 0.5
            pointer.profile = { MouseProfile(pointerSensitivity: value) }
            pointer.start(); precondition(fake.entered.wait(timeout: .now()+2) == .success)
            value = 0.75; pointer.edited()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            value = 1.25; pointer.edited()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            barrier.signal()
            pump { pointer.message == "applied" }
            pointer.stop() // drains the coalesced update too
            precondition(fake.writes == [0.5,1.25] && fake.restored)
        }
        // Failure callbacks/publications return to main; a subsequent Start is
        // independent from the stopped generation, including a late completion.
        do {
            let fake = FakePointer(); fake.failNext = true
            let pointer = NativePointer(hardware: fake)
            var failed = false
            pointer.failed = { _ in precondition(Thread.isMainThread); failed = true; pointer.stop() }
            pointer.start(); pump { failed }
            precondition(fake.restored)
            pointer.start(); pump { pointer.message == "applied" }
            pointer.stop(); precondition(fake.restored && fake.starts == 2)
        }
        // Cursor UI inspections do not duplicate active tracking polls.
        do {
            let fake = FakePointer(); let pointer = NativePointer(hardware: fake)
            pointer.start(); pointer.inspect(); pointer.inspect()
            pump { pointer.message == "applied" }; pointer.stop()
            precondition(fake.inspectCount == 0)
        }
        print("4 tracking-worker checks passed (fake backend; no hardware input or writes).")
    }
}
