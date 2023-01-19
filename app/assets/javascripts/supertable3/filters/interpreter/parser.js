import { TokenType } from "./tokenizer.js";

/*
This isn't a recursive-descent parser. It just looks at the current token and the token before
it, and makes all the decisions based on those two. This parser is only used to validate the
filter string and extract all comparisons into their own array. No AST is build. The remaining
tokens are stored in a new array that is then fed to the Shunting Yard algorithm.
*/

export class Parser {
    constructor()
    {
        this.columnDefinitions = null;
        this.logger = null;

        this.tokens = [];
        this.previous = TokenType.START;
        this.pos = 0;

        this.comparisons = [];
        this.output = [];
    }

    prev()
    {
        for (let i = 0; i < arguments.length; i++)
            if (this.previous == arguments[i])
                return true;

        return false;
    }

    peek()
    {
        if (this.pos + 1 >= this.tokens.length)
            return false;

        const type = this.tokens[this.pos + 1].type;

        for (let i = 0; i < arguments.length; i++)
            if (type == arguments[i])
                return true;

        return false;
    }

    // Adds a new comparison or finds the existing one. Always returns an index
    // to a comparison you can use to look up whatever you passed to this.
    comparison(column, operator, value)
    {
        for (let i = 0; i < this.comparisons.length; i++) {
            const c = this.comparisons[i];

            if (c.column.str == column.str &&
                c.operator.str == operator.str &&
                c.value.str == value.str &&
                c.value.flags == value.flags)
                return i;
        }

        this.comparisons.push({
            column: column,
            operator: operator,
            value: value,
        });

        return this.comparisons.length - 1;
    }

    parse(logger, columns, tokens, lastRow, lastCol)
    {
        this.columnDefinitions = columns;
        this.logger = logger;

        this.tokens = [...tokens];
        this.previous = TokenType.START;
        this.pos = 0;

        this.output = [];
        this.comparisons = [];

        let errors = false,
            nesting = 0,
            columnIndex = -1,
            operatorIndex = -1;

        while (this.pos < this.tokens.length) {
            const t = this.tokens[this.pos];

            switch (t.type) {
                case TokenType.START:
                    break;

                case TokenType.COLUMN:
                    if (this.prev(TokenType.START, TokenType.OPEN_PAREN,
                                  TokenType.BOOL_AND, TokenType.BOOL_OR, TokenType.BOOL_NOT)) {

                        // If there is no operator after this, then this is a shorthand "!!"
                        // syntax. Expand the shorthand by splicing two extra tokens into
                        // the stream after the column name. This is really ugly, but it works
                        // and it really does make writing filter expressions nicer.
                        if (this.pos + 1 >= this.tokens.length ||
                            this.peek(TokenType.BOOL_AND, TokenType.BOOL_OR, TokenType.CLOSE_PAREN)) {

                            let opr = {...t},
                                val = {...t};

                            opr.type = TokenType.OPERATOR;
                            opr.flags = 0;
                            opr.str = "!!";
                            opr.len = 2;

                            // Exists or not?
                            val.type = TokenType.VALUE;
                            val.flags = 0;
                            val.str = this.prev(TokenType.BOOL_NOT) ? "0" : "1";
                            val.len = 1;

                            if (this.prev(TokenType.BOOL_NOT)) {
                                // In this case, the negation before the colum name is part
                                // of the coercion. We don't want to negate the result of
                                // this test, so remove the negation from the opcodes.
                                // Ugly ugly ugly.
                                this.output.pop();
                            }

                            this.tokens.splice(this.pos + 1, 0, opr);
                            this.tokens.splice(this.pos + 2, 0, val);

                            // Then continue like nothing happened...
                        }

                        columnIndex = this.pos;
                        operatorIndex = -1;

                        break;
                    }

                    this.logger.errorToken("unexpected_column_name", t);
                    errors = true;
                    break;

                case TokenType.OPERATOR:
                    if (this.previous == TokenType.COLUMN) {
                        operatorIndex = this.pos;
                        break;
                    }

                    this.logger.errorToken("expected_column_name", t);
                    errors = true;
                    columnIndex = -1;
                    operatorIndex = -1;
                    break;

                case TokenType.VALUE:
                    if (this.previous == TokenType.OPERATOR) {
                        if (columnIndex == -1) {
                            this.logger.errorToken("expected_operator", t);
                            errors = true;
                            break;
                        }

                        const index = this.comparison(this.tokens[columnIndex],
                                                      this.tokens[operatorIndex],
                                                      this.tokens[this.pos]);

                        this.output.push([index, -1]);

                        columnIndex = -1;
                        operatorIndex = -1;
                        break;
                    }

                    if (this.previous == TokenType.COLUMN) {
                        this.logger.errorToken("expected_operator", t);
                        errors = true;
                    } else {
                        this.logger.errorToken("expected_column_name", t);
                        errors = true;
                    }

                    columnIndex = -1;
                    operatorIndex = -1;
                    break;

                case TokenType.BOOL_AND:
                    if (!this.prev(TokenType.VALUE, TokenType.CLOSE_PAREN)) {
                        this.logger.errorToken("expected_value_rpar", t);
                        errors = true;
                        break;
                    }

                    this.output.push(["&", 1]);
                    break;

                case TokenType.BOOL_OR:
                    if (this.previous == TokenType.COLUMN) {
                        this.logger.errorToken("expected_operator", t);
                        errors = true;
                        break;
                    }

                    if (!this.prev(TokenType.VALUE, TokenType.CLOSE_PAREN)) {
                        this.logger.errorToken("expected_value_rpar", t);
                        errors = true;
                        break;
                    }

                    this.output.push(["|", 2]);
                    break;

                case TokenType.BOOL_NOT:
                    if (!this.prev(TokenType.START, TokenType.BOOL_AND, TokenType.BOOL_OR,
                                   TokenType.BOOL_NOT, TokenType.OPEN_PAREN)) {
                        this.logger.errorToken("unexpected_negation", t);
                        errors = true;
                        break;
                    }

                    this.output.push(["!", 0]);
                    break;

                case TokenType.OPEN_PAREN:
                    if (!this.prev(TokenType.START, TokenType.VALUE,
                                   TokenType.BOOL_AND, TokenType.BOOL_OR, TokenType.BOOL_NOT,
                                   TokenType.OPEN_PAREN)) {
                        this.logger.errorToken("unexpected_lpar", t);
                        errors = true;
                        break;
                    }

                    nesting++;
                    this.output.push(["(", -1]);
                    break;

                case TokenType.CLOSE_PAREN:
                    if (!this.prev(TokenType.VALUE, TokenType.CLOSE_PAREN)) {
                        this.logger.errorToken("unexpected_rpar", t);
                        errors = true;
                        break;
                    }

                    if (nesting < 1) {
                        this.logger.errorToken("unbalanced_nesting", t);
                        errors = true;
                        return false;
                    }

                    nesting--;
                    this.output.push([")", -1]);
                    break;

                default:
                    this.logger.errorToken("syntax_error", t);
                    errors = true;
                    return false;
            }

            this.previous = t.type;
            this.pos++;
        }

        if (!this.prev(TokenType.START, TokenType.VALUE, TokenType.CLOSE_PAREN)) {
            this.logger.error("unexpected_end", lastRow, lastCol, this.pos);
            return false;
        }

        if (nesting != 0) {
            this.logger.error("unbalanced_nesting", lastRow, lastCol, this.pos);
            return false;
        }

        return !errors;
    }
}
