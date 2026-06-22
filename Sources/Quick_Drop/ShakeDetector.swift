import AppKit

// Detects a "shake" gesture while the user is dragging something (e.g. a file
// from the Finder / Desktop). When the cursor rapidly reverses horizontal
// direction several times in a short window, `onShake` fires — this is how
// Quick_Drop summons its palette mid-drag.
//
// Uses a passive *global* event monitor on left-mouse-drag events. Monitoring
// mouse events does not require Accessibility permission; the monitor only
// observes, it never consumes events, so the in-progress drag is unaffected.
final class ShakeDetector {
    var onShake: (() -> Void)?

    private var monitor: Any?

    // Sign of the last significant horizontal movement (-1, 0, +1).
    private var lastSignX = 0
    // Timestamps (NSEvent.timestamp seconds) of recent direction reversals.
    private var reversalTimes: [TimeInterval] = []
    private var lastFire: TimeInterval = 0

    // Tuning.
    private let minSpeed: CGFloat = 6          // ignore tiny jitter
    private let windowSeconds: TimeInterval = 0.6
    private let reversalsToTrigger = 4         // back-and-forth crossings
    private let cooldown: TimeInterval = 1.2   // don't re-fire immediately

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] event in
            self?.handle(event)
        }
    }

    func stop() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func handle(_ event: NSEvent) {
        let dx = event.deltaX
        guard abs(dx) >= minSpeed else { return }

        let sign = dx > 0 ? 1 : -1
        let now = event.timestamp

        if lastSignX != 0 && sign != lastSignX {
            reversalTimes.append(now)
            reversalTimes.removeAll { now - $0 > windowSeconds }

            if reversalTimes.count >= reversalsToTrigger && now - lastFire > cooldown {
                lastFire = now
                reversalTimes.removeAll()
                // Hand back to the main thread for any UI work.
                DispatchQueue.main.async { [weak self] in self?.onShake?() }
            }
        }
        lastSignX = sign
    }
}
