"use strict";

// The right-side item editor

import { create, getTemplate, toggleClass } from "../common/dom.js";
import { ProgramType } from "./data/program.js";
import { ENTRY_ID_REGEXP } from "./main.js";

export const ItemType = {
    NONE: -1,
    CATEGORY: 1,
    MENU: 2,
    PROGRAM: 3,
};

// Splits a string. Accepts ",", ", " and " " as separators. Returns an empty array if
// the input is not a string.
const splitMultiValue = (s) => (typeof(s) == "string") ? s.trim().split(/,\ |,|\ /).filter(i => i) : [];

export class ItemEditor {
    constructor(container, restrictedMode, parentClass)
    {
        this.container = container;
        this.restrictedMode = restrictedMode;
        this.parentClass = parentClass;

        this.itemID = null;
        this.itemType = null;
        this.item = null;

        // Setup events
        for (let i of this.container.querySelectorAll(`details#sect_catid button, details#sect_menuid button, details#sect_progid button`))
            i.addEventListener("click", e => this.onShowRenameEntryDialog(e));

        this.container.querySelector(`details#sect_progtype input[type="radio"]#desktop`).
            addEventListener("click", () => this.onChangeProgramType(ProgramType.DESKTOP));

        this.container.querySelector(`details#sect_progtype input[type="radio"]#custom`).
            addEventListener("click", () => this.onChangeProgramType(ProgramType.CUSTOM));

        this.container.querySelector(`details#sect_progtype input[type="radio"]#web`).
            addEventListener("click", () => this.onChangeProgramType(ProgramType.WEB_LINK));

        for (let i of this.container.querySelectorAll(`details#sect_name div.contents input[type="radio"]`))
            i.addEventListener("input", e => this.onChangeTranslationType("name", e.target.id));

        for (let i of this.container.querySelectorAll(`details#sect_description div.contents input[type="radio"]`))
            i.addEventListener("input", e => this.onChangeTranslationType("description", e.target.id));

        for (let i of this.container.querySelectorAll(`details#sect_name div.contents input[type="text"]`))
            i.addEventListener("input", e => this.onChangeName(e));

        for (let i of this.container.querySelectorAll(`details#sect_description div.contents input[type="text"]`))
            i.addEventListener("input", e => this.onChangeDescription(e));

        for (let i of this.container.querySelectorAll(`details#sect_position div.contents input#position`))
            i.addEventListener("input", e => this.onChangeCategoryPosition(e));

        for (let i of this.container.querySelectorAll(`details#sect_icon div.contents input#icon`))
            i.addEventListener("input", e => this.onChangeIcon(e));

        for (let i of this.container.querySelectorAll(`details#sect_command div.contents input#command`))
            i.addEventListener("input", e => this.onChangeCommand(e));

        for (let i of this.container.querySelectorAll(`details#sect_url div.contents input#url`))
            i.addEventListener("input", e => this.onChangeURL(e));

        for (let i of this.container.querySelectorAll(`details#sect_keywords div.contents input#keywords`))
            i.addEventListener("input", e => this.onChangeKeywords(e));

        for (let i of this.container.querySelectorAll(`details#sect_visibility div.contents input#tags`))
            i.addEventListener("input", e => this.onChangeTags(e));

        for (let i of this.container.querySelectorAll(`details#sect_visibility div.contents select, details#sect_visibility div.contents input[type="checkbox"]`))
            i.addEventListener("input", e => this.onChangeCondition(e));

        for (const i of this.container.querySelectorAll("a.help"))
            i.addEventListener("click", e => this.onShowHelp(e));

        this.hideAllMessages();
    }

    clearItem()
    {
        this.itemID = null;
        this.itemType = null;
        this.item = null;

        toggleClass(this.container.querySelector("div#select_something"), "hidden", false);
        toggleClass(this.container.querySelector("div#external_menu"), "hidden", true);
        toggleClass(this.container.querySelector("div#external_program"), "hidden", true);
        toggleClass(this.container.querySelector("div#wrapper"), "hidden", true);

        this.hideAllMessages();
    }

