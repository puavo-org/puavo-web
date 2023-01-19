/*
This is a modified Shunting Yard algorithm. It has been changed to only accept logical AND, OR
and NOT operators instead of addition and such. If you think about it, a "||" is "plus" because
either side being non-zero is enough, and "&&" is multiplication because both sides must be
non-zero. "!" is multiplying by -1. And for numbers, you only have 0 and 1 because a comparison
either succeeds (1) or fails (0). An unmodified Shunting Yard algorithm can therefore handle
logical expressions if you replace the operators and numbers.
*/

// Operators, their precedences and associativities
const Associativity = {
    LEFT: 0,
    RIGHT: 1
};

// If this table is reordered, you must change the parser above to match the new order
const SHUNTING_OPERATORS = [
    { op: '!', precedence: 4, assoc: Associativity.LEFT },
    { op: '&', precedence: 3, assoc: Associativity.LEFT },
    { op: '|', precedence: 2, assoc: Associativity.LEFT },
];

export class CodeGenerator {
    compile(input)
    {
        let output = [];

        let ops = [],       // operator stack
            pos = 0;

        // This was converted almost verbatim from the pseudocode given on the Wikipedia's
        // page about the Shunting Yard algorithm. If you want comments, read the page.
        while (pos < input.length) {
            const tok = input[pos];

            // Load a comparison result. All numbers are indexes to the results table.
            if (typeof(tok[0]) == "number") {
                output.push(tok);
                pos++;
                continue;
            }

            // Process an operator
            // tok[0] = operator token, tok[1] = index to OPERATORS[]
            switch (tok[0]) {
                case "!":
                case "&":
                case "|":
                {
                    const opIndex = tok[1],
                          thisOp = SHUNTING_OPERATORS[opIndex];

                    while (ops.length > 0) {
                        const top = ops[ops.length - 1];

                        if (top[0] != "(" &&
                            (SHUNTING_OPERATORS[top[1]].precedence > thisOp.precedence ||
                                (SHUNTING_OPERATORS[top[1]].precedence == thisOp.precedence &&
                                    thisOp.assoc == Associativity.LEFT))) {

                            output.push(top);
                            ops.pop();
                        } else break;
                    }

                    ops.push(tok);
                    break;
                }

                case "(":
                    ops.push(tok);
                    break;

                case ")": {
                    while (ops.length > 0) {
                        const top = ops[ops.length - 1];

                        if (top[0] != "(") {
                            output.push(top);
                            ops.pop();
                        } else break;
                    }

                    if (ops.length == 0)
                        throw new Error(`Mismatched parenthesis in Shunting Yard (1)`);

                    ops.pop();
                    break;
                }

                default:
                    throw new Error(`Unknown token "${tok[0]}"`);
            }

            pos++;
        }

        while (ops.length > 0) {
            const top = ops[ops.length - 1];

            if (top[0] == "(")
                throw new Error(`Mismatched parenthesis in Shunting Yard (2)`);

            output.push(top);
            ops.pop();
        }

        return output;
    }
}
