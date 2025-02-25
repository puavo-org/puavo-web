"use strict";

// Interactive Puavomenu menudata editor
// v0.5

// Copyright Opinsys Oy 2023

/*
----
TODO
----

Core functionality (all of these are required for version 1.0):
    - Because menudata can be defined on three levels (organisation, school, device) just like
      puavo-conf values, the editor should display inherited menudata. Overridden entries should
      be indicated clearly.
    - It should be possible to create/override existing programs and menus, without having to
      create a new category first.
    - Dragging menus and programs around is a bit wonky.
        - Find the *closest* drop slot, not the one that's immediately under the mouse.
          (The closest slot could be anywhere.)
        - There should be a separate drop marker for the last possible slot. You can move an item
          to the end of a list, but it looks wrong (ie. there should be a marker between the last
          item and the "new entry" button).
    - The menudata format allows "\n" to be used for newlines in titles and descriptions, but the
      input boxes won't display them correctly.
    - Condition editor (include conditions in menudata, not in separate files). Some conditions
      (like running external scripts) require changes to the desktop image, but basic stuff, like
      environment variables and querying puavo-conf values, will work just fine.
    - There's a lot of redudancy in the navigation and view update code.
      They could be simplified a lot.
    - Missing category functionality:
        - "new category" button and popup
        - Category deletion buttons
        - Rebuild the category bar if category positions are changed? (the sorting is locale-dependant,
          so this might not be possible)

Nice to have (version 1.1 or something):
    - Add support for .desktop files. Either drag-and-drop, or convert them into JSON that is then
      copied to the server and the menu can load them from there.
    - Support pre-built icon atlas images for visually selecting icons and showing their previews?
    - Retain expandable editor sections open/close states in localstore
    - The expandable sections of the editor should display a summary of the value
      in the section title.
    - "Copy menu from another school" button, so you don't have recreate
      the same menu for multiple schools by hand
    - Category reordering by drag-and-drop?
*/

import { create, getTemplate, toggleClass } from "../common/dom.js";
import { _tr } from "../common/utils.js";
import { sortIDs, Menudata } from "./data/menudata.js";
import { ItemType, ItemEditor } from "./item_editor.js";
import { existsInArray } from "./utils.js";

import { Category } from "./data/category.js";
import { Menu } from "./data/menu.js";
import { Program } from "./data/program.js";

// Where are the settings are stored?
const LOCALSTORE_KEY = "PME_settings";

// Validates .desktop file names and category/menu IDs
export const ENTRY_ID_REGEXP = /[^a-zA-Z0-9._-]/u;

export class PuavomenuEditor {
    constructor(container, initial, restrictedMode)
    {
        this.container = container;
        this.restrictedMode = restrictedMode;
        this.data = new Menudata(initial, this.restrictedMode);

        this.current = {
            // The initial category is the first available (in sort order)
            categoryID: this.data.categoryIndex[0][1],
            menuID: null,

            // Menus and programs of the current category (or submenu). Updated in updateView().
            // Can be NULL if nothing is selected.
            menus: null,
            programs: null,
        };

        this.selection = {
            type: ItemType.NONE,
            id: null,
            handle: null,
        };

        this.newEntryFilterMenus = "";
        this.newEntryFilterPrograms = "";
        this.searchTerm = "";

        this.confirmMenuRemoval = true;
        this.confirmProgramRemoval = true;

        // Direct handles to various UI elements
        this.ui = {
            tabs: this.container.querySelector("div#pme div#preview div#tabs"),
            preview: this.container.querySelector("div#pme div#preview div#contents"),
            editor: this.container.querySelector("div#pme div#editor"),
        };

        // The sidebar item editor
        this.itemEditor = new ItemEditor(this.ui.editor, this.restrictedMode, this);

        // List reordering (drag-and-drop) stuff
        this.onMouseButtonUp = this.onMouseButtonUp.bind(this);
        this.onMouseMove = this.onMouseMove.bind(this);

        this.drag = {
            active: false,
            itemID: null,
            itemType: null,
            startingMousePos: { x: 0, y: 0 },
            dropSlots: [],
            sourceSlot: -1,
            destinationSlot: -1,
            offset: { x: 0, y: 0 },
            size: { w: 0, h: 0 },
            source: null,
            object: null,
            marker: null,
        };

        this.loadSettings();

        // Setup events
        this.container.querySelector("input#confirm_menu_removal").checked = this.confirmMenuRemoval;
        this.container.querySelector("input#confirm_program_removal").checked = this.confirmProgramRemoval;

        this.container.querySelector("input#confirm_menu_removal").addEventListener("click", e => {
            this.confirmMenuRemoval = e.target.checked;
            this.saveSettings();
        });

        this.container.querySelector("input#confirm_program_removal").addEventListener("click", e => {
            this.confirmProgramRemoval = e.target.checked;
            this.saveSettings();
        });

        this.container.querySelector("button#open_json_editor").addEventListener("click", e => this.onOpenJSONEditor(e));
        this.container.querySelector("button#find_unused").addEventListener("click", e => this.onFindUnusedEntries(e));
        this.container.querySelector("button#search").addEventListener("click", e => this.onShowSearch(e));

        this.container.querySelector("a#toplevel").addEventListener("click", e => this.onExitMenu(e));

        // The initial update
        this.createTabs();
        this.updateView();
    }

    loadSettings()
    {
        let stored = localStorage.getItem(LOCALSTORE_KEY);

        if (stored === null)
            stored = "{}";

        try {
            stored = JSON.parse(stored);
        } catch (e) {
            console.error("loadSettings(): could not load stored settings:");
            console.error(e);
            console.error("loadSettings(): using defaults");

            return;
        }

        if ("confirm_menu_removal" in stored && typeof(stored.confirm_menu_removal) == "boolean")
            this.confirmMenuRemoval = stored.confirm_menu_removal;

        if ("confirm_program_removal" in stored && typeof(stored.confirm_program_removal) == "boolean")
            this.confirmProgramRemoval = stored.confirm_program_removal;
    }

