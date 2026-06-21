import Foundation

/// Minimal XML-RPC support for the legacy OpenSubtitles endpoint
/// (api.opensubtitles.org). Covers only the value types that API uses.
enum XmlRpcValue {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([XmlRpcValue])
    case structure([String: XmlRpcValue])

    var stringValue: String? {
        switch self {
        case .string(let value): return value
        case .int(let value): return String(value)
        case .double(let value): return String(value)
        case .bool(let value): return value ? "1" : "0"
        case .array, .structure: return nil
        }
    }

    var arrayValue: [XmlRpcValue]? {
        if case .array(let items) = self { return items }
        return nil
    }

    var structValue: [String: XmlRpcValue]? {
        if case .structure(let members) = self { return members }
        return nil
    }

    subscript(key: String) -> XmlRpcValue? {
        structValue?[key]
    }
}

enum XmlRpcError: Error {
    case malformedResponse
    case fault(message: String)
}

enum XmlRpcRequest {
    static func body(method: String, parameters: [XmlRpcValue]) -> Data {
        var xml = #"<?xml version="1.0"?>"#
        xml += "<methodCall><methodName>\(method)</methodName><params>"
        for parameter in parameters {
            xml += "<param><value>\(encode(parameter))</value></param>"
        }
        xml += "</params></methodCall>"
        return Data(xml.utf8)
    }

    private static func encode(_ value: XmlRpcValue) -> String {
        switch value {
        case .string(let value):
            return "<string>\(escape(value))</string>"
        case .int(let value):
            return "<int>\(value)</int>"
        case .double(let value):
            return "<double>\(value)</double>"
        case .bool(let value):
            return "<boolean>\(value ? 1 : 0)</boolean>"
        case .array(let items):
            let data = items.map { "<value>\(encode($0))</value>" }.joined()
            return "<array><data>\(data)</data></array>"
        case .structure(let members):
            let body = members
                .sorted { $0.key < $1.key }
                .map { "<member><name>\(escape($0.key))</name><value>\(encode($0.value))</value></member>" }
                .joined()
            return "<struct>\(body)</struct>"
        }
    }

    private static func escape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

/// Parses a `<methodResponse>` document into an `XmlRpcValue`. Throws
/// `XmlRpcError.fault` for `<fault>` responses.
final class XmlRpcResponseParser: NSObject, XMLParserDelegate {
    private enum Frame {
        case value(typed: XmlRpcValue?)
        case array([XmlRpcValue])
        case structure([String: XmlRpcValue])
        case member(name: String?, value: XmlRpcValue?)
    }

    private var stack: [Frame] = []
    private var text = ""
    private var root: XmlRpcValue?
    private var isFault = false

    static func parse(_ data: Data) throws -> XmlRpcValue {
        let delegate = XmlRpcResponseParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), let root = delegate.root else {
            throw XmlRpcError.malformedResponse
        }
        if delegate.isFault {
            throw XmlRpcError.fault(message: root["faultString"]?.stringValue ?? "unknown fault")
        }
        return root
    }

    // MARK: - XMLParserDelegate

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
        qualifiedName: String?, attributes: [String: String]
    ) {
        text = ""
        switch elementName {
        case "value": stack.append(.value(typed: nil))
        case "array": stack.append(.array([]))
        case "struct": stack.append(.structure([:]))
        case "member": stack.append(.member(name: nil, value: nil))
        case "fault": isFault = true
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(
        _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
        qualifiedName: String?
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "string":
            setTyped(.string(text))
        case "int", "i4":
            setTyped(.int(Int(trimmed) ?? 0))
        case "double":
            setTyped(.double(Double(trimmed) ?? 0))
        case "boolean":
            setTyped(.bool(trimmed == "1"))
        case "name":
            if case .member(_, let value) = stack.last {
                stack[stack.count - 1] = .member(name: text, value: value)
            }
        case "value":
            guard case .value(let typed) = stack.popLast() else { return }
            // An untyped <value>text</value> is a string per the spec.
            attach(typed ?? .string(text))
        case "member":
            guard case .member(let name, let value) = stack.popLast(),
                  case .structure(var members) = stack.last
            else { return }
            if let name, let value { members[name] = value }
            stack[stack.count - 1] = .structure(members)
        case "array":
            guard case .array(let items) = stack.popLast() else { return }
            setTyped(.array(items))
        case "struct":
            guard case .structure(let members) = stack.popLast() else { return }
            setTyped(.structure(members))
        default:
            break
        }
        text = ""
    }

    /// Records a completed typed value on the innermost open `<value>` frame.
    private func setTyped(_ value: XmlRpcValue) {
        guard case .value = stack.last else { return }
        stack[stack.count - 1] = .value(typed: value)
    }

    /// Hands a finished value to its parent container (or makes it the root).
    private func attach(_ value: XmlRpcValue) {
        switch stack.last {
        case .array(var items):
            items.append(value)
            stack[stack.count - 1] = .array(items)
        case .member(let name, _):
            stack[stack.count - 1] = .member(name: name, value: value)
        default:
            root = value
        }
    }
}
