"use strict";

// A special editor for Puavomenu tags (ie. filter strings)

import { create, getTemplate } from "../common/dom.js";
import { ConfigEntry } from "./config_entry.js";

export class ConfigPuavomenuTags extends ConfigEntry {
    constructor(parent, key, value)
    {
        super(parent);

        this.key = key;
        this.value = value;
        this.container = null;

        // Created by calling load()
        this.tags = [];
    }

    createEditor(container)
    {
        const template = getTemplate("puavoconfPuavomenuInput");
        const input = template.querySelector("input");

        input.value = this.value;
        input.addEventListener("input", event => this.onChangeInput(event));

        container.appendChild(template);

        this.container = container;

        this.load();
        this.createDetails();
        this.explain();

        container.appendChild(this.details);
    }

    onChangeInput(event)
    {
        this.value = event.target.value;
        this.load();
        this.explain();
        this.valueChanged();
    }

    load()
    {
        const TAG_SPLITTER = /,|;|\ /,
              TAG_MATCHER = /^(?<action>(\+|\-))?((?<namespace>c|cat|category|m|menu|p|prog|program|t|tag)\:)?(?<target>[a-zA-Z0-9\-_\.]+)$/;

        this.tags = [];

        for (const tag of (this.value === null ? "" : this.value.trim()).split(TAG_SPLITTER)) {
            if (tag.trim().length == 0)
                continue;

            const match = tag.match(TAG_MATCHER);

            if (!match) {
                // Invalid tag
                this.tags.push({
                    valid: false,
                    action: null,
                    namespace: null,
                    target: null
                });

                continue;
            }

            const action = (match.groups.action && match.groups.action == "-") ? "hide" : "show";
            let namespace = undefined;

            switch (match.groups.namespace) {
                case "c":
                case "cat":
                case "category":
                    namespace = "category";
                    break;

                case "m":
                case "menu":
                    namespace = "menu";
                    break;

                case "p":
                case "prog":
                case "program":
                    namespace = "program";
                    break;

                case undefined:     // unmatched regexp group ends up here too
                default:
                    namespace = "tag";
                    break;
            }

            // Valid tag
            this.tags.push({
                valid: true,
                action: action,
                namespace: namespace,
                target: match.groups.target
            });
        }
    }

    save(fullRebuild=false)
    {
        let tags = [];

        for (const t of this.tags) {
            if (!t.valid || !t.target)
                continue;

            let tag = [];

            if (t.action == "hide")
                tag.push("-");

            if (t.namespace == "tag") {
                // Pretty-print plain tag filters ("tag" is the default type)
                tag.push(t.target);
            } else {
                switch (t.namespace) {
                    case "tag":
                    default:
                        tag.push("t:");
                        break;

                    case "category":
                        tag.push("c:");
                        break;

                    case "menu":
                        tag.push("m:");
                        break;

                    case "program":
                        tag.push("p:");
                        break;
                }

                tag.push(t.target);
            }

            tags.push(tag.join(""));
        }

        this.value = tags.join(" ");
        this.container.querySelector("input").value = this.value;
        this.valueChanged(fullRebuild);
    }

    explain()
    {
        if (this.value === null || this.value.trim().length == 0 || this.tags.length == 0) {
            // Provide a new tag button
            const template = getTemplate("puavoconfPuavomenuNew");

            template.querySelector("button").addEventListener("click", () => {
                this.tags.splice(0, 0, {
                    valid: true,
                    action: "show",
                    namespace: "tag",
                    target: "default"
                });

                this.save();
                this.explain();
            });

            this.details.innerText = "";
            this.details.appendChild(template);
            return;
        }

        // Build the table
        const table = getTemplate("puavoconfPuavomenuExplanation"),
              tbody = table.querySelector("tbody");

        for (let i = 0; i < this.tags.length; i++) {
            const tag = this.tags[i],
                  row = getTemplate("puavoconfPuavomenuExplanationRow"),
                  tr = row.querySelector("tr");

            const action = row.querySelector("#action"),
                  namespace = row.querySelector("#namespace"),
                  target = row.querySelector("#target");

            tr.dataset.index = i;

            if (!tag.valid)
                tr.classList.add("invalid");

            action.value = tag.action;
            namespace.value = tag.namespace;

            if (tag.target)
                target.value = tag.target;

            action.addEventListener("change", (e) => this.onChangeAction(e));
            namespace.addEventListener("change", (e) => this.onChangeNamespace(e));
            target.addEventListener("input", (e) => this.onChangeTarget(e));

            row.querySelector("button#add").addEventListener("click", (e) => this.onAddTag(e));
            row.querySelector("button#delete").addEventListener("click", (e) => this.onDeleteTag(e));
            row.querySelector("button#up").disabled = (this.tags.length > 0 && i == 0);
            row.querySelector("button#up").addEventListener("click", (e) => this.onMoveTagUp(e));
            row.querySelector("button#down").disabled = (this.tags.length > 0 && i == this.tags.length - 1);
            row.querySelector("button#down").addEventListener("click", (e) => this.onMoveTagDown(e));

            tbody.appendChild(row);
        }

        this.details.innerText = null;
        this.details.appendChild(table);
    }

    revalidateTag(index)
    {
        const rows = this.details.querySelectorAll("table tbody tr");

        this.tags[index].valid = this._isValidTag(this.tags[index]);

        if (this.tags[index].valid)
            rows[index].classList.remove("invalid");
        else rows[index].classList.add("invalid");
    }

    onChangeAction(e)
    {
        const index = this._getIndex(e.target);

        this.tags[index].action = e.target.value;
        this.revalidateTag(index);
        this.save();
    }

    onChangeNamespace(e)
    {
        const index = this._getIndex(e.target);

        this.tags[index].namespace = e.target.value;
        this.revalidateTag(index);
        this.save();
    }

    onChangeTarget(e)
    {
        const index = this._getIndex(e.target);

        this.tags[index].target = e.target.value;
        this.revalidateTag(index);
        this.save();
    }

    onAddTag(e)
    {
        this.tags.splice(this._getIndex(e.target) + 1, 0, {
            valid: true,
            action: "show",
            namespace: "tag",
            target: "default"
        });

        this.save(true);
        this.explain();
    }

    onDeleteTag(e)
    {
        this.tags.splice(this._getIndex(e.target), 1);
        this.save(true);
        this.explain();
    }

    onMoveTagUp(e)
    {
        const index = this._getIndex(e.target);

        if (index == 0 || this.tags.length == 1)
            return;

        const t = this.tags[index - 1];

        this.tags[index - 1] = this.tags[index];
        this.tags[index] = t;

        this.save();
        this.explain();
    }

    onMoveTagDown(e)
    {
        const index = this._getIndex(e.target);

        if (index == this.tags.length - 1 || this.tags.length == 1)
            return;

        const t = this.tags[index + 1];

        this.tags[index + 1] = this.tags[index];
        this.tags[index] = t;

        this.save();
        this.explain();
    }

    _getIndex(node)
    {
        return parseInt(node.parentNode.parentNode.dataset.index, 10);
    }

    _isValidTag(tag)
    {
        if (tag.action === null)
            return false;

        if (tag.namespace === null)
            return false;

        if (tag.target === null || tag.target.trim().length == 0)
            return false;

        // Highlight tags whose target contains unacceptable characters
        if (tag.target.match(/[^a-zA-Z0-9\-_\.]/))
            return false;

        return true;
    }
};