    saveSettings()
    {
        const settings = {
            confirm_menu_removal: this.confirmMenuRemoval,
            confirm_program_removal: this.confirmProgramRemoval,
        };

        try {
            localStorage.setItem(LOCALSTORE_KEY, JSON.stringify(settings));
        } catch (e) {
            console.error("saveSettings(): cannot save the settings:");
            console.error(e);
        }
    }

    trySave(url, button)
    {
        // Are there any errors or warnings?
        if (this.data.haveErrorsOrWarnings()) {
            if (!window.confirm(_tr("errors.save_confirm")))
                return;
        }

        const data = this.data.save();

        console.log(`Sending data to ${url}`);

        if (button)
            button.disabled = true;

        fetch(url, {
            method: "POST",
            mode: "cors",
            headers: {
                // Use text/plain to avoid RoR from logging the parameters in plain text.
                // They can contain passwords and other sensitive stuff.
                "Content-Type": "text/plain; charset=utf-8",
                "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content,
            },
            body: JSON.stringify(data),
        }).then(response => {
            if (!response.ok)
                throw response;

            // By parsing the JSON in the "next" stage, we can handle errors better
            return response.text();
        }).then(data => {
            data = JSON.parse(data);

            if (data.success) {
                // Redirect
                document.location = data.redirect;
            } else {
                window.alert(_tr("errors.save_failed_message", { message: data.message }));

                if (button)
                    button.disabled = false;

                return;
            }
        }).catch(e => {
            console.error(e);

            window.alert(_tr("errors.save_failed"));

            if (button)
                button.disabled = false;
        });
    }

    // ----------------------------------------------------------------------------------------------
    // ----------------------------------------------------------------------------------------------
    // INTERFACE UPDATES

    createTabs()
    {
        this.ui.tabs.innerText = "";

        for (const [_, cid] of this.data.categoryIndex) {
            const category = this.data.categories[cid];

            let tab = create("div", { cls: "tab" });

            tab.innerHTML = `<span class="id">${cid}</span>`;

            tab.dataset.cid = cid;

            if (cid == this.current.categoryID)
                tab.classList.add("current");

            if (category.warnings.size > 0 || category.errors.size > 0)
                tab.classList.add("notify");

            tab.addEventListener("click", e => {
                this.onChangeSelection(ItemType.CATEGORY, e.target.dataset.cid, e.target);
            });

            this.ui.tabs.appendChild(tab);
        }
    }

    // Rebuilds the current view, which can be either top-level category view or a
    // submenu view
    updateView()
    {
        const addButton = (id) => {
            let button = getTemplate("existingEntry").querySelector("div.pmeEntry");

            button.dataset.id = id;
            button.querySelectorAll("span")[0].innerText = id;

            return button;
        };

        const newButton = (type) => {
            let button = getTemplate("newEntry").querySelector("div.pmeEntry");

            button.dataset.type = type;
            button.addEventListener("click", e => this.onNewEntryClicked(e));

            return button;
        };

        let menuSection = this.ui.preview.querySelector("section#menus"),
            menusList = this.ui.preview.querySelector("section#menus div.entries"),
            programsList = this.ui.preview.querySelector("section#programs div.entries");

        this.deselectItem();

        if (this.current.menuID === null) {
            // Top-level category view
            menuSection.classList.remove("hidden");

            this.current.menus = this.data.categories[this.current.categoryID].menus;
            this.current.programs = this.data.categories[this.current.categoryID].programs;

            menusList.innerText = "";

            for (const mid of this.current.menus) {
                const menu = this.data.menus[mid];

                let entry = addButton(mid);
                let spans = entry.querySelectorAll("span");

                // Select or move
                spans[0].addEventListener("mousedown", e => {
                    this.onMouseDown(e, ItemType.MENU);
                });

                // Open menu
                if (!menu.isExternal) {
                    spans[0].addEventListener("dblclick", e => {
                        this.onEnterMenu(e.target.parentNode.dataset.id);
                    });
                }

                // Remove
                spans[1].addEventListener("click", e => {
                    this.onRemoveItem(ItemType.MENU, e.target.parentNode.dataset.id, e.target.parentNode);
                });

                if (menu.warnings.size > 0 || menu.errors.size > 0)
                    entry.classList.add("notify");

                if (menu.isExternal)
                    entry.classList.add("external");

                menusList.appendChild(entry);
            }

            menusList.appendChild(newButton(ItemType.MENU));
        } else {
            // Menu view
            menuSection.classList.add("hidden");

            this.current.menus = null;
            this.current.programs = this.data.menus[this.current.menuID].programs;
        }

        programsList.innerText = "";

        for (const pid of this.current.programs) {
            const program = this.data.programs[pid];

            let entry = addButton(pid);
            let spans = entry.querySelectorAll("span");

            // Select or morve
            spans[0].addEventListener("mousedown", e => {
                this.onMouseDown(e, ItemType.PROGRAM);
            });

            // Remove
            spans[1].addEventListener("click", e => {
                this.onRemoveItem(ItemType.PROGRAM, e.target.parentNode.dataset.id, e.target.parentNode);
            });

            if (program.warnings.size > 0 || program.errors.size > 0)
                entry.classList.add("notify");

            if (program.isExternal)
                entry.classList.add("external");

            programsList.appendChild(entry);
        }

        programsList.appendChild(newButton(ItemType.PROGRAM));
    }

    // ----------------------------------------------------------------------------------------------
    // ----------------------------------------------------------------------------------------------
    // NAVIGATION

