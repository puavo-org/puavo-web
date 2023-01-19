// Runs the filter program and returns true if the row matches
export function evaluateFilter(program, comparisonResults)
{
    let stack = [],
        a, b;

    // a simple RPN evaluator
    for (const instr of program) {
        switch (instr[0]) {
            case "!":
                if (stack.length < 1)
                    throw new Error("stack underflow while evaluating a logical NOT");

                a = stack.pop();
                stack.push(!a);
                break;

            case "&":
                if (stack.length < 2)
                    throw new Error("stack underflow while evaluating a logical AND");

                a = stack.pop();
                b = stack.pop();
                stack.push(a & b);
                break;

            case "|":
                if (stack.length < 2)
                    throw new Error("stack underflow while evaluating a logical OR");

                a = stack.pop();
                b = stack.pop();

                stack.push(a | b);
                break;

            default:
                // load comparison result
                stack.push(comparisonResults[instr[0]]);
                break;
        }
    }

    return stack[0];
}
