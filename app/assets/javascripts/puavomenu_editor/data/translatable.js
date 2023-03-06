"use strict";

//import { isNonemptyString } from "../utils.js";

// This can store single and multi-string translations, but only one of them will be saved

export class TranslatableString {
    constructor()
    {
        this.isSingle = true;

        this.single = "";

        this.multi = {
            fi: "",
            en: "",
            sv: "",
            de: "",
        };
    }

    load(source)
    {
        if (typeof(source) == "string") {
            this.isSingle = true;
            this.single = source.trim();
        } else if (typeof(source) == "object") {
            this.isSingle = false;

            for (const lang of ["fi", "en", "sv", "de"])
                this.multi[lang] = (lang in source && typeof(source[lang]) == "string") ? source[lang].trim() : "";
        } else {
            // Allow "resetting"
            this.isSingle = true;
            this.single = "";
            this.multi = {
                fi: "",
                en: "",
                sv: "",
                de: "",
            };
        }
    }

    save()
    {
        if (this.isSingle)
            return this.single;

        // Only export non-empty strings, so that the replacement/override algorithm works
        let out = {};

        for (const lang of ["fi", "en", "sv", "de"])
            if (this.multi[lang].length > 0)
                out[lang] = this.multi[lang];

        return out;
    }

    // Returns true if the selected translation type is empty
    isNonEmpty()
    {
        if (this.isSingle)
            return this.single.length > 0;

        for (const lang of ["fi", "en", "sv", "de"]) {
            if (this.multi[lang].length > 0) {
                // Even one translated string is enough (it won't look nice, but it's enough)
                return true;
            }
        }

        return false;
    }

    // Returns true if this string has both single and multiple values defined. That
    // will cause problems, because only one of them can be saved.
    hasMultiple()
    {
        let score = 0;

        if (this.single.length > 0)
            score++;

        for (const lang of ["fi", "en", "sv", "de"]) {
            if (this.multi[lang].length > 0) {
                // Again, one string is enough
                score++;
                break;
            }
        }

        return score > 1;
    }
}