    // Deselect the selected item
    deselectItem()
    {
        if (this.selection.handle !== null)
            this.selection.handle.classList.remove("selected");

        this.selection.handle = null;
    }

    // Changes the current selection (category, menu or program) and
    // changes the selection focus accordingly
    onChangeSelection(selectedType, selectedID, item)
    {
        // Do category changes first so that the relevant elements exist on the page
        if (selectedType == ItemType.CATEGORY && this.current.categoryID != selectedID) {
            this.current.categoryID = selectedID;
            this.current.menuID = null;

            console.log(`Category changed to "${this.current.categoryID}"`);

            this.deselectItem();
            this.updateMenuTitle(null);

            for (let b of this.ui.tabs.childNodes) {
                if (b.dataset.cid == selectedID)
                    b.classList.add("current");
                else b.classList.remove("current");
            }

            this.updateView();
        }

        if (this.selection.type != selectedType) {
            console.log(`Current selection type changed to ${selectedType}`);
            this.selection.type = selectedType;
        }

        if (this.selection.id != selectedID) {
            console.log(`Current selection ID changed to "${selectedID}"`);
            this.selection.id = selectedID;
            this.onSelectedItemChanged();
        }

        // Update the selection focus
        this.deselectItem();
        this.selection.handle = item;
        this.selection.handle.classList.add("selected");
    }

    // Change the selected item
    onSelectedItemChanged()
    {
        let item = null;

        switch (this.selection.type) {
            case ItemType.CATEGORY:
                item = this.data.categories[this.selection.id];
                break;

            case ItemType.MENU:
                item = this.data.menus[this.selection.id];
                break;

            case ItemType.PROGRAM:
                item = this.data.programs[this.selection.id];
                break;

            default:
                console.error(`onSelectedItemChanged(): unknown item type ${this.selection.type}`);
                return;
        }

        if (this.selection.type != ItemType.PROGRAM && this.current.menuID !== null) {
            // Go back to the main level first
            this.updateMenuTitle(null);
            this.current.menuID = null;
            this.updateView();
        }

        this.itemEditor.setItem(this.selection.id, this.selection.type, item);
    }

    // Opens a menu. Can only happen if we're on a top-level view.
    onEnterMenu(mid)
    {
        console.log(`Entering menu "${mid}"`);

        this.updateMenuTitle(mid);

        this.current.menuID = mid;
        this.itemEditor.clearItem();
        this.updateView();
    }

    updateMenuTitle(title)
    {
        if (title === null) {
            this.ui.preview.querySelector("section#programs a").classList.add("hidden");
            this.ui.preview.querySelector("section#programs span").innerText = "";
        } else {
            this.ui.preview.querySelector("section#programs a").classList.remove("hidden");
            this.ui.preview.querySelector("section#programs span").innerText = `(valikko "${title}")`;
        }
    }

    // TOD: This can be simplified
    onExitMenu(e)
    {
        e.preventDefault();

        console.log("Returning to top-level");

        this.updateMenuTitle(null);
        this.deselectItem();

        this.selection.type = ItemType.MENU;
        this.selection.id = this.current.menuID;

        // This must be cleared before calling updateView(), otherwise it thinks we're still
        // in the menu and shows wrong content
        this.current.menuID = null;

        this.updateView();

        // Re-select the menu we just exited
        for (const i of this.ui.preview.querySelectorAll("div#contents section#menus div.entries div.pmeEntry")) {
            if (i.dataset.id == this.selection.id) {
                this.selection.handle = i;
                i.classList.add("selected");
                break;
            }
        }

        this.itemEditor.setItem(this.selection.id, this.selection.type, this.data.menus[this.selection.id]);
    }

    // ----------------------------------------------------------------------------------------------
    // ----------------------------------------------------------------------------------------------
    // NEW ENTRY CREATION

    // Open the "new entry" popup
    onNewEntryClicked(e)
    {
        e.preventDefault();

        const type = e.target.dataset.type,             // the <span> has no pointer events
              template = getTemplate("newEntryPopup");

        // Fill in the existing menus/programs list. Retain filtering and indicate existing
        // entries, to prevent duplicate entries within the same category/menu.
        let all = null,
            current = null,
            filter = "";

        if (type == ItemType.MENU) {
            template.querySelector("header#hdr_program").remove();
            all = this.data.menus;
            current = this.current.menus;
            filter = this.newEntryFilterMenus;
        } else if (type == ItemType.PROGRAM) {
            template.querySelector("header#hdr_menu").remove();
            all = this.data.programs;
            current = this.current.programs;
            filter = this.newEntryFilterPrograms;
        } else {
            window.alert(`Unknown entry type "${type}". Please report this as a bug.`);
            return;
        }

        current = new Set(current === null ? [] : current);

        let list = template.querySelector("div#list");

        for (const id of sortIDs(Object.keys(all))) {
            let entry = create("div", { text: id });

            entry.dataset.id = id;

            if (!id.toLowerCase().includes(filter))     // filter
                entry.classList.add("hidden");

            if (current.has(id))                        // prevent duplicates
                entry.classList.add("alreadyIn");

            entry.addEventListener("click", e => this.onAddExistingEntry(e));

            list.appendChild(entry);
        }

        // A handy place for stashing this
        template.querySelector("div.pmeNewEntry").dataset.type = type;

        template.querySelector(`input#newName`).addEventListener("input", e => this.onNewEntryNameChanged(e));
        template.querySelector(`button`).addEventListener("click", e => this.onAddNewEntry(e));
        template.querySelector(`button`).disabled = true;

        template.querySelector(`input[type="search"]`).value = filter;
        template.querySelector(`input[type="search"]`).addEventListener("input", e => this.onFilterNewEntryList(e));

        // Display the popup
        if (modalPopup.create()) {
            modalPopup.getContents().innerText = "";
            modalPopup.getContents().appendChild(template);
            modalPopup.attach(e.target, 300);
            modalPopup.display("bottom");

            // Set the focus. Usually people create new menus, but reuse existing programs.
            modalPopup.getContents().querySelector(
                (type == ItemType.MENU) ? `input#newName` : `input[type="search"]`).focus();
        }
    }

