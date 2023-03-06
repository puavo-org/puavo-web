"use strict";

import { Category } from "./category.js";
import { Menu } from "./menu.js";
import { Program, ProgramType } from "./program.js";

// Alphabetically sorts the array. Used to keep programs, menus, etc. in alphabetical order.
export function sortIDs(arr)
{
    return arr.sort((a, b) => a.localeCompare(b, undefined, { sensitivity: 'base' }));
}

// I spent some time debating myself whether to use the plain object returned by JSON.parse()
// and edit it directly, or make Category/Menu/Program classes that wrap them, and I went with
// the latter. Mostly because it's easier that way. The menudata format is very flexible and
// malleable.

// "Hardcoded" category data for restricted mode editing
const RESTRICTED_ID = "category-schoolmenu",
      RESTRICTED_POSITION = -999999;

// A wrapper for all menudata
export class Menudata {
    constructor(source, restrictedMode)
    {
        this.programs = {};
        this.menus = {};
        this.categories = {};
        this.categoryIndex = [];
        this.restrictedMode = restrictedMode;

        if (source) {
            if (typeof(source) == "string")
                this.load(JSON.parse(source));
            else this.load(source);
        }
    }

    load(object)
    {
        if ("programs" in object)
            this._loadPrograms(object.programs);

        if ("menus" in object)
            this._loadMenus(object.menus);

        if ("categories" in object)
            this._loadCategories(object.categories);

        if (this.restrictedMode) {
            // In restricted mode, only one category is allowed. Because we do not know which
            // one it is, we'll just take the first available and hope for the best. If there
            // are no categories, create a new hard-coded one. It's called "school menu", but
            // in reality it is just a normal category.
            if (Object.keys(this.categories).length == 0) {
                console.warn("Running in restricted mode, and there are no categories. Creating the default category.");

                let schoolMenu = new Category();

                schoolMenu.position = RESTRICTED_POSITION;

                schoolMenu.name.load({
                    "fi": "Koulu",
                    "en": "School",
                    "sv": "Skola",
                    "de": "Schule",
                });

                schoolMenu.validate();

                this.categories[RESTRICTED_ID] = schoolMenu;
                this.categoryIndex.push([schoolMenu.position, RESTRICTED_ID]);
            } else {
                // Enforce the hardcoded position
                this.categories[Object.keys(this.categories)[0]].position = RESTRICTED_POSITION;
            }
        }

        // Find unknown programs and menus. Treat them as external (ie. they're defined somewhere
        // else, not in this menudata).
        let externalMenus = new Set(),
            externalPrograms = new Set();

        for (const cid of Object.keys(this.categories)) {
            for (const pid of this.categories[cid].programs) {
                if (!(pid in this.programs))
                    externalPrograms.add(pid);
            }

            for (const mid of this.categories[cid].menus) {
                if (!(mid in this.menus))
                    externalMenus.add(mid);
            }
        }

        for (const mid of Object.keys(this.menus)) {
            for (const pid of this.menus[mid].programs) {
                if (!(pid in this.programs))
                    externalPrograms.add(pid);
            }
        }

        // Construct fake entries for unknown entries
        for (const mid of externalMenus) {
            let m = new Menu;

            m.isExternal = true;
            this.menus[mid] = m;
        }

        for (const pid of externalPrograms) {
            let p = new Program;

            p.isExternal = true;
            this.programs[pid] = p;
        }
    }

    save()
    {
        let out = {};

        let programs = {};

        for (const pid of sortIDs(Object.keys(this.programs))) {
            if (this.programs[pid].isExternal)
                continue;

            programs[pid] = this.programs[pid].save();
        }

        if (Object.keys(programs).length > 0)
            out.programs = programs;

        let menus = {};

        for (const mid of sortIDs(Object.keys(this.menus))) {
            if (this.menus[mid].isExternal)
                continue;

            menus[mid] = this.menus[mid].save();
        }

        if (Object.keys(menus).length > 0)
            out.menus = menus;

        let categories = {};

        for (const cid of sortIDs(Object.keys(this.categories)))
            categories[cid] = this.categories[cid].save();

        if (Object.keys(categories).length > 0) {
            out.categories = categories;

            if (this.restrictedMode) {
                // Enforce the hardcoded position
                this.categories[Object.keys(out.categories)[0]].position = RESTRICTED_POSITION;
            }
        }

        // NOTE: 'categoryIndex' is regenerated when the data is loaded, no need to save it

        return out;
    }

    sortCategories()
    {
        // We can only use position for sorting, not the title (which is language-dependant)
        this.categoryIndex.sort((a, b) => a[0] - b[0]);
    }

    haveErrorsOrWarnings()
    {
        for (const category of Object.values(this.categories)) {
            if (category.warnings.size > 0 || category.errors.size > 0) {
                console.log(category);
                return true;
            }
        }

        for (const menu of Object.values(this.menus)) {
            if (menu.warnings.size > 0 || menu.errors.size > 0) {
                console.log(menu);
                return true;
            }
        }

        for (const program of Object.values(this.programs)) {
            if (program.warnings.size > 0 || program.errors.size > 0) {
                console.log(program);
                return true;
            }
        }

        return false;
    }

    _loadCategories(object)
    {
        for (const id of Object.keys(object)) {
            let cat = new Category();

            if (!cat.load(object[id]))
                continue;

            this.categories[id] = cat;
            this.categoryIndex.push([cat.position, id]);

            if (this.restrictedMode) {
                // Only load the first category
                break;
            }
        }

        this.sortCategories();
    }

    _loadMenus(object)
    {
        for (const id of Object.keys(object)) {
            let m = new Menu();

            if (!m.load(object[id]))
                continue;

            this.menus[id] = m;
        }
    }

    _loadPrograms(object)
    {
        for (const id of Object.keys(object)) {
            let p = new Program();

            if (!p.load(object[id]))
                continue;

            this.programs[id] = p;
        }
    }
}
