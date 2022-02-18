// =============================================================================
// Extremely ugly password field validator, v2.2
// Does not prevent the form from being submitted, but it lets the
// user know that the password will be rejected if they submit it
// =============================================================================

// Returns an array of message IDs detailing why the password doesn't meet the requirements,
// or empty array if the password is valid.
function validatePassword(password, rules)
{
    let errors = [];

    // The rules have been validated server-side, so all error checking has been omitted
    for (const rule of rules) {
        let match = null;

        switch (rule.type) {
            case "length":
            {
                const length = (password === null || password === undefined) ? 0 : password.length;

                switch (rule.operator) {
                    case "=":
                        match = (length == rule.length);
                        break;

                    case "!=":
                        match = (length != rule.length);
                        break;

                    case "<":
                        match = (length < rule.length);
                        break;

                    case "<=":
                        match = (length <= rule.length);
                        break;

                    case ">":
                        match = (length > rule.length);
                        break;

                    case ">=":
                        match = (length >= rule.length);
                        break;
                }

                break;
            }

            case "regexp":
                match = (rule.regexp.exec(password) ? "=" : "!=") == rule.operator;
                break;

            case "complexity_check":
            {
                let matches = 0;

                for (const r of rule.regexps)
                    if (r.exec(password) !== null)
                        matches++;

                match = (matches >= rule.min_matches);
                break;
            }

            default:
                break;
        }

        if (!match)
            errors.push(rule.message);
    }

    return errors;
}

// UI element handles
let passwordField = null,
    passwordStatus = null,
    confirmField = null,
    confirmStatus = null,
    usernameFields = [];

// Optional function that is called whenever the input changes and the password is revalidated.
// It receives two parameters: one true/false that indicates if the password is okay, and
// another true/false that indicates if the password and the confirmation fields are identical.
// Because the validator is placed on the page through an ERB template, we can't pass a JavaScript
// function as a parameter, we can only pass its name.
let updateCallbackName = null;

function callCallback(ok, identical)
{
    if (updateCallbackName)
        window[updateCallbackName](ok, identical);
}

function findTD(e)
{
    while (e && e.tagName != "TD")
        e = e.parentNode;

    return e;
}

// There's no escape, I mean, unescape from Ruby's string escaping wrath. If you use t(),
// it *WILL* escape ' and " with HTML entities, period. No way around it. But JavaScript
// inserts the strings on the page as-is, so these escaped entities will not display
// correctly.
function unEsacapeHTML(s)
{
    return s.replaceAll("&#39;", "'")
            .replaceAll("&quot;", "\"");
}

function onPasswordInput()
{
    const password = passwordField.value,
          confirmation = confirmField.value;

    if (password.length == 0 && confirmation.length == 0) {
        passwordStatus.innerText = "";
        confirmStatus.innerText = "";
        callCallback(false, true);
        return;
    }

    // PASSWORD_RULES is defined in the inline <script> block on the page

    if (PASSWORD_RULES.length == 0) {
        // Only verify the password confirmation
        passwordStatus.innerText = "";
        confirmStatus.innerText = (confirmation == password) ? "" : unEsacapeHTML(CONFIRM_MISMATCH);
        callCallback(true, (confirmation == password));
        return;
    }

    let errors = validatePassword(password, PASSWORD_RULES);

    for (const e of usernameFields) {
        // If the password contains the first name, last name or username, flag it as an error
        const v = e.value.toLowerCase().trim();

        if (password.toLowerCase().indexOf(v) != -1) {
            errors.push(unEsacapeHTML(PASSWORD_CONTAINS_NAME));
            break;
        }
    }

    // Check for common passwords. Find full words, not substrings. The strings are tab-separated.
    if (new RegExp(`\t${password}\t`).exec(COMMON_PASSWORDS))
        errors.push(unEsacapeHTML(PASSWORD_IS_COMMON));

    passwordStatus.innerText = (errors.length == 0) ? "" : errors.map(e => unEsacapeHTML(e)).join("\n");
    confirmStatus.innerText = (confirmation == password) ? "" : unEsacapeHTML(CONFIRM_MISMATCH);

    callCallback(errors.length == 0, (confirmation == password));
}

function initializePasswordValidator(passwordFieldID, confirmFieldID, nameFields=null, callback=null)
{
    try {
        console.log(`Initializing the password validator, have ${PASSWORD_RULES.length} rule(s)`);

        if (PASSWORD_RULES.length == 0)
            console.log("Only checking the password confirmation");

        passwordField = document.getElementById(passwordFieldID);
        confirmField = document.getElementById(confirmFieldID);

        if (!passwordField) {
            console.error(`Could not find the password input field by ID "${passwordFieldID}"`);
            return;
        }

        if (!confirmField) {
            console.error(`Could not find the confirm input field by ID "${confirmFieldID}"`);
            return;
        }

        if (nameFields) {
            for (const id of nameFields) {
                const e = document.getElementById(id);

                if (e)
                    usernameFields.push(e);
            }
        }

        // Reuse the existing field error elements. Must find the actual TD element
        // because if the field is invalid, it's wrapped in a DIV, but not otherwise.
        passwordStatus = findTD(passwordField).querySelector("span.field_error");
        confirmStatus = findTD(confirmField).querySelector("span.field_error");

        // Except if the form is the publicly accessible password form, then the
        // field error spans don't exist and we must create them.
        if (!passwordStatus) {
            passwordStatus = document.createElement("span");
            passwordStatus.classList.add("field_error");
            findTD(passwordField).appendChild(passwordStatus);
        }

        if (!confirmStatus) {
            confirmStatus = document.createElement("span");
            confirmStatus.classList.add("field_error");
            findTD(confirmField).appendChild(confirmStatus);
        }

        updateCallbackName = callback;

        passwordField.addEventListener("input", () => onPasswordInput());
        confirmField.addEventListener("input", () => onPasswordInput());
    } catch (e) {
        console.error("Password field validator initialization failed!");
        console.error(e)
    }
}
