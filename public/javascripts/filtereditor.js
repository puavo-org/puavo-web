"use strict";

// The filter editor and the whole filtering subsystem of the SuperTable. Contains two filtering
// interfaces: a mouse-driven "traditional" one, and a more advanced system that uses a simple
// scripting language. Only one can be active at any given moment, but both are compiled down to a
// simple RPN "program" that is executed for every row on the table to see if it's visible or not.
// The table itself does not know anything about this, it only sees the final program.

// --------------------------------------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------
// COLUMN NAME LOOKUPS

/*
Each column can have zero or more (unique) alias names that all point to the actual name.
It's just a simple text replacement system. Some column names used in the raw JSON data
are very short and cryptic, so it's nice to have easy-to-remember aliases for them.
*/

class ColumnDefinitions {
    constructor(rawDefinitions)
    {
        this.columns = new Map();
        this.aliases = new Map();

        for (const key of Object.keys(rawDefinitions)) {
            const def = rawDefinitions[key];

            this.columns.set(key, {
                type: def.type,
                flags: def.flags || 0,
            });

            if ("alias" in def) {
                for (const a of def.alias) {
                    // Each alias name must be unique. Explode loudly if they aren't.
                    if (this.aliases.has(a))
                        throw new Error(`Alias "${a}" used by columns "${this.aliases.get(a)}" and "${key}"`);

                    this.aliases.set(a, key);
                }
            }
        }
    }

    isColumn(s)
    {
        return this.columns.has(s) || this.aliases.has(s);
    }

    // Expands an alias name. If the string isn't an alias, nothing happens.
    expandAlias(s)
    {
        if (!this.aliases.has(s))
            return s;

        return this.aliases.get(s);
    }

    // Retrieves a column definition by name. Bad things will happen if the name isn't valid.
    // (Use isColumn() to validate it first, and expandAlias() to get the full name.)
    get(s)
    {
        return this.columns.get(s);
    }

    getAliases(s)
    {
        let out = new Set();

        for (const a of this.aliases)
            if (a[1] == s)
                out.add(a[0]);

        return out;
    }
};

// A custom logger that also keeps track of row and column numbers and some other metadata
class MessageLogger {
    constructor()
    {
        this.messages = [];
    }

    empty()
    {
        return this.messages.length == 0;
    }

    haveErrors()
    {
        for (const m of this.messages)
            if (m.type == "error")
                return true;

        return false;
    }

    clear()
    {
        this.messages = [];
    }

    warn(message, row=-1, col=-1, pos=-1, len=-1, extra=null)
    {
        this.messages.push({
            type: "warning",
            message: message,
            row: row,
            col: col,
            pos: pos,
            len: len,
            extra: extra,
        });
    }

    warnToken(message, token, extra=null)
    {
        this.messages.push({
            type: "warning",
            message: message,
            row: token.row,
            col: token.col,
            pos: token.pos,
            len: token.len,
            extra: extra,
        });
    }

    error(message, row=-1, col=-1, pos=-1, len=-1, extra=null)
    {
        this.messages.push({
            type: "error",
            message: message,
            row: row,
            col: col,
            pos: pos,
            len: len,
            extra: extra,
        });
    }

    errorToken(message, token, extra=null)
    {
        this.messages.push({
            type: "error",
            message: message,
            row: token.row,
            col: token.col,
            pos: token.pos,
            len: token.len,
            extra: extra,
        });
    }
};

// --------------------------------------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------
// TOKENIZATION

