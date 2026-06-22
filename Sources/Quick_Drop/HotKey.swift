import AppKit
import Carbon.HIToolbox

// Registers a single system-wide hotkey using the Carbon Hot Key API.
// This does NOT require Accessibility permission (unlike a CGEventTap).
final class HotKey {
    static let shared = HotKey()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    var onPressed: (() -> Void)?

    private init() {}

    /// keyCode: a Carbon virtual key code (e.g. kVK_Space == 49).
    /// modifiers: a combination of controlKey, optionKey, cmdKey, shiftKey.
    func register(keyCode: UInt32, modifiers: UInt32) {
        unregister()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )

        // C callback cannot capture context, so route through the shared singleton.
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, _, _) -> OSStatus in
                HotKey.shared.onPressed?()
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandler
        )

        let hotKeyID = EventHotKeyID(signature: OSType(0x4F555450), id: 1) // 'OUTP'
        RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }
}
