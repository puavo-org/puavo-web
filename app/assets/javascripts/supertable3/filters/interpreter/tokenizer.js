// Filter expression tokenizer

// Raw token types
export const TokenType = {
    COLUMN: "col",            // target column name
    OPERATOR: "opr",          // comparison operator
    VALUE: "val",             // comparison value (whether it's a string or number is irrelevant here)
    OPEN_PAREN: "(",
    CLOSE_PAREN: ")",
    BOOL_AND: "and",
    BOOL_OR: "or",
    BOOL_NOT: "not",

    // Used during parsing to initialize the state machine to a known state.
    // Using this anywhere else will hurt you badly.
    START: "start",
};

// Raw token flags, set by the tokenizer
export const TokenFlags = {
    REGEXP: 0x01,       // This token contains a regexp string
    MULTILINE: 0x02,    // This string is multiline, ie. it containts embedded newlines (can be used with regexps)
};

export class Tokenizer {
    constructor()
    {
        this.columnDefinitions = null;
        this.logger = null;

        this.source = null;
        this.pos = 0;           // character position in the input stream
        this.row = 1;
        this.col = 1;
        this.startPos = 0;
        this.startRow = 1;
        this.startCol = 1;
        this.tokens = [];
    }

    addToken(type, token, flags=0)
    {
        this.tokens.push({
            type: type,
            str: token,
            flags: flags,

            // These are used in error reporting. They're not needed for anything else.
            row: this.startRow,
            col: this.startCol,
            pos: this.startPos,
            len: this.pos - this.startPos,
        });
    }

    done()
    {
        return this.pos >= this.source.length;
    }

    peek()
    {
        if (this.done())
            return null;

        return this.source[this.pos];
    }

    read()
    {
        const c = this.source[this.pos++];

        if (c == "\n") {
            this.row++;
            this.col = 0;
        }

        if (c != "\r") {
            // Transparently treat \n\r (or \r\n) newlines as just \n
            this.col++;
        }

        return c;
    }

    match(expected)
    {
        if (this.done())
            return false;

        if (this.source[this.pos] != expected)
            return false;

        this.pos++;
        this.col++;     // don't call match("\r") if you want the column number to be correct

        return true;
    }

    comment()
    {
        while (true) {
            if (this.peek() == "\n" || this.done())
                break;

            this.read();
        }
    }

    content(initial)
    {
        let quoted = false,
            escape = false,
            token = "",
            flags = 0;

        if (`"'/`.includes(initial)) {
            // We have three types of values/strings here: unquoted, quoted and regexp.
            // The only difference between quoted and regexp strings is the terminating
            // character. For unquoted strings, any unescaped whitespace or characters
            // that are actually part of the language syntax end the string.
            quoted = true;

            if (initial == "/")
                flags |= TokenFlags.REGEXP;
        } else {
            // Start the token with a non-quote character
            token += initial;
        }

        while (true) {
            if (this.done()) {
                if (quoted) {
                    this.logger.error("unterminated_string",
                                      this.startRow, this.startCol, this.startPos, this.col - this.startCol);
                    return true;
                }

                break;
            }

            // Can't use read() here, otherwise we can end up reading one character too far
            const c = this.peek();

            if (c == "\\") {
                escape = true;
                this.read();
                continue;
            }

            if (escape) {
                // Process escape codes
                switch (c) {
                    case "n":
                        token += "\n";
                        flags |= TokenFlags.MULTILINE;
                        break;

                    case "r":
                        token += "\r";
                        break;

                    case "t":
                        token += "\t";
                        break;

                    default:
                        // Unknown escape, pass it through as-is
                        token += `\\${c}`;
                        break;
                }
            } else {
                if (quoted) {
                    // For quoted strings, the initial character also ends the string
                    if (c == initial) {
                        this.read();
                        break;
                    }

                    if (c == "\n")
                        flags |= TokenFlags.MULTILINE;
                } else if (" \n\r\t()&|<>=!#".includes(c)) {
                    // Only these can end an unquoted string as they're part of the language itself
                    break;
                }

                token += c;
            }

            this.read();
            escape = false;
        }

        if (escape) {
            // Unfinished escape sequence (+1 to skip the escape character)
            this.logger.error("unexpected_end",
                              this.startRow, this.startCol, this.startPos, this.col - this.startCol + 1);
            return true;
        }

        // Quoted strings are hardcoded to always be values, but unquoted
        // strings are either values or column names
        if (!quoted && this.columnDefinitions.isColumn(token))
            this.addToken(TokenType.COLUMN, this.columnDefinitions.expandAlias(token), flags);
        else this.addToken(TokenType.VALUE, token, flags);

        return true;
    }

    token()
    {
        // Remember the starting position, so we'll know exact token locations and lengths
        this.startPos = this.pos;
        this.startRow = this.row;
        this.startCol = this.col;

        const c = this.read();

        switch (c) {
            case " ":
            case "\t":
            case "\n":
            case "\r":
                // Either already handled in read(), or we can skip these
                break;

            case "#":
                this.comment();
                break;

            case "=":
                // equality, permit "=" and "=="
                if (this.match("="))
                    this.addToken(TokenType.OPERATOR, "=");
                else this.addToken(TokenType.OPERATOR, "=");
                break;

            case "!":
                // ! (unary negation), != (inequality) or !! (database field presence check)
                if (this.match("="))
                    this.addToken(TokenType.OPERATOR, "!=");
                else if (this.match("!"))
                    this.addToken(TokenType.OPERATOR, "!!");
                else this.addToken(TokenType.BOOL_NOT, "!");
                break;

            case "<":
                // < or <=
                if (this.match("="))
                    this.addToken(TokenType.OPERATOR, "<=");
                else this.addToken(TokenType.OPERATOR, "<");
                break;

            case ">":
                // > or >=
                if (this.match("="))
                    this.addToken(TokenType.OPERATOR, ">=");
                else this.addToken(TokenType.OPERATOR, ">");
                break;

            case "&":
                // && (and)
                if (this.match("&"))
                    this.addToken(TokenType.BOOL_AND, "&&");
                else this.logger.error("unknown_operator", this.startRow, this.startCol, this.startPos, 2);
                break;

            case "|":
                // || (or)
                if (this.match("|"))
                    this.addToken(TokenType.BOOL_OR, "||");
                else this.logger.error("unknown_operator", this.startRow, this.startCol, this.startPos, 2);
                break;

            case "(":
                this.addToken(TokenType.OPEN_PAREN, "(");
                break;

            case ")":
                this.addToken(TokenType.CLOSE_PAREN, ")");
                break;

            default:
                // Could be a column name or a string, or a number, etc.
                if (this.content(c))
                    break;

                // I don't currently know any syntactical structure that could end up here
                this.logger.error("syntax_error", this.startRow, this.startCol, this.startPos, 1);
                break;
        }
    }

    tokenize(logger, columns, source)
    {
        this.columnDefinitions = columns;
        this.logger = logger;

        this.pos = 0;
        this.source = source;
        this.row = 1;
        this.col = 1;
        this.tokens = [];

        while (!this.done())
            this.token();
    }
}