    // Filter the existing menus/programs list in the "new entry" popup
    onFilterNewEntryList(e)
    {
        const filter = e.target.value.trim().toLowerCase();

        // Remember type-specific search strings
        if (modalPopup.getContents().querySelector("div.pmeNewEntry").dataset.type == ItemType.MENU)
            this.newEntryFilterMenus = filter;
        else this.newEntryFilterPrograms = filter;

        const list = modalPopup.getContents().querySelector(`div#list`);

        for (const i of list.querySelectorAll("div")) {
            if (i.dataset.id.toLowerCase().includes(filter))
                i.classList.remove("hidden");
            else i.classList.add("hidden");
        }
    }

    // Validate the new menu/program name
    onNewEntryNameChanged(e)
    {
        const value = e.target.value.trim();

        const button = modalPopup.getContents().querySelector("button"),
              error = modalPopup.getContents().querySelector("div.pmeError"),
              type = modalPopup.getContents().querySelector("div.pmeNewEntry").dataset.type;

        // Check for invalid names
        const match = value.match(ENTRY_ID_REGEXP);

        if (match) {
            button.disabled = true;
            error.childNodes[1].classList.remove("hidden");
            error.childNodes[1].querySelector("span").innerText = match[0];
            error.childNodes[3].classList.add("hidden");
            error.classList.remove("hidden");

            return;
        }

        // Check for duplicate names
        const exists = (value in this.data.categories) || (value in this.data.menus) || (value in this.data.programs);

        if (exists) {
            button.disabled = true;
            error.childNodes[1].classList.add("hidden");
            error.childNodes[3].classList.remove("hidden");
            error.classList.remove("hidden");

            return;
        }

        error.classList.add("hidden");

        if (value.length == 0) {
            button.disabled = true;
            return;
        }

        button.disabled = false;
    }

    // Creates a new menu or program, inserts it into the appropriate list, and selects it for editing
    onAddNewEntry(e)
    {
        e.preventDefault();

        const id = modalPopup.getContents().querySelector("div.pmeNewEntry input").value.trim(),
              type = modalPopup.getContents().querySelector("div.pmeNewEntry").dataset.type,
              isExternal = modalPopup.getContents().querySelector("input#is_external").checked;

        modalPopup.close();

        console.log(`Creating new entry "${id}", type is ${type}, external=${isExternal}`);

        let newType = null,
            newItem = null;

        if (type == ItemType.MENU) {
            let menu = new Menu();

            menu.isExternal = isExternal;

            // This instantly flags the missing name and icon as errors. Doesn't look very nice,
            // but it has to be done.
            menu.validate();

            this.data.menus[id] = menu;
            this.current.menus.push(id);

            newType = ItemType.MENU;
            newItem = this.data.menus[id];
        } else if (type == ItemType.PROGRAM) {
            let program = new Program();

            program.tags = ["default"];
            program.isExternal = isExternal;
            program.validate();

            this.data.programs[id] = program;
            this.current.programs.push(id);

            newType = ItemType.PROGRAM;
            newItem = this.data.programs[id];
        } else {
            window.alert(`Unknown entry type "${type}". Please report this as a bug.`);
            return;
        }

        // The view must be rebuilt before the element can be selected
        this.updateView();
        this.selectNewItem(id, newType, newItem);
    }

    // Insert an existing menu or program
    onAddExistingEntry(e)
    {
        e.preventDefault();

        if (e.target.classList.contains("alreadyIn"))
            return;

        const id = e.target.dataset.id;
        const type = modalPopup.getContents().querySelector("div.pmeNewEntry").dataset.type;

        modalPopup.close();

        console.log(`Appending entry "${id}", type is ${type}`);

        let newType = null,
            newItem = null;

        if (type == ItemType.MENU) {
            this.current.menus.push(id);
            newType = ItemType.MENU;
            newItem = this.data.menus[id];
        } else if (type == ItemType.PROGRAM) {
            this.current.programs.push(id);
            newType = ItemType.PROGRAM;
            newItem = this.data.programs[id];
        } else {
            window.alert(`Unknown entry type "${type}". Please report this as a bug.`);
            return;
        }

        this.updateView();
        this.selectNewItem(id, newType, newItem);
    }

    // Selects the newly-added item (menu or program). It's always at the end of the list.
    selectNewItem(id, type, item)
    {
        const all = this.ui.preview.querySelectorAll((type == ItemType.MENU) ?
            "div#contents section#menus div.entries div.pmeEntry" :
            "div#contents section#programs div.entries div.pmeEntry");

        this.deselectItem();

        this.selection.id = id;
        this.selection.type = type;
        this.selection.handle = all[all.length - 2];        // -1 is the new entry button
        this.selection.handle.classList.add("selected");

        this.itemEditor.setItem(id, type, item);
    }

    // ----------------------------------------------------------------------------------------------
    // ----------------------------------------------------------------------------------------------
    // ENTRY REMOVAL

