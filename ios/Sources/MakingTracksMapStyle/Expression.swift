public enum Expression {
    public static func evaluate(_ expression: JSONValue, _ props: [String: JSONValue]) -> JSONValue {
        guard case let .array(items) = expression,
              case let .string(op)? = items.first
        else { return expression }

        switch op {
        case "get":
            guard items.count == 2, case let .string(key) = items[1] else { return .null }
            return props[key] ?? .null
        case "literal":
            guard items.count == 2 else { return .null }
            return items[1]
        case "==":
            guard items.count == 3 else { return .bool(false) }
            return .bool(evaluate(items[1], props) == evaluate(items[2], props))
        case "!":
            guard items.count == 2, case let .bool(value) = evaluate(items[1], props) else { return .bool(false) }
            return .bool(!value)
        case "all":
            return .bool(items.dropFirst().allSatisfy { expression in
                if case let .bool(value) = evaluate(expression, props) { return value }
                return false
            })
        case "case":
            guard items.count >= 4 else { return .null }
            var index = 1
            while index + 1 < items.count {
                if evaluate(items[index], props) == .bool(true) {
                    return evaluate(items[index + 1], props)
                }
                index += 2
            }
            return evaluate(items.last ?? .null, props)
        case "any":
            return .bool(items.dropFirst().contains { expression in
                if case let .bool(value) = evaluate(expression, props) { return value }
                return false
            })
        case "in":
            guard items.count == 3 else { return .bool(false) }
            let needle = evaluate(items[1], props)
            guard case let .array(haystack) = evaluate(items[2], props) else { return .bool(false) }
            return .bool(haystack.contains(needle))
        case "match":
            guard items.count >= 4 else { return .null }
            let input = evaluate(items[1], props)
            var index = 2
            while index + 1 < items.count {
                if evaluate(items[index], props) == input {
                    return evaluate(items[index + 1], props)
                }
                index += 2
            }
            return evaluate(items.last ?? .null, props)
        default:
            return expression
        }
    }
}