    setItem(id, type, item)
    {
        toggleClass(this.container.querySelector("div#select_something"), "hidden", true);

        if ((type == ItemType.PROGRAM || type == ItemType.MENU) && item.isExternal) {
            // Hide the editor for external menus and programs
            toggleClass(this.container.querySelector("div#external_menu"), "hidden", type == ItemType.PROGRAM);
            toggleClass(this.container.querySelector("div#external_program"), "hidden", type == ItemType.MENU);
            toggleClass(this.container.querySelector("div#wrapper"), "hidden", true);
            this.hideAllMessages();

            return;
        }

        toggleClass(this.container.querySelector("div#external_menu"), "hidden", true);
        toggleClass(this.container.querySelector("div#external_program"), "hidden", true);
        toggleClass(this.container.querySelector("div#wrapper"), "hidden", false);

        this.itemID = id;
        this.itemType = type;
        this.item = item;

        // Hide editor UI elements that aren't used with this type of an item
        const isCategory = this.itemType == ItemType.CATEGORY,
              isMenu = this.itemType == ItemType.MENU,
              isProgram = this.itemType == ItemType.PROGRAM;

        this.showSection("progtype", isProgram);
        this.showSection("catid", isCategory);
        this.showSection("menuid", isMenu);
        this.showSection("progid", isProgram);
        this.showSection("description", isMenu || isProgram);
        this.showSection("position", isCategory);
        this.showSection("icon", isMenu || isProgram);
        this.showSection("keywords", isProgram);
        this.showSection("command", isProgram);
        this.showSection("url", isProgram && this.item.programType == ProgramType.WEB_LINK);

        this.updateWarningsAndErrors();

        // Update input field values. Some of them are common, but most aren't.
        this.setTranslatedEntry("name", this.item.name);
        this.updateVisibilityValues();

        toggleClass(this.container.querySelector("details#sect_visibility label#tagsLabel"), "hidden", !isProgram);
        toggleClass(this.container.querySelector("details#sect_visibility input#tags"), "hidden", !isProgram);

        if (isCategory) {
            this.container.querySelector("details#sect_catid input#cid").value = this.itemID;
            this.container.querySelector("details#sect_position input").value = this.item.position;

            // Editing the category position in restricted mode makes no sense.
            this.container.querySelector("details#sect_position input").disabled = this.restrictedMode;
            this.container.querySelector("details#sect_catid button").disabled = this.restrictedMode;
        }

        if (isMenu) {
            this.container.querySelector("details#sect_menuid input#mid").value = this.itemID;
        }

        if (isProgram) {
            this.container.querySelector(`input[type="radio"]#desktop`).checked = this.item.programType == ProgramType.DESKTOP;
            this.container.querySelector(`input[type="radio"]#custom`).checked = this.item.programType == ProgramType.CUSTOM;
            this.container.querySelector(`input[type="radio"]#web`).checked = this.item.programType == ProgramType.WEB_LINK;
            this.updateProgramTypeTitle();

            this.container.querySelector("details#sect_progid input#pid").value = this.itemID;
            this.container.querySelector("details#sect_visibility input#tags").value = this.item.tags.join(" ");
            this.container.querySelector("details#sect_keywords input#keywords").value = this.item.keywords.join(" ");
            this.container.querySelector("details#sect_command input#command").value = this.item.command;
            this.container.querySelector("details#sect_url input#url").value = this.item.url;
        }

        if (isMenu || isProgram) {
            this.setTranslatedEntry("description", this.item.description);
            this.container.querySelector("details#sect_icon input#icon").value = this.item.icon;
        }
    }

    showSection(id, condition)
    {
        toggleClass(this.container.querySelector(`details#sect_${id}`), "hidden", !condition);
    }

    setTranslatedEntry(sectionID, value)
    {
        const section = this.container.querySelector(`details#sect_${sectionID}`);

        if (!section) {
            console.warn(`setTranslatedEntry(): unknown section "sect_${sectionID}"`);
            return;
        }

        section.querySelector(`input[type="radio"]#${sectionID}-one`).checked = value.isSingle;
        section.querySelector(`input[type="radio"]#${sectionID}-multi`).checked = !value.isSingle;

        const textOne = section.querySelector(`input[type="text"]#${sectionID}-one-value`);

        textOne.value = value.single;
        textOne.disabled = !value.isSingle;

        for (const lang of ["en", "fi", "sv", "de"]) {
            const input = section.querySelector(`input[type="text"]#${sectionID}-multi-value-${lang}`);

            input.value = value.multi[lang];
            input.disabled = value.isSingle;
        }
    }

