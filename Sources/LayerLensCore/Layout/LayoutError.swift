import Foundation

public enum LayoutError: Error, CustomStringConvertible, Sendable {
    case fileNotReadable(path: String, underlying: String)
    case malformedJSON(String)
    case missingField(String)
    case typeMismatch(String, expected: String)
    case invalidHexNumber(String)

    public var description: String {
        switch self {
        case .fileNotReadable(let path, let underlying):
            return "Could not read '\(path)': \(underlying)"
        case .malformedJSON(let msg):
            return "Malformed JSON: \(msg)"
        case .missingField(let field):
            return "Missing required field '\(field)'"
        case .typeMismatch(let field, let expected):
            return "Field '\(field)' has wrong type (expected \(expected))"
        case .invalidHexNumber(let raw):
            return "Could not parse hex number from '\(raw)'"
        }
    }
}