    // Removes a menu/program from the current list
    onRemoveItem(type, id, element)
    {
        console.log(`menus: ${this.confirmMenuRemoval}  programs: ${this.confirmProgramRemoval}  type: ${type}`);

        // Confirm removals first
        if ((type == ItemType.MENU && this.confirmMenuRemoval) || (type == ItemType.PROGRAM && this.confirmProgramRemoval)) {
            if (!window.confirm(_tr("confirm_remove")))
                return;
        }

        if (this.selection.handle == element) {
            // Deleting the current item clears the item editor
            this.itemEditor.clearItem();
            this.deselectItem();
        }

        let isExternal = false;

        switch (type) {
            case ItemType.MENU: {
                const index = this.data.categories[this.current.categoryID].menus.indexOf(id);

                if (index == -1) {
                    window.alert(`Can't find item "${id}" on the list. Please report this as an error.`);
                    return;
                }

                isExternal = this.data.menus[id].isExternal;

                this.data.categories[this.current.categoryID].menus.splice(index, 1);
                break;
            }

            case ItemType.PROGRAM: {
                const index = this.current.programs.indexOf(id);

                if (index == -1) {
                    window.alert(`Can't find item "${id}" on the list. Please report this as an error.`);
                    return;
                }

                isExternal = this.data.programs[id].isExternal;

                this.current.programs.splice(index, 1);
                break;
            }

            default:
                window.alert(`Unknown entry type "${type}". Please report this as a bug.`);
                return;
        }

        // No need to call updateView()
        element.remove();

        // Automatically remove unused external menus/programs when the last reference to them
        // is removed. Typo'd and invalid entries don't hang around, allowing the user to recreate
        // them.
        if (isExternal) {
            let stillInUse = false;

            if (type == ItemType.MENU) {
                for (const cid of Object.keys(this.data.categories)) {
                    if (existsInArray(this.data.categories[cid].menus, id)) {
                        console.log(`Found menu ${id} in category ${cid}`);
                        stillInUse = true;
                        break;
                    }
                }
            } else if (type == ItemType.PROGRAM) {
                for (const cid of Object.keys(this.data.categories)) {
                    if (existsInArray(this.data.categories[cid].programs, id)) {
                        console.log(`Found program ${id} in category ${cid}`);
                        stillInUse = true;
                        break;
                    }
                }

                if (!stillInUse) {
                    for (const mid of Object.keys(this.data.menus)) {
                        if (existsInArray(this.data.menus[mid].programs, id)) {
                            console.log(`Found program ${id} in menu ${mid}`);
                            stillInUse = true;
                            break;
                        }
                    }
                }
            }

            console.log(`stillInUse: ${stillInUse}`);

            if (stillInUse)
                return;

            // Garbage collection
            if (type == ItemType.MENU)
                delete this.data.menus[id];
            else if (type == ItemType.PROGRAM)
                delete this.data.programs[id];
        }
    }

    // ----------------------------------------------------------------------------------------------
    // ----------------------------------------------------------------------------------------------
    // ENTRY UPDATES

    // Called from the child item editor when the user edits the selected item in any way
    onItemChange()
    {
        if (!this.selection.id)
            return;

        // Update warning/error CSS styles in the listing to indicate that something is wrong
        let target = null;

        switch (this.selection.type) {
            case ItemType.CATEGORY:
                target = this.data.categories[this.selection.id];
                break;

            case ItemType.MENU:
                target = this.data.menus[this.selection.id];
                break;

            case ItemType.PROGRAM:
                target = this.data.programs[this.selection.id];
                break;

            default:
                console.error(`onItemChange(): unknown item type ${this.selection.type}`);
                return;
        }

        // Add/remove the error sign
        if (target.warnings.size == 0 && target.errors.size == 0)
            this.selection.handle.classList.remove("notify");
        else this.selection.handle.classList.add("notify");
    }

    // ----------------------------------------------------------------------------------------------
    // ----------------------------------------------------------------------------------------------
    // MENU AND PROGRAM LISTS REORDERING (DRAG-AND-DROP)

    onMouseDown(e, type)
    {
        e.preventDefault();

        if (e.button != 0)
            return;

        this.drag.active = false;
        this.drag.itemID = e.target.parentNode.dataset.id;
        this.drag.itemType = type;
        this.drag.startingMousePos.x = e.clientX;
        this.drag.startingMousePos.y = e.clientY;
        this.drag.dropSlots = [];
        this.drag.sourceSlot = -1;
        this.drag.destinationSlot = -1;
        this.drag.source = e.target;
        this.drag.object = null;

        document.addEventListener("mouseup", this.onMouseButtonUp);
        document.addEventListener("mousemove", this.onMouseMove);
    }

    onMouseButtonUp(e)
    {
        if (e.button != 0)
            return;

        document.removeEventListener("mouseup", this.onMouseButtonUp);
        document.removeEventListener("mousemove", this.onMouseMove);

        if (!this.drag.active) {
            // Select an item, don't drag it
            this.onChangeSelection(this.drag.itemType, this.drag.itemID, this.drag.source.parentNode);
        } else {
            // Reorder the items
            const src = this.drag.sourceSlot,
                  dst = this.drag.targetSlot;

            if (src != -1 && dst != -1 && src != dst) {
                let list = this.ui.preview.querySelectorAll((this.drag.itemType == ItemType.MENU) ?
                    "div#contents section#menus div.entries div.pmeEntry" :
                    "div#contents section#programs div.entries div.pmeEntry");

                console.log(`Reordering item from ${src} to ${dst}`);

                // Reorder the UI elements
                if (dst > src)
                    list[dst].after(list[src]);
                else list[dst].before(list[src]);

                // Reorder the array elements
                let array;

                if (this.drag.itemType == ItemType.MENU)
                    array = this.data.categories[this.current.categoryID].menus;
                else {
                    if (this.current.menuID !== null)
                        array = this.data.menus[this.current.menuID].programs;
                    else array = this.data.categories[this.current.categoryID].programs;
                }

                array.splice(dst, 0, array.splice(src, 1)[0]);
            }
        }

        this.drag.active = false;
        this.drag.itemID = null;
        this.drag.itemType = null;
        this.drag.startingMousePos.x = 0;
        this.drag.startingMousePos.y = 0;
        this.drag.dropSlots = [];
        this.drag.sourceSlot = -1;
        this.drag.destinationSlot = -1;
        this.drag.size.w = 0;
        this.drag.size.h = 0;
        this.drag.source = null;

        if (this.drag.object) {
            this.drag.object.remove();
            this.drag.object = null;
        }

        if (this.drag.marker) {
            this.drag.marker.remove();
            this.drag.marker = null;
        }
    }