    // Updates the "visibility" section
    updateVisibilityValues()
    {
        const section = this.container.querySelector(`details#sect_visibility`);

        const condition = this.container.querySelector(`select#condition`),
              reverse = this.container.querySelector(`input[type="checkbox"]#reverse`);

        if (this.item.condition == "") {
            condition.value = "";
            reverse.checked = false;
        } else {
            condition.value = this.item.condition[0] == "!" ? this.item.condition.substring(1) : this.item.condition;
            reverse.checked = this.item.condition[0] == "!";
        }

        section.querySelector(`input[type="checkbox"]#hidden_by_default`).checked = this.item.hiddenByDefault;
    }

    updateProgramTypeTitle()
    {
        toggleClass(this.container.querySelector("details#sect_progid span#desktopID"), "hidden", this.item.programType != ProgramType.DESKTOP);
        toggleClass(this.container.querySelector("details#sect_progid span#otherID"), "hidden", this.item.programType == ProgramType.DESKTOP);
    }

    hideAllMessages()
    {
        for (let i of this.container.querySelectorAll(`details summary span.notify`))
            i.classList.add("hidden");

        for (let i of this.container.querySelectorAll(`div.pmeWarning, div.pmeError`))
            i.classList.add("hidden");
    }

    updateWarningsAndErrors()
    {
        if (!this.item) {
            this.hideAllMessages();
            return;
        }

        // Automatically show or hide the notification flags of each section: if the section
        // has any visible warnings or errors, show the flag. Otherwise hide it.
        let notifications = {};

        for (const i of this.container.querySelectorAll("details summary span.notify")) {
            const id = i.closest("details").id.replace("sect_", "");

            notifications[id] = {
                element: i,
                visible: false
            }
        }

        for (const i of this.container.querySelectorAll(`div.pmeWarning, div.pmeError`)) {
            if (i.classList.contains("pmeWarning")) {
                if (!this.item.warnings.has(i.dataset.code)) {
                    i.classList.add("hidden");
                    continue;
                }
            } else {
                if (!this.item.errors.has(i.dataset.code)) {
                    i.classList.add("hidden");
                    continue;
                }
            }

            // This message should be visible
            i.classList.remove("hidden");

            // Flag the notification icon for this section as visible
            notifications[i.closest("details").id.replace("sect_", "")].visible = true;
        }

        // Update section notification flag visibilities. They serve as an indicator that
        // something is wrong in this section even if it's closed.
        for (const i of Object.values(notifications))
            toggleClass(i.element, "hidden", !i.visible);
    }

    // Opens the help text popup for the current item
    onShowHelp(e)
    {
        e.preventDefault();

        const id = e.target.closest("details").id.replace("sect_", "");

        // Take the current language into account when looking for help texts
        const rawTemplate = document.querySelector(`template[lang="${I18n.locale}"]#template_help`);

        if (!rawTemplate) {
            console.error(`Can't find help text template for language "${I18n.locale}".`);
            window.alert(`Sorry, no help text could be found for item "${id}". Please report this as a bug.`);
            return;
        }

        const template = rawTemplate.content.cloneNode(true).querySelector(`div#help_${id}`);

        if (!template) {
            console.error(`No help node found for ID "${id}".`);
            window.alert(`Sorry, no help text could be found for item "${id}". Please report this as a bug.`);
            return;
        }

        if (modalPopup.create()) {
            modalPopup.getContents().innerText = "";
            modalPopup.getContents().appendChild(template);
            modalPopup.attach(e.target, parseInt(template.dataset.width, 10));
            modalPopup.display("bottom");
        }
    }

    // ----------------------------------------------------------------------------------------------
    // ----------------------------------------------------------------------------------------------
    // VALUE EDITING