// Raw token types
const TokenType = {
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
const TokenFlags = {
    REGEXP: 0x01,       // This token contains a regexp string
    MULTILINE: 0x02,    // This string is multiline (can be used with regexps)
};

class Tokenizer {
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
};

// --------------------------------------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------
// SYNTAX ANALYZER

/*
This isn't a recursive-descent parser. It just looks at the current token and the token before
it and makes all the decisions based on those. This parser is only used to validate the filter
string and move all comparisons into their own array. No AST is build. The remaining tokens
are stored in a new array that is then fed to the Shunting Yard algorithm.
*/

class Parser {
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
};

// --------------------------------------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------
// RPN CODE GENERATION

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

class CodeGenerator {
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
};

// --------------------------------------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------
// COMPARISON EVALUATORS

/*
The RPN program contains only binary logic. These evaluators actually figure out if the logic
values being tested are true (1) or false (0). They're "compiled" only once, but they must be
re-evaluated again for every row that is being checked.
*/

// All known operators
const KNOWN_OPERATORS = new Set(["=", "!=", "<", "<=", ">", ">=", "!!"]);

// Which operators can be used with different column types? For example, strings cannot
// be compared with < or > (actually they can be, but it won't result in what you expect).
const ALLOWED_OPERATORS = {
    [ColumnType.BOOL]: new Set(["=", "!=", "!!"]),
    [ColumnType.NUMERIC]: new Set(["=", "!=", "<", "<=", ">", ">=", "!!"]),
    [ColumnType.UNIXTIME]: new Set(["=", "!=", "<", "<=", ">", ">=", "!!"]),
    [ColumnType.STRING]: new Set(["=", "!=", "!!"]),
};

// Absolute ("YYYY-MM-DD HH:MM:SS") and relative ("-7d") time matchers
const ABSOLUTE_TIME = /^(?<year>\d{4})-?(?<month>\d{2})?-?(?<day>\d{2})? ?(?<hour>\d{2})?:?(?<minute>\d{2})?:?(?<second>\d{2})?$/,
      RELATIVE_TIME = /^(?<sign>(\+|-))?(?<value>(\d*))(?<unit>(s|h|d|w|m|y))?$/;

// Storage size matcher ("10M", "1.3G", "50%10G" and so on).
// XY or Z%XY, where X=value, Y=optional unit, Z=percentage. Permit floats, written with
// either commas or dots.
const STORAGE_PARSER = /^((?<percent>(([0-9]*[.,])?[0-9]+))%)?(?<value>(([0-9]*[.,])?[0-9]+))(?<unit>([a-zA-Z]))?$/;

// String->float, understands dots and commas (so locales that use dots or commas for
// thousands separating will work correctly)
function floatize(str)
{
    return parseFloat(str.replace(",", "."));
}

// Converts a "YYYY-MM-DD HH:MM:SS" into a Date object, but the catch is that you can omit
// the parts you don't need, ie. the more you specify, the more accurate it gets. Giving
// "2021" to this function returns 2021-01-01 00:00:00, "2021-05" returns 2021-05-01 00:00:00,
// "2021-05-27 19:37" returns 2021-05-27 19:37:00 and so on. The other format this function
// understands are relative times: if the input value is an integer, then it is added to the
// CURRENT time and returned. Negative values point to the past, positive point to the future.
function parseAbsoluteOrRelativeDate(str)
{
    let match = ABSOLUTE_TIME.exec(str);

    if (match !== null) {
        // Parse an absolute datetime

        // This should cut off after the first missing element (ie. if you omit the day,
        // then hours, minutes and seconds should not be set), but the regexp won't match
        // it then, so no harm done.
        const year = parseInt(match.groups.year, 10),
              month = parseInt(match.groups.month || "1", 10) - 1,
              day = parseInt(match.groups.day || "1", 10),
              hour = parseInt(match.groups.hour || "0", 10),
              minute = parseInt(match.groups.minute || "0", 10),
              second = parseInt(match.groups.second || "0", 10);

        let d = null;

        try {
            d = new Date();

            d.setFullYear(year);
            d.setMonth(month);
            d.setDate(day);
            d.setHours(hour);
            d.setMinutes(minute);
            d.setSeconds(second);
            d.setMilliseconds(0);       // the database values have only 1-second granularity
        } catch (e) {
            console.error(`parseAbsoluteOrRelativeDate(): can't construct an absolute Date object from "${str}":`);
            console.error(e);
            return null;
        }

        return d;
    }

    match = RELATIVE_TIME.exec(str);

    if (match === null) {
        // Don't know what this string means
        console.error(`parseAbsoluteOrRelativeDate(): "${str}" is neither absolute nor relative date`);
        return null;
    }

    // Parse a relative datetime
    let value = parseInt(match.groups.value, 10);

    // Scale
    switch (match.groups.unit) {
        default:
        case "s":
            // Seconds are the default, do nothing
            break;

        case "h":
            value *= 60 * 60;               // 1 hour in seconds
            break;

        case "d":
            value *= 60 * 60 * 24;          // 1 day in seconds
            break;

        case "w":
            value *= 60 * 60 * 24 * 7;      // 1 week in seconds
            break;

        case "m":
            value *= 60 * 60 * 24 * 30;     // 1 (30-day) month in seconds
            break;

        case "y":
            value *= 60 * 60 * 24 * 365;    // 1 year with 365 days (no leap year checks here)
            break;
    }

    // Sign
    if (match.groups.sign !== undefined) {
        if (match.groups.sign == "-")
            value *= -1;

        // Treat all other signs are +, even unknown ones (there shouldn't be any, since the
        // regexp rejects them)
    }

    let d = new Date();

    try {
        d.setSeconds(d.getSeconds() + value);
        d.setMilliseconds(0);       // the database values have only 1-second granularity
    } catch (e) {
        console.error(`parseAbsoluteOrRelativeDate(): can't construct a relative Date object from "${str}":`);
        console.error(e);
        return null;
    }

    return d;
}

class ComparisonCompiler {
    constructor()
    {
        this.logger = null;
    }

    // Parses and expands a value with unit, like "10M" or "10G" to a full number. Optionally
    // calculates a percentage value, like "50%10M" is equivalent to writing "5M".
    __parseStorage(valueToken)
    {
        const storage = STORAGE_PARSER.exec(valueToken.str.trim());

        if (storage === null) {
            // Just a number, no units or percentages
            try {
                const v = floatize(valueToken.str);

                if (isNaN(v)) {
                    console.error(`__parseStorage(): "${valueToken.str}" is not a valid number`);
                    this.logger.errorToken("not_a_number", valueToken);
                    return null;
                }

                return v;
            } catch (e) {
                console.error(`__parseStorage(): "${valueToken.str}" cannot be parsed as a float`);
                this.logger.errorToken("not_a_number", valueToken);
                return null;
            }
        }

        // The base value. It's easier if we treat everything here as a float.
        let value = 0;

        try {
            value = floatize(storage.groups.value);
        } catch (e) {
            console.error(`__parseStorage(): "${storage.groups.value}" cannot be parsed as a float`);
            this.logger.errorToken("not_a_number", valueToken);
            return null;
        }

        // Scale unit
        let unit = storage.groups.unit;

        if (unit === undefined || unit === null)
            unit = "B";

        switch (unit) {
            case "B":
                // bytes are the default, do nothing
                break;

            case "K":
                value *= 1024;
                break;

            case "M":
                value *= 1024 * 1024;
                break;

            case "G":
                value *= 1024 * 1024 * 1024;
                break;

            case "T":
                value *= 1024 * 1024 * 1024 * 1024;
                break;

            default:
                console.error(`__parseStorage(): invalid storage unit "${unit}"`);
                this.logger.errorToken("invalid_storage_unit", valueToken, unit);
                return null;
        }

        // Percentage
        let percent = storage.groups.percent;

        if (percent) {
            percent = Math.min(Math.max(floatize(percent), 0.0), 100.0);
            value *= percent / 100.0;
        }

        return value;
    }

    __compileBoolean(columnToken, operatorToken, valueToken)
    {
        return {
            column: columnToken.str,
            operator: operatorToken.str,
            value: ["1", "t", "y", "true", "yes", "on"].includes(valueToken.str.toLowerCase()),
            regexp: false
        };
    }

    __compileNumeric(columnToken, operatorToken, valueToken)
    {
        const colDef = this.columnDefs.get(this.columnDefs.expandAlias(columnToken.str));
        let value = undefined;

        if (colDef.flags & ColumnFlag.F_STORAGE) {
            // Parse a storage specifier, like "5M" or "10G"
            value = this.__parseStorage(valueToken);

            if (value === null)
                return null;
        } else {
            try {
                if (valueToken.str.indexOf(".") == -1 && valueToken.str.indexOf(",") == -1) {
                    // Integer
                    value = parseInt(valueToken.str, 10);
                } else {
                    // Float
                    value = floatize(valueToken.str);
                }

                if (isNaN(value))
                    throw new Error("not an integer");
            } catch (e) {
                console.error(`ComparisonCompiler::compile(): can't parse a number: ${e.message}`);
                console.error(e);
                this.logger.errorToken("not_a_number", valueToken);
                return null;
            }
        }

        return {
            column: columnToken.str,
            operator: operatorToken.str,
            value: value,
            regexp: false
        };
    }

    __compileUnixtime(columnToken, operatorToken, valueToken)
    {
        const out = parseAbsoluteOrRelativeDate(valueToken.str);

        if (out === null) {
            this.logger.errorToken("unparseable_time", valueToken);
            return false;
        }

        return {
            column: columnToken.str,
            operator: operatorToken.str,
            value: out.getTime() / 1000,        // convert to seconds
            regexp: false
        }
    }

    __compileString(columnToken, operatorToken, valueToken)
    {
        let regexp = false,
            value = undefined;

        if (valueToken.flags & TokenFlags.REGEXP) {
            // Compile a regexp
            try {
                value = new RegExp(valueToken.str.trim(),
                                   valueToken.flags & TokenFlags.MULTILINE ? "miu" : "iu"),
                regexp = true;
            } catch (e) {
                console.error(`ComparisonCompiler::compile(): regexp compilation failed: ${e.message}`);
                this.logger.errorToken("invalid_regexp", valueToken, e.message);
                return null;
            }
        } else {
            // A plain string, use as-is
            value = valueToken.str;
        }

        return {
            column: columnToken.str,
            operator: operatorToken.str,
            value: value,
            regexp: regexp
        };
    }

    // Takes a raw comparison (made of three tokens) and "compiles" it (ie. verifies the data
    // types, the comparison operator and the value, and converts the stringly-typed value into
    // "native" JavaScript type). Returns null if it failed.
    compile(logger, columns, columnToken, operatorToken, valueToken)
    {
        this.logger = logger;
        this.columnDefs = columns;

        // Validate the column and the operator
        if (!this.columnDefs.isColumn(columnToken.str)) {
            console.error(`ComparisonCompiler::compile(): unknown column "${columnToken.str}"`);
            this.logger.errorToken("unknown_column", columnToken);
            return null;
        }

        if (!KNOWN_OPERATORS.has(operatorToken.str)) {
            console.error(`ComparisonCompiler::compile(): invalid operator "${operatorToken.str}"`);
            this.logger.errorToken("invalid_operator", operatorToken);
            return null;
        }

        const colDef = this.columnDefs.get(this.columnDefs.expandAlias(columnToken.str));

        if (!ALLOWED_OPERATORS[colDef.type].has(operatorToken.str)) {
            console.error(`ComparisonCompiler::compile(): operator "${operatorToken.str}" cannot be used with column type "${colDef.type}"`);
            this.logger.errorToken("incompatible_operator", operatorToken);
            return null;
        }

        if (typeof(valueToken.str) != "string") {
            console.error(`ComparisonCompiler::compile(): value "${valueToken.str}" is not a string`);
            this.logger.errorToken("invalid_value", valueToken);
            return null;
        }

        // Interpret the comparison value and convert it into a "native" type
        if (operatorToken.str == "!!") {
            // Special case: always treat the value as boolean, regardless of what the column is
            return this.__compileBoolean(columnToken, operatorToken, valueToken);
        }

        switch (colDef.type) {
            case ColumnType.BOOL:
                return this.__compileBoolean(columnToken, operatorToken, valueToken);

            case ColumnType.NUMERIC:
                return this.__compileNumeric(columnToken, operatorToken, valueToken);

            case ColumnType.UNIXTIME:
                return this.__compileUnixtime(columnToken, operatorToken, valueToken);

            case ColumnType.STRING:
                return this.__compileString(columnToken, operatorToken, valueToken);

            default:
                console.error(`ComparisonCompiler::compile(): unhandled column type "${colDef.type}"`);
                this.logger.errorToken("unknown_error", columnToken);
                return null;
        }
    }
};

// Executes a comparison. Returns true if the comparison matches the tested value.
// Can (sorta) deal with NULL and undefined values.
function __compareSingleValue(cmp, value)
{
    if (cmp.operator != "!!") {
        if (value === undefined || value === null) {
            // Treat missing values as false. Actually comparing them with something
            // is nonsensical. Use the "!!" operator to test if those values actually
            // are present in the data.
            return false;
        }
    }

    switch (cmp.operator) {
        case "=":
            return cmp.regexp ? cmp.value.test(value) : cmp.value === value;

        case "!=":
            return !(cmp.regexp ? cmp.value.test(value) : cmp.value === value);

        case "<":
            return value < cmp.value;

        case "<=":
            return value <= cmp.value;

        case ">":
            return value > cmp.value;

        case ">=":
            return value >= cmp.value;

        case "!!":
            return cmp.value != (value === null || value === undefined);

        default:
            throw new Error(`compare(): unknown operator "${cmp.operator}"`);
    }
}

// Executes a single comparison against a row value. Deals with arrays and NULL/undefined
// data. Returns true if the comparison matched.
function compareRowValue(value, cmp)
{
    if (value !== undefined && value !== null && Array.isArray(value)) {
        // Loop over multiple values. Currently only string arrays are supported,
        // because no other types of arrays exists in the database.
        if (cmp.operator == "=") {
            for (const v of value)
                if (__compareSingleValue(cmp, v))
                    return true;

            return false;
        }

        // Assume "!=" because there are only two usable operators with strings
        for (const v of value)
            if (!__compareSingleValue(cmp, v))
                return false;

        return true;
    }

    // Just one value
    return __compareSingleValue(cmp, value);
}

// Runs the filter program and returns true if the row matches
function evaluateFilter(program, comparisonResults)
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

// --------------------------------------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------
// THE FILTER EDITOR USER INTERFACE

// All known operators and which column types they can be used with
const OPERATORS = {
    "=": {
        allowed: new Set([ColumnType.BOOL, ColumnType.NUMERIC, ColumnType.UNIXTIME, ColumnType.STRING]),
        multiple: true,
    },

    "!=": {
        allowed: new Set([ColumnType.BOOL, ColumnType.NUMERIC, ColumnType.UNIXTIME, ColumnType.STRING]),
        multiple: true,
    },

    "<": {
        allowed: new Set([ColumnType.NUMERIC, ColumnType.UNIXTIME]),
        multiple: false,
    },

    "<=": {
        allowed: new Set([ColumnType.NUMERIC, ColumnType.UNIXTIME]),
        multiple: false,
    },

    ">": {
        allowed: new Set([ColumnType.NUMERIC, ColumnType.UNIXTIME]),
        multiple: false,
    },

    ">=": {
        allowed: new Set([ColumnType.NUMERIC, ColumnType.UNIXTIME]),
        multiple: false,
    },

    // interval (closed)
    "[]": {
        allowed: new Set([ColumnType.NUMERIC, ColumnType.UNIXTIME]),
        multiple: true,
    },

    // reverse interval (closed)
    "![]": {
        allowed: new Set([ColumnType.NUMERIC, ColumnType.UNIXTIME]),
        multiple: true,
    },
};

const ColumnTypeStrings = {
    [ColumnType.BOOL]: "boolean",
    [ColumnType.NUMERIC]: "numeric",
    [ColumnType.UNIXTIME]: "unixtime",
    [ColumnType.STRING]: "string",
};

function makeRandomID()
{
    const CHARS = "abcdefghijklmnopqrstuvwxyz";
    let out = "";

    for (let i = 0; i < 20; i++)
        out += CHARS.charAt(Math.floor(Math.random() * CHARS.length));

    return out;
}

let filterID_ = 1;

function nextFilterID()
{
    return filterID_++;
}

function hideElements()
{
    for (let i = 0; i < arguments.length; i++)
        arguments[i].classList.add("hidden");
}

function showElements()
{
    for (let i = 0; i < arguments.length; i++)
        arguments[i].classList.remove("hidden");
}

function humanOperatorName(operator)
{
    switch (operator) {
        case "=": return "=";
        case "!=": return "≠";
        case "<": return "<";
        case "<=": return "≤";
        case ">": return ">";
        case ">=": return "≥";
        case "[]": return _tr("tabs.filtering.pretty.interval");
        case "![]": return _tr("tabs.filtering.pretty.not_interval");

        default:
            throw new Error(`humanOperatorName(): invalid operator "${operator}"`);
    }
}

// Single editable filter
class EditableFilter {
constructor()
{
    this.active = false;
    this.column = null;
    this.operator = null;
    this.values = [];

    // Current data being edited (the original data is not overwritten until "Save" is pressed)
    this.editColumn = null;
    this.editOperator = null;
    this.editValues = null;

    // True if this is a brand new filter that hasn't been saved yet. Changes how some
    // operations work (or don't work).
    this.isNew = false;

    // Editor child class (see below)
    this.editor = null;
}

beginEditing()
{
    this.editColumn = this.column;
    this.editOperator = this.operator;
    this.editValues = [...this.values];

    // The editor is created elsewhere
}

finishEditing()
{
    // Overwrite old values
    this.column = this.editColumn;
    this.operator = this.editOperator;
    this.values = this.editor.getData();
}

cancelEditing()
{
    this.editColumn = null;
    this.editOperator = null;
    this.editValues = null;

    // The editor is destroyed elsewhere
}

// Parses a "raw" filter stored as [active?, column, operator, value1, value2, ... valueN].
// Returns true if OK.
load(raw, columnDefinitions)
{
    if (!Array.isArray(raw) || raw.length < 4) {
        console.error(`EditableFilter::fromRaw(): invalid/incomplete raw filter:`);
        console.error(raw);
        return false;
    }

    // The column must be valid. We can tolerate/fix almost everything else, but not this.
    if (!(raw[1] in columnDefinitions)) {
        console.warn(`EditableFilter::fromRaw(): column "${raw[1]}" is not valid`);
        return false;
    }

    this.active = (raw[0] === true || raw[0] === 1) ? 1 : 0;
    this.column = raw[1];
    this.operator = raw[2];
    this.values = raw.slice(3);

    // Reset invalid operators to "=" because it's the least destructive of them all,
    // and I'd wager that most filters are simple equality checks
    if (!(this.operator in OPERATORS)) {
        console.warn(`EditableFilter::fromRaw(): operator "${this.operator}" is not valid, resetting it to "="`);
        this.operator = "=";
    }

    // Is the operator usable with this column type?
    const opDef = OPERATORS[this.operator],
          colDef = columnDefinitions[this.column];

    if (!opDef.allowed.has(colDef.type)) {
        console.warn(`EditableFilter::fromRaw(): operator "${this.operator}" cannot be used with ` +
                     `column type "${ColumnTypeStrings[colDef.type]}" (column "${this.column}"), ` +
                     `resetting to "="`);
        this.operator = "=";
    }

    // Handle storage units. Remove invalid values.
    if (colDef.flags & ColumnFlag.F_STORAGE) {
        let proper = [];

        // Remove invalid entries
        for (const v of this.values) {
            try {
                const m = STORAGE_PARSER.exec(v.toString().trim());

                if (m !== null) {
                    const unit = (m.groups.unit === undefined || m.groups.unit === null) ? "B" : m.groups.unit;
                    proper.push(`${m.groups.value}${unit}`);
                }
            } catch (e) {
                console.error(e);
                continue;
            }
        }

        this.values = proper;
    }

    // Check time strings
    if (colDef.type == ColumnType.UNIXTIME) {
        let proper = [];

        for (const v of this.values) {
            try {
                if (parseAbsoluteOrRelativeDate(v) !== null)
                    proper.push(v);
            } catch (e) {
                console.error(e);
                continue;
            }
        }

        this.values = proper;
    }

    if (this.values.length == 0) {
        // Need to do this check again, because we might have altered the values
        console.error(`EditableFilter::fromRaw(): filter has no values at all`);
        return false;
    }

    // Ensure there's the required number of values for this operator
    if (this.operator == "[]" || this.operator == "![]") {
        if (this.values.length == 1) {
            console.warn(`EditableFilter::fromRaw(): need more than one value, duplicating the single value`);
            this.values.push(this.values[0]);
        } else if (this.values.length > 2) {
            console.warn(`EditableFilter::fromRaw(): intervals can use only two values, removing extras`);
            this.values = [this.values[0], this.values[1]];
        }
    }

    if (this.values.length > 1 && opDef.multiple !== true) {
        console.warn(`EditableFilter::fromRaw(): operator "${this.operator}" cannot handle multiple values, extra values removed`);
        this.values = [this.values[0]];
    }

    return true;
}

save()
{
    return [this.active, this.column, this.operator].concat(this.values);
}

};  // class EditableFilter

class FilterEditorBase {
constructor(container, filter, definition)
{
    // Target filter
    this.filter = filter;

    // Does this filter target RAM/HD sizes?
    this.isStorage = (definition.flags & ColumnFlag.F_STORAGE) ? true : false;

    // Where to put the editor interface
    this.container = container;

    // Unique UI element prefix
    this.id = makeRandomID();

    // UI properties
    this.defaultValue = "";
    this.fieldSize = 50;
    this.maxLength = "";
}

buildUI()
{
}

operatorHasChanged(operator)
{
    this.buildUI();
}

getData()
{
    return this.filter.editValues;
}

// Return [state, message], if state is true then the data is valid, otherwise the
// message is displayed and the filter is NOT saved (and the editor does not close).
validate()
{
    return [true, null];
}

// Accessing this.container.query... is so frequent that here's two helpers for it
$(query) { return this.container.querySelector(query); }
$all(query) { return this.container.querySelectorAll(query); }

createValueRow(value, showButtons=true, title=null)
{
    let row = document.createElement("tr"),
        html = "";

    if (title !== null)
        html += `<td>${title}</td>`;

    html += `<td><div class="flex flex-cols flex-gap-5px">`;

    value = value.toString();

    if (this.isStorage) {
        // Make a unit selector combo box and strip the unit from the value
        const unit = value.length > 1 ? value.toString().slice(value.length - 1) : null;

        html += `<input type="text" size="${this.fieldSize}" maxlen="" value="${value.length > 1 ? value.slice(0, value.length - 1) : value}">`;

        html += "<select>";

        for (const u of [["B", "B"], ["KiB", "K"], ["MiB", "M"], ["GiB", "G"], ["TiB", "T"]])
            html += `<option data-unit="${u[1]}" ${u[1] == unit ? "selected" : ""}>${u[0]}</option>`;

        html += "</select>";
    } else {
        html += `<input type="text" size="${this.fieldSize}" maxlength="${this.maxLength}" value="${value}">`;
    }

    if (showButtons) {
        html += `<button>+</button>`;
        html += `<button>-</button>`;
    }

    html += "</div></td>";

    row.innerHTML = html;

    if (showButtons)
        this.addEventHandlers(row);

    return row;
}

// +/- button click handlers
addEventHandlers(row)
{
    // The button positions change if the unit combo box is on the row
    const add = this.isStorage ? 2 : 1,
          del = this.isStorage ? 3 : 2;

    row.children[0].children[0].children[add].addEventListener("click", (e) => this.duplicateRow(e));
    row.children[0].children[0].children[del].addEventListener("click", (e) => this.removeRow(e));
}

duplicateRow(e)
{
    let thisRow = e.target.parentNode.parentNode.parentNode,
        newRow = thisRow.cloneNode(true);

    if (this.isStorage) {
        // Turns out that selectedIndex is not part of the DOM. Thank you, JavaScript.
        // This is so ugly.
        newRow.children[0].children[0].children[1].selectedIndex =
            thisRow.children[0].children[0].children[1].selectedIndex;
    }

    this.addEventHandlers(newRow);
    thisRow.parentNode.insertBefore(newRow, thisRow.nextSibling);
}

removeRow(e)
{
    let thisRow = e.target.parentNode.parentNode.parentNode;

    thisRow.parentNode.removeChild(thisRow);

    // There must be at least one value at all times, even if it's empty
    if (this.$all(`table#values tr`).length == 0) {
        console.log("Creating a new empty value row");
        this.$("table#values").appendChild(this.createValueRow(this.defaultValue));
    }
}
};  // class FilterEditorBase

class FilterEditorBoolean extends FilterEditorBase {
buildUI()
{
    // HAX!
    if (this.filter.editValues.length == 0 || (this.filter.editValues[0] !== 1 && this.filter.editValues[0] !== 0))
        this.filter.editValues = [1];

    this.container.innerHTML =
`<div class="flex flex-rows flex-gap-5px">
<span><input type="radio" name="${this.id}-value" id="${this.id}-true" ${this.filter.editValues[0] === 1 ? "checked" : ""}><label for="${this.id}-true">${_tr('tabs.filtering.ed.bool.t')}</label></span>
<span><input type="radio" name="${this.id}-value" id="${this.id}-false" ${this.filter.editValues[0] !== 1 ? "checked" : ""}><label for="${this.id}-false">${_tr('tabs.filtering.ed.bool.f')}</label></span>
</div>`;

    this.$(`#${this.id}-true`).addEventListener("click", () => { this.filter.editValues = [1]; });
    this.$(`#${this.id}-false`).addEventListener("click", () => { this.filter.editValues = [0]; });
}

getData()
{
    return [this.filter.editValues[0] === 1 ? 1 : 0];
}
};  // class FilterEditorBoolean

class FilterEditorString extends FilterEditorBase {
buildUI()
{
    this.container.innerHTML = `<p>${this.getExplanation()}</p><table id="values"></table>`;
    let table = this.$("table#values");

    for (const v of this.filter.editValues)
        table.appendChild(this.createValueRow(v));
}

getData()
{
    let values = [];

    for (const i of this.$all(`table#values tr input[type="text"]`))
        values.push(i.value.trim());

    return values;
}

operatorHasChanged(operator)
{
    this.$("p").innerHTML = this.getExplanation();
}

getExplanation()
{
    let out = "";

    out += _tr("tabs.filtering.ed.multiple");
    out += " ";
    out += _tr((this.filter.editOperator == "=") ? "tabs.filtering.ed.one_hit_is_enough" : "tabs.filtering.ed.no_hits_allowed");
    out += " ";
    out += _tr("tabs.filtering.ed.regexp");

    return out;
}
};  // class FilterEditorString

class FilterEditorNumeric extends FilterEditorBase {
constructor(container, filter, definition)
{
    super(container, filter, definition);

    this.defaultValue = this.isStorage ? "0M" : "0";
    this.fieldSize = 10;
    this.maxLength = "32";
}

buildUI()
{
    const id = this.id;
    const opr = this.filter.editOperator;

    if (opr == "[]" || opr == "![]") {
        let help = "";

        if (opr == "[]")
            help += _tr("tabs.filtering.ed.closed");
        else help += _tr("tabs.filtering.ed.open");

        this.container.innerHTML = `<p>${help}${this.getExtraHelp()}</p><table id="values"></table>`;

        if (this.filter.editValues.length == 1) {
            // If you change the operator from a single-value to range, there is no second value yet
            this.filter.editValues.push(this.filter.editValues[0]);
        }

        let table = this.$("table#values");

        table.appendChild(this.createValueRow(this.filter.editValues[0], false, "Min:"));
        table.appendChild(this.createValueRow(this.filter.editValues[1], false, "Max:"));
    } else if (opr == "=" || opr == "!=") {
        let html = `<p>${_tr("tabs.filtering.ed.multiple")}`;

        html += " ";
        html += _tr((opr == "=") ? "tabs.filtering.ed.one_hit_is_enough" : "tabs.filtering.ed.no_hits_allowed");
        html += " ";

        html += `${this.getExtraHelp()}</p><table id="values"></table>`;

        this.container.innerHTML = html;

        let table = this.$("table#values");

        for (const v of this.filter.editValues)
            table.appendChild(this.createValueRow(v));
    } else {
        this.container.innerHTML = `<p>${_tr("tabs.filtering.ed.single")}${this.getExtraHelp()}</p><table id="values"></table>`;
        this.$("table#values").appendChild(this.createValueRow(this.filter.editValues[0], false));
    }
}

getData()
{
    const interval = (this.filter.editOperator == "[]" || this.filter.editOperator == "![]");
    let values = [];

    // This assumes validate() has been called first and the data is actually valid
    for (const i of this.$all(`table#values tr input[type="text"]`)) {
        let n = i.value.trim();

        if (n.length == 0)
            continue;

        try {
            n = floatize(n);
        } catch (e) {
            continue;
        }

        if (isNaN(n))
            continue;

        if (this.isStorage) {
            const s = i.parentNode.children[1];
            values.push(`${n}${s.options[s.selectedIndex].dataset.unit}`);  // put the unit back
        } else values.push(n);
    }

    // min > max, swap
    // TODO: Make this work with storage
    if (!this.isStorage && interval && values[0] > values[1])
        values = [values[1], values[0]];

    return values;
}

validate()
{
    const interval = (this.filter.editOperator == "[]" || this.filter.editOperator == "![]");
    let valid = 0;

    for (const i of this.$all(`table#values tr input[type="text"]`)) {
        let n = i.value.trim();

        if (n.length == 0)
            continue;

        try {
            n = floatize(n);
        } catch (e) {
            return [false, `"${i.value.trim()}" ` + _tr("tabs.filtering.ed.numeric.nan")];
        }

        if (isNaN(n))
            return [false, `"${i.value.trim()}" `+ _tr("tabs.filtering.ed.numeric.nan")];

        if (this.isStorage && n < 0)
            return [false, _tr("tabs.filtering.ed.numeric.negative_storage")];

        valid++;
    }

    if (interval && valid < 2)
        return [false, _tr("tabs.filtering.ed.invalid_interval")];

    if (!interval && valid == 0)
        return [false, _tr("tabs.filtering.ed.no_values")];

    return [true, null];
}

getExtraHelp()
{
    return "";
}
};  // class FilterEditorNumeric

class FilterEditorUnixtime extends FilterEditorNumeric {
constructor(container, filter, definition)
{
    super(container, filter, definition);

    // Use today's date as the default value
    const d = new Date();

    this.defaultValue = `${d.getFullYear()}-` +
                        `${String(d.getMonth() + 1).padStart(2, "0")}-` +
                        `${String(d.getDate()).padStart(2, "0")}`;

    this.fieldSize = 20;
    this.maxLength = "20";
}

buildUI()
{
    super.buildUI();
    this.$(`a#${this.id}-help`).addEventListener("click", (e) => this.showHelp(e));
}

getData()
{
    let values = [];

    // Unlike numbers, attempt no string->int conversions here. The filter compiler
    // engine will deal with interpreting absolute and relative time values.
    for (const i of this.$all(`table#values tr input[type="text"]`)) {
        const v = i.value.trim();

        if (v.length == 0)
            continue;

        values.push(v);
    }

    return values;
}

validate()
{
    const interval = (this.filter.editOperator == "[]" || this.filter.editOperator == "![]");
    let valid = 0;

    for (const i of this.$all(`table#values tr input[type="text"]`)) {
        const v = i.value.trim();

        if (v.length == 0)
            continue;

        if (parseAbsoluteOrRelativeDate(v) === null)
            return [false, `"${v}"` + _tr("tabs.filtering.ed.time.invalid")];

        valid++;
    }

    if (interval && valid < 2)
        return [false, _tr("tabs.filtering.ed.invalid_interval")];

    if (!interval && valid == 0)
        return [false, _tr("tabs.filtering.ed.no_values")];

    return [true, null];
}

getExtraHelp()
{
    return ` <a href="#" id="${this.id}-help"> ${_tr("tabs.filtering.ed.time.help_link")}</a>.`;
}

showHelp(e)
{
    e.preventDefault();
    window.alert(_tr("tabs.filtering.ed.time.help"));
}
};  // class FilterEditorUnixtime

const RowElem = {
    BTN_DELETE: 1,
    BTN_DUPLICATE: 2,
    CB_ACTIVE: 3,
    DIV_PRETTY: 4,
    DIV_EDITOR: 5,
};

class FilterEditor {

constructor(parentClass, container, columnDefinitions, columnTitles, filterPresets, filterDefaults, isAdvanced)
{
    // Who do we tell about filter changes?
    this.parentClass = parentClass;

    // This container is our playground. Everything we put on the screen, it's
    // inside this HTML element.
    this.container = container;

    // Column definitions
    this.plainColumnDefinitions = columnDefinitions;
    this.columnDefinitions = new ColumnDefinitions(columnDefinitions);
    this.columnTitles = columnTitles;

    this.updateColumnHelp = true;
    this.haveHelp = false;
    this.changed = false;
    this.isAdvanced = isAdvanced;

    this.filterPresets = filterPresets;

    this.filters = {};      // the traditional filters
    this.showJSON = false;
    this.defaultFilter = filterDefaults[0];

    // The current filter programs. One for the old-style filters, one for the advanced filter.
    this.comparisons = [];
    this.program = [];
    this.comparisonsAdvanced = [];
    this.programAdvanced = [];

    // JS event handling shenanigans
    this.onDeleteFilter = this.onDeleteFilter.bind(this);
    this.onDuplicateFilter = this.onDuplicateFilter.bind(this);
    this.onActiveFilter = this.onActiveFilter.bind(this);
    this.onClickColumnName = this.onClickColumnName.bind(this);

    this.buildUI();
    this.enableOrDisable(false);
}

buildUI()
{
    const havePresets = Object.keys(this.filterPresets[0]).length > 0,
          haveAdvancedPresets = Object.keys(this.filterPresets[1]).length > 0;

    let html = "";

    html += `<div id="traditional" class="filterEditorWrapper">`;

    html +=
`<div class="flex flex-rows flex-gap-5px"><div class="flex flex-cols flex-gap-5px">
<button id="deleteAll" class="danger" title="${_tr("tabs.filtering.delete_all_title")}">${_tr("tabs.filtering.delete_all")}</button>
<button id="toggleJSON" title="${_tr("tabs.filtering.toggle_json_title")}">${_tr("tabs.filtering.show_json")}</button>
<button id="saveJSON" class="hidden" title="${_tr("tabs.filtering.save_json_title")}">${_tr("tabs.filtering.save_json")}</button>
</div><textarea id="json" rows="5" class="width-100p jsonEditor hidden" title="${_tr("tabs.filtering.json_title")}"></textarea>
<table class="filtersTable"></table>
<div><button id="new">${_tr("tabs.filtering.new_filter")}</button></div>`;

    if (havePresets) {
        const presets = this.filterPresets[0];

        html += `<div><details><summary>${_tr('tabs.filtering.presets.title')}</summary>`;
        html += `<div class="flex flex-rows flex-gap-5px margin-top-10px">`;
        html += `<p class="margin-0 padding-0">${_tr("tabs.filtering.presets.click_to_add")}</p>`;
        html += `<span><input type="checkbox" id="append-at-end" checked><label for="append-at-end">${_tr('tabs.filtering.presets.append')}</label></span>`;
        html += `<ul class="margin-0 padding-0 no-list-bullets" id="presets">`;

        for (const key of Object.keys(presets))
            html += `<li><a href="#" data-id="${key}">${presets[key].title}</a></li>`;

        html += `</ul></details></div></div>`;
    }

    html += `</div>`;
    html += `</div>`;
    html += `<div id="advanced">`;

    html +=
`<div class="flex flex-columns flex-gap-10px width-100p">
<fieldset class="width-66p">
<legend>${_tr('tabs.filtering.expression_title')}</legend>
<textarea id="filter" placeholder="${_tr('tabs.filtering.expression_placeholder')}" rows="5"></textarea>
<div class="flex flex-columns flex-gap-5px margin-top-5px">
<button id="save" disabled>${_tr('tabs.filtering.save')}</button>
<button id="clear" disabled>${_tr('tabs.filtering.clear')}</button>
</div>
</fieldset>

<fieldset class="width-33p">
<legend>${_tr('tabs.filtering.messages_title')}</legend>
<div id="messages"></div>
</fieldset>
</div>
`;

    html += `<div class="flex flex-rows flex-gap-10px margin-top-10px">`;

    if (haveAdvancedPresets) {
        html +=
`<details>
<summary>${_tr('tabs.filtering.presets.title')}</summary>
<div class="padding-10px">
<p class="line-height-150p margin-0 padding-0">${_tr('tabs.filtering.presets.instructions')}</p>
<div class="padding-top-10px padding-bottom-10px flex flex-vcenter flex-columns flex-gap-10px">
<span><input type="checkbox" id="append-at-end-advanced" checked><label for="append-at-end-advanced">${_tr('tabs.filtering.presets.append')}</label></span>
<span><input type="checkbox" id="add-parenthesis" checked><label for="add-parenthesis">${_tr('tabs.filtering.presets.add_parenthesis')}</label></span>
</div>

<table class="commonTable presetsTable"><thead>
<tr><th class="padding-5px">${_tr('tabs.filtering.presets.name')}</th><th class="padding-5px">${_tr('tabs.filtering.presets.expression')}</th></tr>
</thead><tbody>`;

        for (const key of Object.keys(this.filterPresets[1])) {
            const preset = this.filterPresets[1][key];

            html +=
`<tr data-id="${key}">
<td class="padding-5px"><a href="#" data-id="${key}">${preset.title}</a></td>
<td class="padding-5px"><code>${escapeHTML(preset.filter)}</code></td>
</tr>`;
        }

        html += `</tbody></table>`;
        html += "</div>";
        html += `</details>`;
    }

    html +=
`<details>
<summary>${_tr('tabs.filtering.column_list.title')}</summary>
<div class="padding-10px">
<p class="line-height-150p margin-0 padding-0">${_tr('tabs.filtering.column_list.hidden_warning')}</p>
<div id="columnList" class="margin-top-10px"></div>
</details>`;

    html += `</div>`;
    html += `</div>`;

    this.container.innerHTML = html;

    // Initial mode selection
    if (this.isAdvanced)
        this.$("div#traditional").classList.add("hidden");
    else this.$("div#advanced").classList.add("hidden");

    this.$("button#deleteAll").addEventListener("click", () => this.onDeleteAllFilters());
    this.$("button#toggleJSON").addEventListener("click", () => this.onToggleJSON());
    this.$("button#saveJSON").addEventListener("click", () => this.onSaveJSON());
    this.$("button#new").addEventListener("click", () => this.onNewFilter());
    this.$("textarea#json").addEventListener("input", () => this.validateJSON());
    this.$("button#save").addEventListener("click", () => this.onSave());
    this.$("button#clear").addEventListener("click", () => this.onClear());
    this.$("textarea#filter").addEventListener("input", () => this.onAdvancedInput());

    // Make the presets clickable
    if (havePresets) {
        for (let i of this.$all("div#traditional ul#presets a"))
            i.addEventListener("click", (e) => this.onLoadPreset(e));
    }

    if (haveAdvancedPresets) {
        for (let i of this.$all("div#advanced .presetsTable a"))
            i.addEventListener("click", (e) => this.onLoadPreset(e));
    }

    this.generateColumnHelp();
}

$(selector) { return this.container.querySelector(selector); }
$all(selector) { return this.container.querySelectorAll(selector); }

// Called from the parent class
enableOrDisable(isEnabled)
{
    this.disabled = !isEnabled;

    this.$("textarea#filter").disabled = this.disabled;
    this.$("button#save").disabled = this.disabled;
    this.$("button#clear").disabled = this.disabled;
}

// Switch between traditional and advanced filtering modes
toggleMode(advanced)
{
    if (this.isAdvanced == advanced)
        return;

    this.isAdvanced = advanced;

    if (this.isAdvanced) {
        this.$("div#traditional").classList.add("hidden");
        this.$("div#advanced").classList.remove("hidden");
    } else {
        this.$("div#traditional").classList.remove("hidden");
        this.$("div#advanced").classList.add("hidden");
    }

    this.parentClass.updateFiltering();
}

// Load a filter preset
onLoadPreset(e)
{
    e.preventDefault();
    const id = e.target.dataset.id;
    const preset = this.filterPresets[this.isAdvanced ? 1 : 0][id];

    if (!preset) {
        window.alert(`Invalid preset ID "${id}". Please contact Opinsys support.`);
        return;
    }

    if (this.isAdvanced) {
        let f = preset.filter;

        if (this.$("input#add-parenthesis").checked)
            f = `(${f})`;

        let box = this.$("textarea#filter");

        if (this.$("input#append-at-end-advanced").checked == false)
            box.value = f;
        else {
            // Append or replace?
            if (box.value.trim().length == 0)
                box.value = f;
            else {
                box.value += "\n";
                box.value += f;
            }
        }

        this.clearMessages();
        this.changed = true;
        this.updateUnsavedWarning();
    } else {
        // Append or replace?
        if (this.$("input#append-at-end").checked == false)
            this.setFilters(preset.filters);
        else this.setFilters(this.getFilters().concat(preset.filters));

        this.parentClass.saveFilters();
        this.parentClass.updateFiltering();
    }
}

// Compiles a filter expression and returns the compiled comparisons and RPN code in an array.
// This does not actually USE the filter for anything, it only compiles the given string.
compileFilterExpression(input)
{
    console.log("----- Compiling filter string -----");

    console.log("Input:");
    console.log(input);

    const t0 = performance.now();

    this.clearMessages();

    if (input.trim() == "") {
        // Do nothing if there's nothing to compile
        console.log("(Doing nothing to an empty string)");
        return [[], []];
    }

    let logger = new MessageLogger();

    // ----------------------------------------------------------------------------------------------
    // Tokenization

    let t = new Tokenizer();

    console.log("----- Tokenization -----");

    t.tokenize(logger, this.columnDefinitions, input);

    if (!logger.empty()) {
        for (const m of logger.messages) {
            if (m.message == "unexpected_end") {
                // Don't report the same error multiple times
                this.listMessages(logger);
                return null;
            }
        }
    }

    console.log("Raw tokens:");

    if (t.tokens.length == 0)
        console.log("  (NONE)");
    else console.log(t.tokens);

    // ----------------------------------------------------------------------------------------------
    // Syntax analysis and comparison extraction

    let p = new Parser();

    console.log("----- Syntax analysis/parsing -----");

    // TODO: Should we abort the compilation if this fails? Now we just cram ahead at full speed
    // and hope for the best.
    p.parse(logger, this.columnDefinitions, t.tokens, t.lastRow, t.lastCol);

    console.log("Raw comparisons:");

    if (p.comparisons.length == 0)
        console.log("  (NONE)");
    else console.log(p.comparisons);

    console.log("Raw parser output:");

    if (p.output.length == 0)
        console.log("  (NONE)");
    else console.log(p.output);

    // ----------------------------------------------------------------------------------------------
    // Compile the actual comparisons

    let comparisons = [];

    console.log("----- Compiling the comparisons -----");

    let cc = new ComparisonCompiler();

    for (const raw of p.comparisons) {
        const c = cc.compile(logger, this.columnDefinitions, raw.column, raw.operator, raw.value);

        if (c === null) {
            // null == the comparison was so invalid it could not even be parsed
            // log it for debugging
            console.error(raw);
            continue;
        }

        if (c === false) {
            // false == the comparison was syntactically okay, but it wasn't actually correct
            console.warn("Could not compile comparison");
            console.warn(raw);
            continue;
        }

        comparisons.push(c);
    }

    if (!logger.empty()) {
        this.listMessages(logger);

        if (logger.haveErrors()) {
            // Warnings won't stop the filter string from saved or used
            console.error("Comparison compilation failed, no filter program produced");
            return null;
        }
    }

    console.log("Compiled comparisons:");
    console.log(comparisons);

    let program = [];

    console.log("----- Shunting Yard -----");

    // Generate code
    let cg = new CodeGenerator();

    program = cg.compile(p.output);

    console.log("Final filter program:");

    if (program.length == 0)
        console.log("  (Empty)");

    for (let i = 0; i < program.length; i++) {
        const o = program[i];

        switch (o[0]) {
            case "!":
                console.log(`(${i}) NEG`);
                break;

            case "&":
                console.log(`(${i}) AND`);
                break;

            case "|":
                console.log(`(${i}) OR`);
                break;

            default: {
                const cmp = comparisons[o[0]];
                console.log(`(${i}) CMP [${cmp.column} ${cmp.operator} ${cmp.value.toString()}]`);
                break;
            }
        }
    }

    const t1 = performance.now();

    console.log(`Filter expression compiled to ${program.length} opcode(s), ${comparisons.length} comparison evaluator(s)`);
    console.log(`Filter expression compilation: ${t1 - t0} ms`);

    return [comparisons, program];
}

getFilterProgram()
{
    return {
        comparisons: [...(this.isAdvanced ? this.comparisonsAdvanced : this.comparisons)],
        program: [...(this.isAdvanced ? this.programAdvanced : this.program)]
    };
}

// --------------------------------------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------
// "TRADITIONAL" FILTERS

// Loads filters from an array, updates the table and builds the filter program
setFilters(raw)
{
    this.filters = {};

    let table = this.$("table.filtersTable");

    table.innerHTML = "";

    for (const r of (Array.isArray(raw) ? raw : [])) {
        let e = new EditableFilter();

        if (!e.load(r, this.plainColumnDefinitions))
            continue;

        const id = nextFilterID();

        this.filters[id] = e;

        let row = this.buildFilterRow(id, e);

        this.setFilterRowEvents(row);
        table.appendChild(row);
    }

    this.updateJSON();
    this.convertAndCompileFilters();
}

getFilters()
{
    let out = [];

    for (const row of this.$all("table.filtersTable tr.row")) {
        const f = this.filters[row.dataset.id];

        if (!f.isNew)
            out.push(f.save());
    }

    return out;
}

onDeleteAllFilters()
{
    if (!window.confirm(_tr("tabs.filtering.delete_all_confirm")))
        return;

    this.filters = {};
    this.$("table.filtersTable").innerHTML = "";

    this.updateJSON();
    this.convertAndCompileFilters();
    this.parentClass.saveFilters();
    this.parentClass.updateFiltering();
}

onToggleJSON()
{
    let box = this.$("textarea#json"),
        button = this.$("button#saveJSON");

    this.showJSON = !this.showJSON;

    if (this.showJSON)
        showElements(box, button);
    else hideElements(box, button);

    this.$("button#toggleJSON").innerText =
        _tr("tabs.filtering." + (this.showJSON ? "hide_json" : "show_json"));
}

onSaveJSON()
{
    if (!window.confirm(_tr("tabs.filtering.save_json_confirm")))
        return;

    try {
        this.setFilters(JSON.parse(this.$("textarea#json").value));
        this.convertAndCompileFilters();
        this.parentClass.saveFilters();
        this.parentClass.updateFiltering();
    } catch (e) {
        window.alert(e);
    }
}

updateJSON()
{
    this.$("textarea#json").value = JSON.stringify(this.getFilters());
    this.$("textarea#json").classList.remove("invalidJSON");
    this.$("button#saveJSON").disabled = false;
}

validateJSON()
{
    let box = this.$("textarea#json");

    // Is the JSON parseable?
    try {
        JSON.parse(box.value);
        box.classList.remove("invalidJSON");
        this.$("button#saveJSON").disabled = false;
    } catch (e) {
        box.classList.add("invalidJSON");
        this.$("button#saveJSON").disabled = true;
    }
}

// Pretty-prints a filter row
prettyPrintFilter(filter)
{
    const colDef = this.plainColumnDefinitions[filter.column],
          operator = OPERATORS[filter.operator];

    function formatValue(v)
    {
        if (colDef.type == ColumnType.UNIXTIME) {
            const d = parseAbsoluteOrRelativeDate(v);

            if (d === null)
                return "?";

            return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ` +
                   `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
        }

        if (colDef.flags & ColumnFlag.F_STORAGE) {
            if (v.length == 0)
                return "";

            let unit = v.slice(v.length - 1);

            if (!"BKMGT".includes(unit))
                return `${v} B`;

            switch (unit) {
                case "B": unit = "B"; break;
                case "K": unit = "KiB"; break;
                case "M": unit = "MiB"; break;
                case "G": unit = "GiB"; break;
                case "T": unit = "TiB"; break;
            }

            return `${v.slice(0, v.length - 1)} ${unit}`
        }

        return v;
    }

    const prettyTrue = _tr("tabs.filtering.ed.bool.t"),
          prettyFalse = _tr("tabs.filtering.ed.bool.f"),
          prettyEmpty = _tr("tabs.filtering.pretty.empty"),
          prettyOr = _tr("tabs.filtering.pretty.or"),
          prettyNor = _tr("tabs.filtering.pretty.nor");

    let html = "";

    html += `<span class="column">${this.columnTitles[filter.column]}</span>`;
    html += `<span class="operator">${humanOperatorName(filter.operator)}</span>`;
    html += `<span class="values">`

    if (filter.operator == "[]" || filter.operator == "![]") {
        html += `<span class="value">`;
        html += formatValue(filter.values[0]);
        html += `</span><span class="sep"> − </span><span class="value">`;
        html += formatValue(filter.values[1]);
        html += `</span>`;
    } else {
        if (colDef.type == ColumnType.BOOL)
            html += `<span class="value">${filter.values[0] === 1 ? prettyTrue : prettyFalse}</span>`;
        else {
            for (let i = 0, j = filter.values.length; i < j; i++) {
                if (filter.values[i].length == 0 && colDef.type == ColumnType.STRING)
                    html += `<span class="value empty">${prettyEmpty}</span>`;
                else {
                    html += `<span class="value">`;
                    html += formatValue(filter.values[i]);
                    html += "</span>";
                }

                if (i + 1 < j - 1)
                    html += `<span class="sep">, </span>`;
                else if (i + 1 < j) {
                    if (filter.operator == "!=")
                        html += `<span class="sep"> ${prettyNor} </span>`;
                    else html += `<span class="sep"> ${prettyOr} </span>`;
                }
            }
        }
    }

    html += "</span>";

    return html;
}

buildFilterRow(id, filter)
{
    let tr = document.createElement("tr");

    tr.id = `row-${id}`;
    tr.className = "row";
    tr.dataset.id = id;

    tr.innerHTML =
`<td class="minimize-width"><div class="buttons">
<button class="danger" title="${_tr("tabs.filtering.remove_title")}" ${filter.isNew ? "disabled" : ""}>${_tr("tabs.filtering.remove")}</button>
<button title="${_tr("tabs.filtering.duplicate_title")}" ${filter.isNew ? "disabled" : ""}>${_tr("tabs.filtering.duplicate")}</button></div></td>
<td class="minimize-width" title="${_tr("tabs.filtering.active_title")}">
<input type="checkbox" class="active" ${filter.active == 1 ? "checked" : ""} ${filter.isNew ? "disabled" : ""}>
</td><td><div class="flex flex-rows"><div class="pretty" title="${_tr("tabs.filtering.click_to_edit_title")}">
${this.prettyPrintFilter(filter)}</div><div></div></td>`;

    return tr;
}

findTableRow(element)
{
    return element.closest(`tr[id^="row-"]`);
}

getRowElem(row, what)
{
    switch (what) {
        case RowElem.BTN_DELETE:
            return row.children[0].children[0].children[0];

        case RowElem.BTN_DUPLICATE:
            return row.children[0].children[0].children[1];

        case RowElem.CB_ACTIVE:
            return row.children[1].children[0];

        case RowElem.DIV_PRETTY:
            return row.children[2].children[0].children[0];

        case RowElem.DIV_EDITOR:
            return row.children[2].children[0].children[1];

        default:
            return null;
    }
}

setFilterRowEvents(row)
{
    this.getRowElem(row, RowElem.BTN_DELETE).addEventListener("click", e => this.onDeleteFilter(e));
    this.getRowElem(row, RowElem.BTN_DUPLICATE).addEventListener("click", e => this.onDuplicateFilter(e));
    this.getRowElem(row, RowElem.CB_ACTIVE).addEventListener("click", e => this.onActiveFilter(e));

    this.getRowElem(row, RowElem.DIV_PRETTY).addEventListener("click", e => {
        let row = this.findTableRow(e.target);

        this.filters[row.dataset.id].beginEditing();
        this.openFilterEditor(row);
    });
}

onDeleteFilter(e)
{
    let tr = this.findTableRow(e.target);
    const id = tr.dataset.id;
    const wasActive = this.filters[id].active;

    delete this.filters[id];
    tr.parentNode.removeChild(tr);

    this.updateJSON();
    this.parentClass.saveFilters();

    // Deleting disabled filters don't trigger table rebuilds
    if (wasActive) {
        this.convertAndCompileFilters();
        this.parentClass.updateFiltering();
    }
}

onDuplicateFilter(e)
{
    let tr = this.findTableRow(e.target);
    const id = tr.dataset.id;

    let dupe = new EditableFilter();

    if (!dupe.load(this.filters[id].save(), this.plainColumnDefinitions)) {
        window.alert("Filter duplication failed");
        return;
    }

    dupe.active = 0;  // prevent double filtering

    const newID = nextFilterID();

    this.filters[newID] = dupe;

    let newRow = this.buildFilterRow(newID, dupe);

    tr.parentNode.insertBefore(newRow, tr.nextSibling);
    this.setFilterRowEvents(newRow);

    this.updateJSON();
    this.parentClass.saveFilters();

    // The duplicated row is disabled, don't update the table
}

onActiveFilter(e)
{
    this.filters[this.findTableRow(e.target).dataset.id].active ^= 1;

    this.updateJSON();
    this.convertAndCompileFilters();
    this.parentClass.saveFilters();
    this.parentClass.updateFiltering();
}

openFilterEditor(row)
{
    const id = row.dataset.id;
    let filter = this.filters[id];

    hideElements(this.getRowElem(row, RowElem.DIV_PRETTY));

    // Construct an editor interface
    let wrapper = this.getRowElem(row, RowElem.DIV_EDITOR);

    wrapper.innerHTML =
`<div class="flex flex-rows">
<div class="openFilter flex flex-columns flex-gap-5px">
<select id="column" title="${_tr("tabs.filtering.edit_column_title")}"></select>
<select id="operator" title="${_tr("tabs.filtering.edit_operator_title")}"></select>
<button id="save" class="margin-left-20px"><i class="icon-ok"></i>${_tr("tabs.filtering.save")}</button>
<button id="cancel"><i class="icon-cancel"></i>${_tr("tabs.filtering.cancel")}</button>
</div><div id="editor" class="editor"></div></div>`;

    wrapper.classList.add("editorWrapper");

    // Sort the columns in alphabetical order
    let select = wrapper.querySelector("select#column"),
        columns = [];

    for (const column of Object.keys(this.plainColumnDefinitions))
        columns.push([column, this.columnTitles[column]]);

    columns.sort((a, b) => { return a[1].localeCompare(b[1]) });

    for (const [column, title] of columns) {
        let o = document.createElement("option");

        o.innerText = title;
        o.dataset.column = column;
        o.selected = (filter.editColumn == column);

        select.appendChild(o);
    }

    const colDef = this.plainColumnDefinitions[filter.editColumn];

    console.log(`Initial column: |${filter.editColumn}|`);
    console.log(`Initial operator: |${filter.editOperator}|`);

    this.fillOperatorSelector(wrapper.querySelector("select#operator"),
                              colDef.type, filter.editOperator);

    // Initial type-specific editor child UI
    this.buildValueEditor(filter, wrapper.querySelector("div#editor"), colDef);

    wrapper.querySelector("select#column").addEventListener("change", (e) => this.onColumnChanged(e));
    wrapper.querySelector("select#operator").addEventListener("change", (e) => this.onOperatorChanged(e));

    wrapper.querySelector("button#save").addEventListener("click", (e) => {
        let row = this.findTableRow(e.target);
        const id = row.dataset.id;

        // Don't save the filter if the value (or values) is incorrect
        const valid = this.filters[id].editor.validate();

        if (!valid[0]) {
            window.alert(valid[1]);
            return;
        }

        this.filters[id].finishEditing();
        this.filters[id].isNew = false;     // enable normal functionality
        this.closeFilterEditor(row);

        this.getRowElem(row, RowElem.BTN_DELETE).disabled = false;
        this.getRowElem(row, RowElem.BTN_DUPLICATE).disabled = false;
        this.getRowElem(row, RowElem.CB_ACTIVE).disabled = false;
        this.getRowElem(row, RowElem.DIV_PRETTY).innerHTML = this.prettyPrintFilter(this.filters[id]);
        this.updateJSON();
        this.parentClass.saveFilters();
    });

    wrapper.querySelector("button#cancel").addEventListener("click", (e) => {
        let row = this.findTableRow(e.target);
        let filter = this.filters[row.dataset.id];
        const wasNew = filter.isNew;

        filter.cancelEditing();

        if (wasNew)
            row.parentNode.removeChild(row);
        else this.closeFilterEditor(row);
    });
}

closeFilterEditor(row)
{
    this.filters[row.dataset.id].editor = null;

    let editor = this.getRowElem(row, RowElem.DIV_EDITOR);

    editor.innerHTML = "";
    editor.classList.remove("editorWrapper");

    showElements(this.getRowElem(row, RowElem.DIV_PRETTY));
}

buildValueEditor(filter, container, colDef)
{
    const editors = {
        [ColumnType.BOOL]: FilterEditorBoolean,
        [ColumnType.NUMERIC]: FilterEditorNumeric,
        [ColumnType.STRING]: FilterEditorString,
        [ColumnType.UNIXTIME]: FilterEditorUnixtime,
    };

    if (colDef.type in editors) {
        filter.editor = new editors[colDef.type](container, filter, colDef);
        filter.editor.buildUI();
    } else throw new Error(`Unknown column type ${colDef.type}`);
}

onColumnChanged(e)
{
    let row = this.findTableRow(e.target);
    const id = row.dataset.id;
    let filter = this.filters[id];
    let wrapper = this.getRowElem(row, RowElem.DIV_EDITOR);

    filter.editColumn = e.target[e.target.selectedIndex].dataset.column;

    // Is the previous operator still valid for this type? If not, reset it to "=",
    // it's the default (and the safest) operator.
    const newDef = this.plainColumnDefinitions[filter.editColumn];

    if (!OPERATORS[filter.editOperator].allowed.has(newDef.type))
        filter.editOperator = "=";

    // Refill the operator selector
    // TODO: Don't do this if the new column has the same operators available
    // as the previous column did.
    this.fillOperatorSelector(wrapper.querySelector("select#operator"),
                              newDef.type, filter.editOperator);

    // Recreate the editor UI
    let editor = wrapper.querySelector("div#editor");

    editor.innerHTML = "";
    filter.editor = null;
    this.buildValueEditor(filter, editor, newDef);
}

onOperatorChanged(e)
{
    const row = this.findTableRow(e.target);
    const operator = e.target[e.target.selectedIndex].dataset.operator;
    let filter = this.filters[row.dataset.id];

    filter.editOperator = operator;
    filter.editor.operatorHasChanged(operator);
}

fillOperatorSelector(target, type, initial)
{
    target.innerHTML = "";

    for (const opId of ["=", "!=", "<", "<=", ">", ">=", "[]", "![]"]) {
        if (OPERATORS[opId].allowed.has(type)) {
            let o = document.createElement("option");

            o.innerText = humanOperatorName(opId);
            o.dataset.operator = opId;
            o.selected = (opId == initial);

            target.appendChild(o);
        }
    }
}

onNewFilter()
{
    let f = new EditableFilter();

    let initial = null;

    if (this.defaultFilter === undefined || this.defaultFilter === null || this.defaultFilter.length < 4) {
        // Use the first available column. Probably not the best, but at least the filter will be valid.
        initial = [0, Object.keys(this.plainColumnDefinitions)[0], "=", ""];
    } else initial = [...this.defaultFilter];

    if (!f.load(initial, this.plainColumnDefinitions)) {
        window.alert("Filter creation failed. See the console for details.");
        return;
    }

    f.isNew = true;     // disables certain UI elements and makes the Cancel button remove the filter

    const newID = nextFilterID();

    this.filters[newID] = f;
    let newRow = this.buildFilterRow(newID, f);

    this.setFilterRowEvents(newRow);
    this.$("table.filtersTable").appendChild(newRow);

    // Open the newly-created filter for editing
    this.filters[newID].beginEditing();
    this.openFilterEditor(newRow);
}

// Converts the "traditional" filters into an advanced filter string and compiles it
convertAndCompileFilters()
{
    let parts = [];

    for (const f of this.getFilters()) {
        if (!f[0])          // inactive filter
            continue;

        if (f.length < 4)   // incomplete filter
            continue;

        let col = f[1],
            op = f[2],
            val = [];

        const colDef = this.plainColumnDefinitions[col];

        // Convert the value
        for (let v of f.slice(3)) {
            switch (colDef.type) {
                case ColumnType.BOOL:
                    if (v.length == 0)
                        continue;

                    val.push(v === 1 ? '1' : '0');
                    break;

                case ColumnType.NUMERIC:
                    // All possible values should work fine, even storage units, without quotes
                    if (v.length == 0)
                        continue;

                    val.push(v);
                    break;

                case ColumnType.UNIXTIME:
                    if (v.length == 0)
                        continue;

                    // Absolute times must be quoted, relative times should work as-is
                    val.push(ABSOLUTE_TIME.exec(v) !== null ? `"${v}"` : v);
                    break;

                case ColumnType.STRING:
                default:
                    // Convert strings to regexps
                    if (v == "")
                        val.push(`/^$/`);
                    else val.push(`/${v}/`);
                    break;
            }
        }

        // Output a comparison with the converted value
        if (op == "[]") {
            // include (closed)
            if (val.length < 2)
                continue;

            parts.push(`(${col} >= ${val[0]} && ${col} <= ${val[1]})`);
        } else if (op == "![]") {
            // exclude (open)
            if (val.length < 2)
                continue;

            parts.push(`(${col} < ${val[0]} || ${col} > ${val[1]})`);
        } else {
            if (val.length < 1)
                continue;

            if (val.length == 1) {
                // a single value
                parts.push(`${col} ${op} ${val[0]}`);
            } else {
                // multiple values, either OR'd or AND'd together depending on the operator
                let sub = [];

                for (const v of val)
                    sub.push(`${col} ${op} ${v}`);

                if (op == "=")
                    sub = sub.join(" || ");
                else sub = sub.join(" && ");

                parts.push("(" + sub + ")");
            }
        }
    }

    // Join the comparisons together and compile the resulting string
    const script = parts.join(" && ");

    const result = this.compileFilterExpression(script);

    if (result === false || result === null) {
        window.alert("Could not compile the filter. See the console for details, then contact Opinsys support.");
        return;
    }

    this.comparisons = result[0];
    this.program = result[1];
}

// --------------------------------------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------
// ADVANCED FILTERS

setFilterString(filter)
{
    let box = this.$("textarea#filter");

    if (typeof(filter) != "string")
        box.value = "";
    else box.value = filter;

    this.comparisonsAdvanced = [];
    this.programAdvanced = [];

    const result = this.compileFilterExpression(box.value);

    if (result === false || result === null)
        return;

    this.comparisonsAdvanced = result[0];
    this.programAdvanced = result[1];
}

getFilterString()
{
    return this.$("textarea#filter").value;
}

// Save the advanced filter string
onSave()
{
    const result = this.compileFilterExpression(this.$("textarea#filter").value);

    if (result === false || result === null)
        return;

    this.comparisonsAdvanced = result[0];
    this.programAdvanced = result[1];
    this.changed = false;
    this.updateUnsavedWarning();
    this.parentClass.saveFilters();
    this.parentClass.updateFiltering();
}

// Clear the advanced filter
onClear()
{
    if (window.confirm(_tr('are_you_sure'))) {
        this.$("textarea#filter").value = "";
        this.clearMessages();
        this.changed = true;
        this.updateUnsavedWarning();
    }
}

// Advanced filter string has changed
onAdvancedInput()
{
    this.changed = true;
    this.updateUnsavedWarning();
}

// Copy the column name to the advanced filter string box
onClickColumnName(e)
{
    e.preventDefault();
    this.$("textarea#filter").value += e.target.dataset.column + " ";
}

updateUnsavedWarning()
{
    let legend = this.$("fieldset legend");

    if (!legend)
        return;

    let html = _tr('tabs.filtering.expression_title');

    if (this.changed)
        html += ` <span class="unsaved">[${_tr('tabs.filtering.unsaved')}]</span>`;

    legend.innerHTML = html;
}

generateColumnHelp()
{
    const COLUMN_TYPES = {
        [ColumnType.BOOL]: _tr('tabs.filtering.column_list.type_bool'),
        [ColumnType.NUMERIC]: _tr('tabs.filtering.column_list.type_numeric'),
        [ColumnType.UNIXTIME]: _tr('tabs.filtering.column_list.type_unixtime'),
        [ColumnType.STRING]: _tr('tabs.filtering.column_list.type_string'),
    };

    let html =
`<table class="commonTable columnHelp"><thead><tr>
<th>${_tr('tabs.filtering.column_list.pretty_name')}</th>
<th>${_tr('tabs.filtering.column_list.database_name')}</th>
<th>${_tr('tabs.filtering.column_list.type')}</th>
<th>${_tr('tabs.filtering.column_list.operators')}</th>
<th>${_tr('tabs.filtering.column_list.nullable')}</th>
</tr></thead><tbody>`;

    let columnNames = [];

    for (const key of Object.keys(this.plainColumnDefinitions))
        columnNames.push([key, this.columnTitles[key]]);

    columnNames.sort((a, b) => { return a[1].localeCompare(b[1]) });

    for (const col of columnNames) {
        html += `<tr><td>${col[1]}</td><td>`;

        const nullable = this.plainColumnDefinitions[col[0]].flags & ColumnFlag.F_NULLABLE;

        let fields = Array.from(this.columnDefinitions.getAliases(col[0]));

        fields.sort();
        fields.unshift(col[0]);

        html += fields.map((f) => `<a href="#" data-column="${f}">${f}</a>`).join("<br>");
        html += "</td>";

        const type = this.plainColumnDefinitions[col[0]].type;

        html += `<td>${COLUMN_TYPES[type]}</td>`;
        html += "<td>";

        const ops = Array.from(ALLOWED_OPERATORS[type]);

        for (let i = 0, j = ops.length; i < j; i++) {
            if (ops[i] == "!!" && !nullable)
                continue;

            html += `<code>${escapeHTML(ops[i])}</code>`;

            if (i + 1 < j)
                html += " ";
        }

        html += "</td>";

        if (nullable)
            html += `<td>${_tr('tabs.filtering.column_list.is_nullable')}</td>`;
        else html += "<td></td>";

        html += "</tr>";
    }

    html += "</tbody></table>";

    let cont = this.$("div#columnList");

    // Remove old event handlers first
    if (cont.firstChild)
        for (let a of cont.querySelectorAll("a"))
            a.removeEventListener("click", this.onClickColumnName);

    cont.innerHTML = html;

    // Then set up new event handlers
    for (let a of cont.querySelectorAll("a"))
        a.addEventListener("click", this.onClickColumnName);
}

clearMessages()
{
    this.$("#messages").innerHTML = `<p class="margin-0 padding-0">${_tr('tabs.filtering.no_messages')}</p>`;
}

// Update the advanced filter compilation messages box
listMessages(logger)
{
    if (logger.empty())
        return;

    let html =
`<table class="commonTable messages width-100p"><thead><tr>
<th>${_tr('tabs.filtering.row')}</th>
<th>${_tr('tabs.filtering.column')}</th>
<th>${_tr('tabs.filtering.message')}</th>
</tr></thead><tbody>`;

    // The messages aren't necessarily in any particular order, sort them
    const sorted = [...logger.messages].sort(function(a, b) { return a.row - b.row || a.col - b.col });

    for (const e of sorted) {
        let cls = [];

        if (e.type == 'error')
            cls.push("error");

        html +=
`<tr class="${cls.join(' ')}" data-pos="${e.pos}" data-len="${e.len}">
<td class="minimize-width align-center">${e.row}</td>
<td class="minimize-width align-center">${e.col}</td>`;

        html += "<td>";
        html += _tr('tabs.filtering.' + e.type) + ": ";
        html += _tr('tabs.filtering.messages.' + e.message);

        if (e.extra !== null)
            html += `<br>(${e.extra})`;

        html += "</td></tr>";
    }

    html += "</tbody></table>";

    this.$("#messages").innerHTML = html;

    // Add event listeners. I'm 99% certain this leaks memory, but I'm not sure how to fix it.
    for (let row of this.$all(`table.messages tbody tr`))
        row.addEventListener("click", (e) => this.highlightMessage(e));
}

highlightMessage(e)
{
    // Find the target table row. Using "pointer-events" to pass through clicks works, but
    // it makes browsers not display the "text" cursor when hovering the table and that is
    // just wrong.
    let elem = e.target;

    while (elem && elem.nodeName != "TR")
        elem = elem.parentNode;

    if (!elem) {
        console.error("highlightMessage(): can't find the clicked table row");
        return;
    }

    // Highlight the target
    const pos = parseInt(elem.dataset.pos, 10),
          len = parseInt(elem.dataset.len, 10);

    let t = this.$("textarea#filter");

    if (!t) {
        console.error("highlightMessage(): can't find the textarea element");
        return;
    }

    t.focus();
    t.selectionStart = pos;
    t.selectionEnd = pos + len;
}

};  // class FilterEditor
