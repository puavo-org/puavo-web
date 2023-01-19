/*
Each column can have zero or more (unique) alias names that all point to the actual name.
It's just a simple text replacement system. Some column names used in the raw JSON data
are very short and cryptic, so it's nice to have easy-to-remember aliases for them.
*/

export class ColumnDefinitions {
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
}