    // Change the current program type. Alters the UI section visibilities to match.
    onChangeProgramType(type)
    {
        // string -> proper type
        if (type == ProgramType.DESKTOP)
            this.item.programType = ProgramType.DESKTOP;
        else if (type == ProgramType.CUSTOM)
            this.item.programType = ProgramType.CUSTOM;
        else if (type == ProgramType.WEB_LINK)
            this.item.programType = ProgramType.WEB_LINK;

        this.showSection("command", type == ProgramType.CUSTOM);
        this.showSection("url", type == ProgramType.WEB_LINK);

        this.item.validate();
        this.updateProgramTypeTitle();
        this.updateWarningsAndErrors();
        this.parentClass.onItemChange();
    }

    // Changes the translation type (single/multi) of the specified section
    onChangeTranslationType(section, id)
    {
        this.container.querySelector(`details#sect_${section} input#${section}-one-value`)
            .disabled = (id != `${section}-one`);

        for (const lang of ["en", "fi", "sv", "de"]) {
            this.container.querySelector(`details#sect_${section} input#${section}-multi-value-${lang}`)
                .disabled = (id == `${section}-one`);
        }

        this.item[section].isSingle = (id == `${section}-one`);

        this.item.validate();
        this.updateWarningsAndErrors();
        this.parentClass.onItemChange();
    }

    // TODO: These can be simplified/merged
    onChangeName(e)
    {
        const value = e.target.value.trim();

        switch (e.target.id) {
            case "name-one-value":
                this.item.name.single = value;
                break;

            case "name-multi-value-fi":
                this.item.name.multi["fi"] = value;
                break;

            case "name-multi-value-en":
                this.item.name.multi["en"] = value;
                break;

            case "name-multi-value-sv":
                this.item.name.multi["sv"] = value;
                break;

            case "name-multi-value-de":
                this.item.name.multi["de"] = value;
                break;
        }

        this.item.validate();
        this.updateWarningsAndErrors();
        this.parentClass.onItemChange();
    }

    onChangeDescription(e)
    {
        const value = e.target.value.trim();

        switch (e.target.id) {
            case "description-one-value":
                this.item.description.single = value;
                break;

            case "description-multi-value-fi":
                this.item.description.multi["fi"] = value;
                break;

            case "description-multi-value-en":
                this.item.description.multi["en"] = value;
                break;

            case "description-multi-value-sv":
                this.item.description.multi["sv"] = value;
                break;

            case "description-multi-value-de":
                this.item.description.multi["de"] = value;
                break;
        }

        this.item.validate();
        this.updateWarningsAndErrors();
        this.parentClass.onItemChange();
    }

    onChangeIcon(e)
    {
        if (this.itemType != ItemType.MENU && this.itemType != ItemType.PROGRAM)
            return;

        this.item.icon = e.target.value.trim();
        this.item.validate();
        this.updateWarningsAndErrors();
        this.parentClass.onItemChange();
    }

    onChangeCommand(e)
    {
        if (this.itemType != ItemType.PROGRAM)
            return;

        if (this.item.programType != ProgramType.DESKTOP && this.item.programType != ProgramType.CUSTOM)
            return;

        this.item.command = e.target.value.trim();
        this.item.validate();
        this.updateWarningsAndErrors();
        this.parentClass.onItemChange();
    }

    onChangeURL(e)
    {
        if (this.itemType != ItemType.PROGRAM)
            return;

        if (this.item.programType != ProgramType.WEB_LINK)
            return;

        this.item.url = e.target.value.trim();
        this.item.validate();
        this.updateWarningsAndErrors();
        this.parentClass.onItemChange();
    }

    onChangeKeywords(e)
    {
        if (this.itemType != ItemType.PROGRAM)
            return;

        this.item.keywords = splitMultiValue(e.target.value);

        this.item.validate();
        this.updateWarningsAndErrors();
        this.parentClass.onItemChange();
    }

    onChangeTags(e)
    {
        if (this.itemType != ItemType.PROGRAM)
            return;

        this.item.tags = splitMultiValue(e.target.value);
        this.item.validate();
        this.updateWarningsAndErrors();
        this.parentClass.onItemChange();
    }

