import AppKit
import Observation
import SwiftUI

@Observable
class KeyboardManager {
    static let shared = KeyboardManager()
    
    enum Key: UInt16, CaseIterable {
        case c = 8
        case space = 49
        case escape = 53
        case j = 38
        case k = 40
        case l = 37
    }
    
    enum EventType {
        case down, up
    }
    
    struct KeyEvent: Equatable {
        let id = UUID() // Ensure uniqueness so onChange always fires
        let key: Key
        let type: EventType
        let isRepeat: Bool
        
        static func == (lhs: KeyEvent, rhs: KeyEvent) -> Bool {
            lhs.id == rhs.id
        }
    }
    
    private(set) var pressedKeys: Set<Key> = []
    private(set) var modifiers: NSEvent.ModifierFlags = []
    private(set) var lastEvent: KeyEvent?
    
    /// When false, KeyboardManager will ignore and pass through all events.
    /// Set this to true only when the target view (e.g., Editor) is focused.
    var isActive: Bool = false
    
    private var monitor: Any?
    
    private init() {
        setupMonitor()
    }
    
    private func setupMonitor() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self = self else { return event }
            
            if event.type == .flagsChanged {
                self.modifiers = event.modifierFlags
                return event
            }
            
            // If not active, pass through everything
            guard self.isActive else { return event }
            
            if let key = Key(rawValue: event.keyCode) {
                let isRepeat = event.isARepeat
                
                switch event.type {
                case .keyDown:
                    if !isRepeat { self.pressedKeys.insert(key) }
                    self.lastEvent = KeyEvent(key: key, type: .down, isRepeat: isRepeat)
                case .keyUp:
                    self.pressedKeys.remove(key)
                    self.lastEvent = KeyEvent(key: key, type: .up, isRepeat: false)
                default:
                    break
                }
                
                // Return nil to "consume" the event and prevent the system alert sound
                return nil
            }
            
            return event
        }
    }
    
    func isPressed(_ key: Key) -> Bool {
        return pressedKeys.contains(key)
    }
    
    var isCommandPressed: Bool { modifiers.contains(.command) }
    var isShiftPressed: Bool { modifiers.contains(.shift) }
    var isOptionPressed: Bool { modifiers.contains(.option) }
    
    deinit {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

// MARK: - SwiftUI Integration (Browser-like API)
extension View {
    /// Triggers when the key is pressed (matches browser's keydown).
    /// Prevents repeated triggers if the key is held down.
    func onKeyDown(_ key: KeyboardManager.Key, action: @escaping () -> Void) -> some View {
        self.onChange(of: KeyboardManager.shared.lastEvent) { _, event in
            if let event = event, event.key == key, event.type == .down, !event.isRepeat {
                action()
            }
        }
    }
    
    /// Triggers when the key is released (matches browser's keyup).
    func onKeyUp(_ key: KeyboardManager.Key, action: @escaping () -> Void) -> some View {
        self.onChange(of: KeyboardManager.shared.lastEvent) { _, event in
            if let event = event, event.key == key, event.type == .up {
                action()
            }
        }
    }
    
    /// Convenience modifier for a single tap (down phase only).
    func onKeyPress(_ key: KeyboardManager.Key, action: @escaping () -> Void) -> some View {
        self.onKeyDown(key, action: action)
    }
}
