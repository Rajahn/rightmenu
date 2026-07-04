import Carbon
import Cocoa

final class GlobalHotKey {
    private let keyCode: UInt32
    private let modifiers: UInt32
    private let signature: OSType
    private let id: UInt32
    private let handler: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    init(keyCode: UInt32, modifiers: UInt32, signature: OSType, id: UInt32, handler: @escaping () -> Void) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.signature = signature
        self.id = id
        self.handler = handler
    }

    deinit {
        unregister()
    }

    func register() {
        unregister()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event,
                      let userData else {
                    return noErr
                }

                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else {
                    return status
                }

                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                guard hotKeyID.signature == hotKey.signature,
                      hotKeyID.id == hotKey.id else {
                    return noErr
                }

                DispatchQueue.main.async {
                    hotKey.handler()
                }
                return noErr
            },
            1,
            &eventType,
            userData,
            &eventHandlerRef
        )
        guard handlerStatus == noErr else {
            NSLog("RightMenu failed to install hotkey handler: %d", handlerStatus)
            return
        }

        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if registerStatus != noErr {
            NSLog("RightMenu failed to register clipboard history hotkey: %d", registerStatus)
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }
}

func fourCharCode(_ value: String) -> OSType {
    value.utf8.prefix(4).reduce(OSType(0)) { result, byte in
        (result << 8) + OSType(byte)
    }
}