    onChangeCategoryPosition(e)
    {
        if (this.itemType != ItemType.CATEGORY)
            return;

        if (this.restrictedMode)
            return;

        const value = e.target.value.trim();

        try {
            this.item.position = (value.length > 0) ? parseInt(value, 10) : 0;
        } catch (whatever) {
            this.item.position = 0;
        }

        this.item.validate();
        this.parentClass.onItemChange();
    }

    onChangeCondition(e)
    {
        const condition = this.container.querySelector(`details#sect_visibility div.contents select`).value,
              reverse = this.container.querySelector(`details#sect_visibility div.contents input[type="checkbox"]`).checked;

        switch (e.target.id) {
            case "condition":
            case "reverse":
                if (condition == "")
                    this.item.condition = "";
                else this.item.condition = reverse ? "!" + condition : condition;

                break;

            case "hidden_by_default":
                this.item.hiddenByDefault = e.target.checked;
                break;

            default:
                return;
        }

        this.item.validate();
        this.parentClass.onItemChange();
    }

    // ----------------------------------------------------------------------------------------------
    // ----------------------------------------------------------------------------------------------
    // ENTRY RENAMING

    // This only implements the user interface. The actual renaming is done in main.js, method
    // renameCurrentEntry(). This is because this sidebar editor has no access to the full
    // menudata, it sees only the current item.

    onShowRenameEntryDialog(e)
    {
        const template = getTemplate("renameEntry");

        switch (this.itemType) {
            case ItemType.CATEGORY:
                if (this.restrictedMode)
                    return;

                template.querySelector(`label[data-for="menu"]`).remove();
                template.querySelector(`label[data-for="program"]`).remove();
                break;

            case ItemType.MENU:
                template.querySelector(`label[data-for="category"]`).remove();
                template.querySelector(`label[data-for="program"]`).remove();
                break;

            case ItemType.PROGRAM:
                template.querySelector(`label[data-for="category"]`).remove();
                template.querySelector(`label[data-for="menu"]`).remove();
                break;
        }

        template.querySelector("input#newID").value = this.itemID;
        template.querySelector("input#newID").addEventListener("input", e => this.onRenameEntryNewIDChanged(e));
        template.querySelector("button").addEventListener("click", e => this.onRenameEntry(e));

        if (modalPopup.create()) {
            modalPopup.getContents().innerText = "";
            modalPopup.getContents().appendChild(template);
            modalPopup.attach(e.target, 300);
            modalPopup.display("bottom");

            modalPopup.getContents().querySelector("input#newID").focus();
        }
    }

    onRenameEntryNewIDChanged(e)
    {
        const newID = e.target.value.trim();

        const button = modalPopup.getContents().querySelector("button"),
              error = modalPopup.getContents().querySelector("div.pmeError");

        // Check for invalid names
        const match = newID.match(ENTRY_ID_REGEXP);

        if (match) {
            button.disabled = true;
            error.childNodes[1].classList.remove("hidden");
            error.childNodes[1].querySelector("span").innerText = match[0];
            error.childNodes[3].classList.add("hidden");
            error.classList.remove("hidden");

            return;
        }

        // Check for duplicate names (but not against the original)
        const exists = (newID != this.itemID) && this.parentClass.isIDUnique(newID);

        if (exists) {
            button.disabled = true;
            error.childNodes[1].classList.add("hidden");
            error.childNodes[3].classList.remove("hidden");
            error.classList.remove("hidden");

            return;
        }

        error.classList.add("hidden");

        if (newID.length == 0) {
            button.disabled = true;
            return;
        }

        button.disabled = false;
    }

    onRenameEntry(e)
    {
        const newID = modalPopup.getContents().querySelector("input#newID").value.trim();

        modalPopup.close();

        if (newID == this.itemID) {
            console.log("Nothing to change");
            return;
        }

        this.itemID = newID;

        // Actually do the renaming
        this.parentClass.renameCurrentEntry(newID);

        switch (this.itemType) {
            case ItemType.CATEGORY:
                this.container.querySelector(`details#sect_catid input#cid`).value = newID;
                break;

            case ItemType.MENU:
                this.container.querySelector(`details#sect_menuid input#mid`).value = newID;
                break;

            case ItemType.PROGRAM:
                this.container.querySelector(`details#sect_progid input#pid`).value = newID;
                break;

            default:
                break;
        }
    }
}