    onMouseMove(e)
    {
        if (!this.drag.active) {
            // Measure how far the mouse has been moved from the tracking start location.
            // Assume 10 pixels is "far enough".
            const dx = this.drag.startingMousePos.x - e.clientX,
                  dy = this.drag.startingMousePos.y - e.clientY;

            if (Math.sqrt(dx * dx + dy * dy) < 10.0)
                return;

            // Activate dragging
            this.drag.active = true;

            // First, find the possible drop target slots
            let slots = [];

            const items = this.ui.preview.querySelectorAll((this.drag.itemType == ItemType.MENU) ?
                "div#contents section#menus div.entries div.pmeEntry" :
                "div#contents section#programs div.entries div.pmeEntry");

            for (let i = 0; i < items.length; i++) {
                if (items[i].classList.contains("new")) {
                    // Don't move the new button
                    continue;
                }

                const rect = items[i].getBoundingClientRect();

                if (items[i].dataset.id == this.drag.source.parentNode.dataset.id)
                    this.drag.sourceSlot = i;

                // store 2D bounding boxes
                slots.push({
                    x1: Math.round(rect.left),
                    y1: Math.round(rect.top),
                    x2: Math.round(rect.right),
                    y2: Math.round(rect.bottom),
                    h: Math.round(rect.height),
                });
            }

            this.drag.dropSlots = slots;

            // Then create the drag-and-drop mock object and the drop marker
            const rect = this.drag.source.getBoundingClientRect();

            this.drag.offset.x = e.clientX - rect.left;
            this.drag.offset.y = rect.height / 2;           // keep vertically centered

            let drag = create("div", { cls: "pmeDrag", text: this.drag.itemID });

            drag.style.width = `${rect.width}px`;
            drag.style.height = `${rect.height}px`;

            this.drag.object = drag;

            let marker = create("div", { cls: ["pmeDragMarker"] });

            marker.style.width = `2px`;

            this.drag.marker = marker;

            document.body.appendChild(this.drag.object);
            document.body.appendChild(this.drag.marker);
        }

        // Position the drag-and-drop mock element. Clamp it against the window edges to prevent
        // unnecessary scrollbars from appearing.
        const mx = e.clientX + window.scrollX,
              my = e.clientY + window.scrollY;

        const windowW = document.body.scrollWidth,      // not the best, but nothing else...
              windowH = document.body.scrollHeight;     // ...works even remotely nicely here

        const dx = Math.max(0, Math.min(mx - this.drag.offset.x, windowW - this.drag.size.w)),
              dy = Math.max(0, Math.min(my - this.drag.offset.y, windowH - this.drag.size.h));

        this.drag.object.style.left = `${dx}px`;
        this.drag.object.style.top = `${dy}px`;

        // Find the slot below the mouse, and (re)position the marker
        let candidate = null;

        this.drag.targetSlot = -1;

        for (let i = 0; i < this.drag.dropSlots.length; i++) {
            const slot = this.drag.dropSlots[i];

            if (mx < slot.x1)
                continue;

            if (my < slot.y1)
                continue;

            if (mx > slot.x2)
                continue;

            if (my > slot.y2)
                continue;

            candidate = slot;
            this.drag.targetSlot = i;

            break;
        }

        if (candidate === null)
            this.drag.marker.classList.add("hidden");
        else {
            this.drag.marker.classList.remove("hidden");
            this.drag.marker.style.left = `${candidate.x1 - 3}px`;
            this.drag.marker.style.top = `${candidate.y1 - 5}px`;
            this.drag.marker.style.height = `${candidate.h + 10}px`;
        }
    }

    // ----------------------------------------------------------------------------------------------
    // ----------------------------------------------------------------------------------------------
    // ENTRY RENAMING

    // Returns true if the ID is unique. Called from the item editor (it has no access to
    // the full menudata).
    isIDUnique(id)
    {
        return (id in this.data.categories) ||
               (id in this.data.menus) ||
               (id in this.data.programs);
    }

    // Changes the ID of the currently selected item. Called from the item editor.
    renameCurrentEntry(newID)
    {
        switch (this.selection.type) {
            case ItemType.CATEGORY:
                console.log(`Renaming category "${this.selection.id}" to "${newID}"`);

                // UI update
                for (const tab of this.ui.tabs.querySelectorAll("div.tab")) {
                    if (tab.dataset.cid == this.selection.id) {
                        tab.dataset.cid = newID;
                        tab.querySelector("span.id").innerText = newID;
                        break;
                    }
                }

                this.data.categories[newID] = this.data.categories[this.selection.id];
                delete this.data.categories[this.selection.id];

                this.current.categoryID = newID;
                this.selection.id = newID;

                this.data.sortCategories();

                break;

            case ItemType.MENU:
                console.log(`Renaming menu "${this.selection.id}" to "${newID}"`);

                // Update all references to this menu
                for (const cid of Object.keys(this.data.categories)) {
                    const category = this.data.categories[cid];

                    for (let i = 0; i < category.menus.length; i++) {
                        if (category.menus[i] == this.selection.id)
                            category.menus[i] = newID;
                    }
                }

                this.selection.handle.dataset.id = newID;
                this.selection.handle.querySelector("span.id").innerText = newID;

                this.data.menus[newID] = this.data.menus[this.selection.id];
                delete this.data.menus[this.selection.id];
                this.selection.id = newID;

                break;

            case ItemType.PROGRAM:
                console.log(`Renaming program "${this.selection.id}" to "${newID}"`);

                // Update all references to this program
                for (const cid of Object.keys(this.data.categories)) {
                    const category = this.data.categories[cid];

                    for (let i = 0; i < category.programs.length; i++) {
                        if (category.programs[i] == this.selection.id)
                            category.programs[i] = newID;
                    }
                }

                for (const mid of Object.keys(this.data.menus)) {
                    const menu = this.data.menus[mid];

                    for (let i = 0; i < menu.programs.length; i++) {
                        if (menu.programs[i] == this.selection.id)
                            menu.programs[i] = newID;
                    }
                }

                this.selection.handle.dataset.id = newID;
                this.selection.handle.querySelector("span.id").innerText = newID;

                this.data.programs[newID] = this.data.programs[this.selection.id];
                delete this.data.programs[this.selection.id];
                this.selection.id = newID;

                break;

            default:
                break;
        }
    }

