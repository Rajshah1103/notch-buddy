import Carbon.HIToolbox

/// A system-wide keyboard shortcut. Needs no permission: it uses the Carbon hot key API, which is
/// still how launchers register theirs.
final class HotKey {
    private var reference: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    /// `modifiers` use Carbon flags: `controlKey`, `optionKey`, `cmdKey`, `shiftKey`.
    init?(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        self.action = action

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue().action()
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
        guard status == noErr else { return nil }

        let id = EventHotKeyID(signature: OSType(0x4E48_4B59), id: 1)   // "NHKY"
        guard RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &reference) == noErr
        else { return nil }
    }

    deinit {
        if let reference { UnregisterEventHotKey(reference) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
