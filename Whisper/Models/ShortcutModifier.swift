import AppKit

enum ShortcutModifier: String, CaseIterable, Identifiable {
    case function
    case command
    case option
    case control
    case shift

    var id: String { rawValue }

    var label: String {
        switch self {
        case .function: return "Fn"
        case .command: return "Cmd"
        case .option: return "Option"
        case .control: return "Control"
        case .shift: return "Shift"
        }
    }
    
    var flags: NSEvent.ModifierFlags {
        switch self {
        case .function: return .function
        case .command: return .command
        case .option: return .option
        case .control: return .control
        case .shift: return .shift
        }
    }
}