    // ----------------------------------------------------------------------------------------------
    // ----------------------------------------------------------------------------------------------
    // RAW JSON EDITOR

    onOpenJSONEditor(e)
    {
        const template = getTemplate("JSONEditorPopup");

        template.querySelector("textarea#json").value = JSON.stringify(this.data.save(), null, "    ");
        template.querySelector("textarea#json").addEventListener("input", () => this.onChangeJSON());
        template.querySelector("button#save").addEventListener("click", () => this.onSaveJSON());

        if (modalPopup.create()) {
            modalPopup.getContents().innerText = "";
            modalPopup.getContents().appendChild(template);
            modalPopup.attach(e.target, 800);
            modalPopup.display("bottom");
        }
    }

    onChangeJSON()
    {
        const textarea = modalPopup.getContents().querySelector("textarea#json"),
              button = modalPopup.getContents().querySelector("button#save"),
              error = modalPopup.getContents().querySelector("div.pmeError");

        // The error message uses "not-visible" (instead of "hidden") because the message
        // has more padding than the button, so toggling its visibility alters the line height.
        // But "not-visible" does not, because the element is still there.

        try {
            JSON.parse(textarea.value.trim());
            button.disabled = false;
            error.classList.add("not-visible");
        } catch (e) {
            button.disabled = true;
            error.classList.remove("not-visible");
        }
    }

    onSaveJSON()
    {
        const json = modalPopup.getContents().querySelector("textarea#json").value.trim();

        modalPopup.close();

        // Regenerate the editor from scratch
        this.data = new Menudata(json, this.restrictedMode);

        this.current.categoryID = this.data.categoryIndex[0][1];
        this.current.menuID = null;
        this.current.menus = null;
        this.current.programs = null;

        this.selection.type = ItemType.NONE;
        this.selection.id = null;
        this.selection.handle = null;

        this.createTabs();
        this.updateView();
        this.updateMenuTitle(null);
        this.itemEditor.clearItem();
    }

    // ----------------------------------------------------------------------------------------------
    // ----------------------------------------------------------------------------------------------
    // UNUSED ENTRIES

    onFindUnusedEntries(e)
    {
        // Count how many times each menu and program is refereneced. Use sortIDs() when
        // building the initial maps, so the entries are alphabetically sorted.
        let allMenus = new Map(),
            allPrograms = new Map();

        for (const mid of sortIDs(Object.keys(this.data.menus)))
            allMenus.set(mid, 0);

        for (const pid of sortIDs(Object.keys(this.data.programs)))
            allPrograms.set(pid, 0);

        for (const cid of Object.keys(this.data.categories)) {
            for (const mid of this.data.categories[cid].menus)
                allMenus.set(mid, allMenus.get(mid) + 1);

            for (const pid of this.data.categories[cid].programs)
                allPrograms.set(pid, allPrograms.get(pid) + 1);
        }

        for (const mid of Object.keys(this.data.menus)) {
            // Don't let unused menus skew program counters
            if (allMenus.get(mid) == 0) {
                console.log(`Menu ${mid} is not used, ignoring`);
                continue;
            }

            for (const pid of this.data.menus[mid].programs)
                allPrograms.set(pid, allPrograms.get(pid) + 1);
        }

        let numUnused = 0,
            html = "";

        const addEntry = (id, type, typeStr) => {
            return `<tr data-id="${id}" data-type="${type}">` +
                   `<td><label><input type="checkbox">${id}</label></td>` +
                   `<td class="minimize-width">${typeStr}</td>` +
                   `</tr>`;
        };

        for (const [id, uses] of allMenus) {
            if (uses == 0) {
                html += addEntry(id, ItemType.MENU, _tr("unused.type_menu"));
                numUnused++;
            }
        }

        for (const [id, uses] of allPrograms) {
            if (uses == 0) {
                html += addEntry(id, ItemType.PROGRAM, _tr("unused.type_program"));
                numUnused++;
            }
        }

        if (numUnused == 0) {
            window.alert(_tr("unused.no_unused_entries"));
            return;
        }

        const template = getTemplate("unusedEntriesPopup");

        template.querySelector("table tbody").innerHTML = html;

        template.querySelector("button#select_all").addEventListener("click", () => this.onSelectAllUnusedEntries());
        template.querySelector("button#remove_selected").addEventListener("click", () => this.onDeleteUnusedEntries());

        if (modalPopup.create()) {
            modalPopup.getContents().innerText = "";
            modalPopup.getContents().appendChild(template);
            modalPopup.attach(e.target, 400);
            modalPopup.display("bottom");
        }
    }

    onSelectAllUnusedEntries()
    {
        for (const i of modalPopup.getContents().querySelectorAll(`input[type="checkbox"]`))
            i.checked = true;
    }

