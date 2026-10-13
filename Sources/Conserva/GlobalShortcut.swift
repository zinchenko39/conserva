import Carbon
import Foundation

/// One system-wide shortcut, registered with the Carbon hot key service: it fires in whatever app
/// is in front and, unlike watching the keyboard, asks the user for no permission.
///
/// Carbon hands the key press to a plain C function, so the handler cannot capture anything; the
/// shortcut passes itself in as the handler's user data and dispatches from there.
final class GlobalShortcut {
    private let action: () -> Void
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    init(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        self.action = action
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let shortcut = Unmanaged<GlobalShortcut>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { shortcut.action() }
            return noErr
        }, 1, &pressed, me, &handler)
        // Any four letters tell this app's hot keys from other apps'; there is only ever this one.
        let tag = EventHotKeyID(signature: OSType(0x4A41_5253), id: 1)  // "JARS"
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), tag, GetApplicationEventTarget(), 0, &hotKey)
        // Another app, or another copy of this one, may hold the combination already.
        registered = status == noErr
        if !registered { NSLog("Conserva: the shortcut could not be registered (status \(status))") }
    }

    /// False when the system refused the combination; the menu still works.
    private(set) var registered = false

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
