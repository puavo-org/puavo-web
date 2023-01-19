// A custom logger that also keeps track of row and column numbers and some other metadata
export class MessageLogger {
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
}