    onDeleteUnusedEntries()
    {
        for (const i of modalPopup.getContents().querySelectorAll(`input[type="checkbox"]:checked`)) {
            const node = i.parentNode.parentNode.parentNode;

            const id = node.dataset.id,
                  type = parseInt(node.dataset.type, 10);

            switch (type) {
                case ItemType.MENU:
                    delete this.data.menus[id];
                    break;

                case ItemType.PROGRAM:
                    delete this.data.programs[id];
                    break;

                default:
                    break;
            }
        }

        modalPopup.close();

        // The view does not need updating, because these unused entries are not visible
    }

    // ----------------------------------------------------------------------------------------------
    // ----------------------------------------------------------------------------------------------
    // SEARCH

    onShowSearch(e)
    {
        const template = getTemplate("search");

        const box = template.querySelector("input#term");

        box.value = this.searchTerm;

        box.addEventListener("input", (e) => {
            this.searchTerm = e.target.value.trim();
            this.onSearch();
        });

        if (modalPopup.create()) {
            modalPopup.getContents().innerText = "";
            modalPopup.getContents().appendChild(template);
            modalPopup.attach(e.target, 400);
            modalPopup.display("bottom");

            modalPopup.getContents().querySelector("input#term").focus();

            // Initial search update
            this.onSearch();
        }
    }

    onSearch()
    {
        const term = this.searchTerm.toLowerCase();

        let html = "";
        let found = false;

        if (term.length > 0) {
            const usedMenus = new Set(),
                  usedPrograms = new Set();

            // Categories
            for (const cid of Object.keys(this.data.categories)) {
                if (cid.toLowerCase().includes(term)) {
                    html += `<li><a href="#" data-path="${cid}">${cid}</a></li>`;
                    found = true;
                }
            }

            // Menus and programs inside categories
            for (const cid of Object.keys(this.data.categories)) {
                const category = this.data.categories[cid];
                let addedCategory = false;

                for (const mid of category.menus) {
                    const menu = this.data.menus[mid];

                    if (mid.toLowerCase().includes(term)) {
                        html += `<li><a href="#" data-path="${cid},${mid}">${cid} / ${mid}</a></li>\n`;
                        usedMenus.add(mid);
                        found = true;
                    }

                    for (const pid of menu.programs) {
                        if (pid.toLowerCase().includes(term)) {
                            html += `<li><a href="#" data-path="${cid},${mid},${pid}">${cid} / ${mid} / ${pid}</a></li>\n`;
                            usedPrograms.add(pid);
                            found = true;
                        }
                    }
                }

                for (const pid of category.programs) {
                    if (pid.toLowerCase().includes(term)) {
                        // empty menu name, so even top-level programs have a three-part path
                        html += `<li><a href="#" data-path="${cid},,${pid}">${cid} / ${pid}</a></li>\n`;
                        usedPrograms.add(pid);
                        found = true;
                    }
                }
            }

            // Unused menus and programs. These cannot be clicked, because there's nothing to open.
            for (const mid of Object.keys(this.data.menus)) {
                if (usedMenus.has(mid))
                    continue;

                if (mid.toLowerCase().includes(term)) {
                    html += `<li>${mid} <em>(${_tr("unused.unused_title")})</em></li>\n`;
                    found = true;
                }
            }

            for (const pid of Object.keys(this.data.programs)) {
                if (usedPrograms.has(pid))
                    continue;

                if (pid.toLowerCase().includes(term)) {
                    html += `<li>${pid} <em>(${_tr("unused.unused_title")})</em></li>\n`;
                    found = true;
                }
            }
        }

        const results = modalPopup.getContents().querySelector("div#results"),
              noResults = modalPopup.getContents().querySelector("div#no_results");

        if (found) {
            results.innerHTML = "<ul>" + html + "</ul>";

            for (const i of results.querySelectorAll("a"))
                i.addEventListener("click", (e) => this.onJumpToSearchResult(e));

            results.classList.remove("hidden");
            noResults.classList.add("hidden");
        } else {
            noResults.classList.remove("hidden");
            results.classList.add("hidden");
            results.innerText = "";
        }
    }

    onJumpToSearchResult(e)
    {
        e.preventDefault();

        const parts = e.target.dataset.path.split(",");

        this.deselectItem();

        let item = null;

        this.current.categoryID = parts[0];
        this.current.menuID = null;             // not in a menu by default

        if (parts.length == 3 && parts[1] != "") {
            // This program is in a menu
            this.current.menuID = parts[1];
        } else this.updateMenuTitle(null);

        this.createTabs();
        this.updateView();

        if (parts.length == 3 && parts[1] != "") {
            // Display the menu title
            this.updateMenuTitle(parts[1]);
        }

        if (parts.length == 1) {
            // Category
            this.selection.type = ItemType.CATEGORY;
            this.selection.id = parts[0];
            this.selection.handle = this.ui.tabs.querySelector("div.tab.current");

            item = this.data.categories[parts[0]];
        } else if (parts.length == 2) {
            // Menu
            this.selection.type = ItemType.MENU;
            this.selection.id = parts[1];
            this.selection.handle = this.ui.preview.querySelector(`div#contents section#menus div.entries div.pmeEntry[data-id="${parts[1]}"]`);

            item = this.data.menus[parts[1]];
        } else if (parts.length == 3) {
            // Program
            this.selection.type = ItemType.PROGRAM;
            this.selection.id = parts[2];
            this.selection.handle = this.ui.preview.querySelector(`div#contents section#programs div.entries div.pmeEntry[data-id="${parts[2]}"]`);

            item = this.data.programs[parts[2]];
        } else {
            window.alert("Can't figure out what you clicked. Please report this as a bug!");
            return;
        }

        this.selection.handle.classList.add("selected");
        this.itemEditor.setItem(this.selection.id, this.selection.type, item);
    }
}
