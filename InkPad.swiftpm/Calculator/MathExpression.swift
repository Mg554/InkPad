import Foundation

/// Reads and works out what the owner writes: "12 + 5×2", "√(9+16)",
/// "sin(30) + π". Pure arithmetic — no drawing, no network — so it can be
/// tested on its own.
enum MathExpression {
    /// Why an expression could not be read.
    enum Failure: Error, Equatable {
        /// Nothing was written.
        case empty
        /// The expression stops too early, e.g. "2 +".
        case unfinished
        /// A character that does not belong, e.g. "2 $ 3".
        case unexpected(String)
        /// A bracket is never closed.
        case unclosedBracket
        /// A name that is not a function or a constant, e.g. "foo(2)".
        case unknownName(String)
        /// Dividing by zero.
        case divisionByZero
        /// A number outside the function's range, e.g. "√(-4)".
        case outOfRange(String)
    }

    // MARK: Reading

    /// The value of an expression.
    static func value(of text: String) throws -> Double {
        let tokens = try tokenize(text)
        guard !tokens.isEmpty else { throw Failure.empty }
        var parser = Parser(tokens: tokens)
        let result = try parser.parseExpression()
        guard parser.isAtEnd else {
            throw Failure.unexpected(parser.describeCurrent())
        }
        return result
    }

    /// The expression as InkPad reads it: the numbers and signs written in
    /// handwriting, cleaned up.
    static func normalized(_ text: String) -> String {
        var result = ""
        for character in text {
            switch character {
            case "×", "✕", "x", "X", "⋅", "•":
                result.append("*")
            case "÷", "∕":
                result.append("/")
            case "−", "–", "—":
                result.append("-")
            case "√":
                result.append("sqrt(")
            case "π":
                result.append("pi")
            case "،", ",":
                result.append(".")
            case "٫":
                result.append(".")
            case "٪":
                result.append("%")
            case "²":
                result.append("^2")
            case "³":
                result.append("^3")
            case "＋":
                result.append("+")
            case "＝":
                result.append("=")
            case " ":
                continue
            default:
                result.append(character)
            }
        }
        // A closing bracket without an opening one is a slip of the pen.
        var fixed = ""
        var open = 0
        for character in result {
            if character == "(" { open += 1 }
            if character == ")" {
                if open == 0 { continue }
                open -= 1
            }
            fixed.append(character)
        }
        fixed.append(String(repeating: ")", count: open))
        return fixed
    }

