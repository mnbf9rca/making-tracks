public enum Expression {
    public static func evaluate(_ expression: JSONValue, _ props: [String: JSONValue]) -> JSONValue {
        guard case let .array(items) = expression,
              case let .string(op)? = items.first
        else { return expression }

        switch op {
        case "get":
            guard items.count == 2, case let .string(key) = items[1] else { return .null }
            return props[key] ?? .null
        case "==":
            guard items.count == 3 else { return .bool(false) }
            return .bool(evaluate(items[1], props) == evaluate(items[2], props))
        case "match":
            guard items.count >= 4 else { return .null }
            let input = evaluate(items[1], props)
            var index = 2
            while index + 1 < items.count {
                if evaluate(items[index], props) == input {
                    return items[index + 1]
                }
                index += 2
            }
            return items.last ?? .null
        default:
            return expression
        }
    }
}
