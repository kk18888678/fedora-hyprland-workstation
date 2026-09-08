// Small, deterministic calculator for the Command Center.
// It intentionally supports arithmetic only and never evaluates JavaScript.

function trim(value) {
    return String(value || "").trim()
}

function expressionFromQuery(query) {
    var value = trim(query)
    if (value.charAt(0) === "=") value = value.slice(1).trim()
    else if (/^calc(?:ulator)?\s+/i.test(value)) value = value.replace(/^calc(?:ulator)?\s+/i, "")
    return value
}

function isExpressionQuery(query) {
    var expression = expressionFromQuery(query)
    if (expression === "" || !/[0-9]/.test(expression)) return false
    return /^[0-9+\-*/%().\s]+$/.test(expression)
}

function tokenize(expression) {
    var tokens = []
    var index = 0
    var previous = ""
    while (index < expression.length) {
        var character = expression.charAt(index)
        if (/\s/.test(character)) {
            index++
            continue
        }

        if (/[0-9.]/.test(character)) {
            var numberStart = index
            var dots = 0
            while (index < expression.length && /[0-9.]/.test(expression.charAt(index))) {
                if (expression.charAt(index) === ".") dots++
                index++
            }
            var numberText = expression.slice(numberStart, index)
            if (dots > 1 || numberText === ".") return { ok: false, error: "Invalid number." }
            var number = Number(numberText)
            if (!isFinite(number)) return { ok: false, error: "Number is out of range." }
            tokens.push({ type: "number", value: number })
            previous = "number"
            continue
        }

        if ("+-*/%".indexOf(character) >= 0) {
            var unary = (character === "+" || character === "-") &&
                (previous === "" || previous === "operator" || previous === "(")
            tokens.push({ type: "operator", value: unary ? (character === "+" ? "u+" : "u-") : character })
            previous = "operator"
            index++
            continue
        }

        if (character === "(") {
            tokens.push({ type: "leftParen", value: character })
            previous = "("
            index++
            continue
        }
        if (character === ")") {
            tokens.push({ type: "rightParen", value: character })
            previous = ")"
            index++
            continue
        }
        return { ok: false, error: "Only arithmetic expressions are supported." }
    }
    return { ok: true, tokens: tokens }
}

function precedence(operator) {
    if (operator === "u+" || operator === "u-") return 3
    if (operator === "*" || operator === "/" || operator === "%") return 2
    return 1
}

function isRightAssociative(operator) {
    return operator === "u+" || operator === "u-"
}

function toRpn(tokens) {
    var output = []
    var operators = []
    for (var i = 0; i < tokens.length; i++) {
        var token = tokens[i]
        if (token.type === "number") {
            output.push(token)
        } else if (token.type === "operator") {
            var currentPrecedence = precedence(token.value)
            while (operators.length > 0) {
                var top = operators[operators.length - 1]
                if (top.type !== "operator") break
                var topPrecedence = precedence(top.value)
                var shouldPop = isRightAssociative(token.value)
                    ? currentPrecedence < topPrecedence
                    : currentPrecedence <= topPrecedence
                if (!shouldPop) break
                output.push(operators.pop())
            }
            operators.push(token)
        } else if (token.type === "leftParen") {
            operators.push(token)
        } else if (token.type === "rightParen") {
            var foundLeft = false
            while (operators.length > 0) {
                var popped = operators.pop()
                if (popped.type === "leftParen") {
                    foundLeft = true
                    break
                }
                output.push(popped)
            }
            if (!foundLeft) return { ok: false, error: "Mismatched parentheses." }
        }
    }
    while (operators.length > 0) {
        var remaining = operators.pop()
        if (remaining.type === "leftParen") return { ok: false, error: "Mismatched parentheses." }
        output.push(remaining)
    }
    return { ok: true, tokens: output }
}

function evaluateRpn(tokens) {
    var stack = []
    for (var i = 0; i < tokens.length; i++) {
        var token = tokens[i]
        if (token.type === "number") {
            stack.push(token.value)
            continue
        }
        if (token.value === "u+" || token.value === "u-") {
            if (stack.length < 1) return { ok: false, error: "Incomplete expression." }
            var unaryValue = stack.pop()
            stack.push(token.value === "u-" ? -unaryValue : unaryValue)
            continue
        }
        if (stack.length < 2) return { ok: false, error: "Incomplete expression." }
        var right = stack.pop()
        var left = stack.pop()
        if ((token.value === "/" || token.value === "%") && right === 0) {
            return { ok: false, error: "Division by zero." }
        }
        var value
        if (token.value === "+") value = left + right
        else if (token.value === "-") value = left - right
        else if (token.value === "*") value = left * right
        else if (token.value === "/") value = left / right
        else if (token.value === "%") value = left % right
        else return { ok: false, error: "Unknown operator." }
        if (!isFinite(value)) return { ok: false, error: "Result is out of range." }
        stack.push(value)
    }
    if (stack.length !== 1) return { ok: false, error: "Incomplete expression." }
    return { ok: true, value: stack[0] }
}

function evaluateQuery(query) {
    if (!isExpressionQuery(query)) return { ok: false, error: "Not a calculator query." }
    var expression = expressionFromQuery(query)
    var tokenized = tokenize(expression)
    if (!tokenized.ok || tokenized.tokens.length === 0) return tokenized
    var rpn = toRpn(tokenized.tokens)
    if (!rpn.ok) return rpn
    var result = evaluateRpn(rpn.tokens)
    if (!result.ok) return result
    return {
        ok: true,
        expression: expression,
        value: result.value,
        display: String(Number(result.value.toPrecision(12)))
    }
}

if (typeof module !== "undefined") {
    module.exports = {
        expressionFromQuery: expressionFromQuery,
        isExpressionQuery: isExpressionQuery,
        evaluateQuery: evaluateQuery
    }
}