    /// A number as it should be shown: no trailing zeros, no noise.
    static func format(_ value: Double) -> String {
        if value.isNaN { return "—" }
        if value.isInfinite { return value > 0 ? "∞" : "-∞" }
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int64(value))
        }
        let rounded = (value * 1e10).rounded() / 1e10
        var text = String(rounded)
        if text.contains("e") || text.contains("E") {
            return String(format: "%.6g", value)
        }
        if text.hasSuffix(".0") { text = String(text.dropLast(2)) }
        return text
    }

    // MARK: Tokens

    private enum Token: Equatable {
        case number(Double)
        case plus, minus, times, divide, power
        case leftBracket, rightBracket
        case bang, percent
        case name(String)
    }

    private static func tokenize(_ text: String) throws -> [Token] {
        var tokens: [Token] = []
        let characters = Array(text)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            switch character {
            case " ", "\t", "\n":
                index += 1
            case "+": tokens.append(.plus); index += 1
            case "-": tokens.append(.minus); index += 1
            case "*": tokens.append(.times); index += 1
            case "/": tokens.append(.divide); index += 1
            case "^": tokens.append(.power); index += 1
            case "(": tokens.append(.leftBracket); index += 1
            case ")": tokens.append(.rightBracket); index += 1
            case "!": tokens.append(.bang); index += 1
            case "%": tokens.append(.percent); index += 1
            case ".":
                // A lone dot is a number: ".5"
                guard let number = readNumber(characters, from: index) else {
                    throw Failure.unexpected(".")
                }
                tokens.append(.number(number.value))
                index = number.index
            case "0"..."9":
                guard let number = readNumber(characters, from: index) else {
                    throw Failure.unexpected(String(character))
                }
                tokens.append(.number(number.value))
                index = number.index
            case "a"..."z", "A"..."Z":
                var name = ""
                while index < characters.count, characters[index].isLetter {
                    name.append(characters[index])
                    index += 1
                }
                tokens.append(.name(name.lowercased()))
            default:
                throw Failure.unexpected(String(character))
            }
        }
        return tokens
    }

    /// A number written in digits, with a dot and an exponent.
    private static func readNumber(_ characters: [Character], from start: Int) -> (value: Double, index: Int)? {
        var index = start
        var text = ""
        while index < characters.count, characters[index].isNumber {
            text.append(characters[index])
            index += 1
        }
        if index < characters.count, characters[index] == "." {
            text.append(".")
            index += 1
            while index < characters.count, characters[index].isNumber {
                text.append(characters[index])
                index += 1
            }
        }
        // An exponent: 2e3
        if index < characters.count, characters[index] == "e" || characters[index] == "E" {
            var exponent = ""
            var look = index + 1
            if look < characters.count, characters[look] == "-" || characters[look] == "+" {
                exponent.append(characters[look])
                look += 1
            }
            var digits = ""
            while look < characters.count, characters[look].isNumber {
                digits.append(characters[look])
                look += 1
            }
            if !digits.isEmpty {
                text += "e" + exponent + digits
                index = look
            }
        }
        guard let value = Double(text) else { return nil }
        return (value, index)
    }

    // MARK: Parsing

    private struct Parser {
        let tokens: [Token]
        var index = 0

        var isAtEnd: Bool { index >= tokens.count }

        var current: Token? { index < tokens.count ? tokens[index] : nil }

        func describeCurrent() -> String {
            switch current {
            case .number(let value): return format(value)
            case .plus: return "+"
            case .minus: return "-"
            case .times: return "*"
            case .divide: return "/"
            case .power: return "^"
            case .leftBracket: return "("
            case .rightBracket: return ")"
            case .bang: return "!"
            case .percent: return "%"
            case .name(let name): return name
            case nil: return ""
            }
        }

        /// Sums and differences, left to right.
        mutating func parseExpression() throws -> Double {
            var value = try parseTerm()
            while true {
                switch current {
                case .plus:
                    index += 1
                    value += try parseTerm()
                case .minus:
                    index += 1
                    value -= try parseTerm()
                default:
                    return value
                }
            }
        }

        /// Products, quotients and the multiplication that is only implied,
        /// as in "2(3+4)" or "3π".
        mutating func parseTerm() throws -> Double {
            var value = try parseUnary()
            while true {
                switch current {
                case .times:
                    index += 1
                    value *= try parseUnary()
                case .divide:
                    index += 1
                    let divisor = try parseUnary()
                    guard divisor != 0 else { throw Failure.divisionByZero }
                    value /= divisor
                case .number, .name, .leftBracket:
                    // Written without a sign: 2π, 2(3+4), (1+2)(3+4).
                    value *= try parseUnary()
                default:
                    return value
                }
            }
        }

        /// A sign in front of a number or a bracket.
        mutating func parseUnary() throws -> Double {
            switch current {
            case .minus:
                index += 1
                return -(try parseUnary())
            case .plus:
                index += 1
                return try parseUnary()
            default:
                return try parsePower()
            }
        }

        /// Powers, from the right: 2^3^2 is 2^9.
        mutating func parsePower() throws -> Double {
            let base = try parsePostfix()
            guard case .power = current else { return base }
            index += 1
            let exponent = try parseUnary()
            let value = pow(base, exponent)
            guard value.isFinite else { throw Failure.outOfRange("the power") }
            return value
        }

        /// Factorials and percentages, written after the number.
        mutating func parsePostfix() throws -> Double {
            var value = try parsePrimary()
            while true {
                switch current {
                case .bang:
                    index += 1
                    value = try factorial(value)
                case .percent:
                    index += 1
                    value /= 100
                default:
                    return value
                }
            }
        }

        /// A number, a constant, a function or a bracket.
        mutating func parsePrimary() throws -> Double {
            switch current {
            case .number(let value):
                index += 1
                return value
            case .leftBracket:
                index += 1
                let value = try parseExpression()
                guard case .rightBracket = current else { throw Failure.unclosedBracket }
                index += 1
                return value
            case .name(let name):
                index += 1
                if name == "pi" { return .pi }
                if name == "e" { return M_E }
                guard let function = Function(name) else { throw Failure.unknownName(name) }
                // sqrt(9) and √9: the bracket may be left out.
                if case .leftBracket = current {
                    index += 1
                    let argument = try parseExpression()
                    guard case .rightBracket = current else { throw Failure.unclosedBracket }
                    index += 1
                    return try function.apply(argument)
                }
                guard case .number(let argument) = current else {
                    throw Failure.unfinished
                }
                index += 1
                return try function.apply(argument)
            case .none:
                throw Failure.unfinished
            case .some:
                throw Failure.unexpected(describeCurrent())
            }
        }

        /// n! for whole numbers up to 170.
        private func factorial(_ value: Double) throws -> Double {
            guard value >= 0, value.rounded() == value, value <= 170 else {
                throw Failure.outOfRange("the factorial")
            }
            var result = 1.0
            if value >= 2 {
                for step in 2...Int(value) {
                    result *= Double(step)
                }
            }
            return result
        }
    }

    /// The functions the calculator knows.
    private enum Function {
        case sine, cosine, tangent, arcsine, arccosine, arctangent
        case naturalLog, logarithm, squareRoot, absolute, exponential, round, floor, ceiling

        init?(_ name: String) {
            switch name {
            case "sin": self = .sine
            case "cos": self = .cosine
            case "tan": self = .tangent
            case "asin": self = .arcsine
            case "acos": self = .arccosine
            case "atan": self = .arctangent
            case "ln": self = .naturalLog
            case "log": self = .logarithm
            case "sqrt": self = .squareRoot
            case "abs": self = .absolute
            case "exp": self = .exponential
            case "round": self = .round
            case "floor": self = .floor
            case "ceil": self = .ceiling
            default: return nil
            }
        }

        /// The functions take degrees or radians? Radians, as in school
        /// mathematics, unless the owner wrote "sin30°".
        func apply(_ value: Double) throws -> Double {
            let radians = value * .pi / 180
            switch self {
            case .sine: return sin(radians)
            case .cosine: return cos(radians)
            case .tangent: return tan(radians)
            case .arcsine:
                guard value >= -1, value <= 1 else { throw Failure.outOfRange("arcsin") }
                return asin(value)
            case .arccosine:
                guard value >= -1, value <= 1 else { throw Failure.outOfRange("arccos") }
                return acos(value)
            case .arctangent: return atan(value)
            case .naturalLog:
                guard value > 0 else { throw Failure.outOfRange("ln") }
                return log(value)
            case .logarithm:
                guard value > 0 else { throw Failure.outOfRange("log") }
                return log10(value)
            case .squareRoot:
                guard value >= 0 else { throw Failure.outOfRange("sqrt") }
                return sqrt(value)
            case .absolute: return abs(value)
            case .exponential: return exp(value)
            case .round: return value.rounded()
            case .floor: return value.rounded(.down)
            case .ceiling: return value.rounded(.up)
            }
        }
    }
}
