// =============================================================================
// Extremely ugly password field validator

// Does not prevent the form from being submitted, but it lets the
// user know that the password will be rejected if they submit it
// =============================================================================

// Return one these from the validator function
const PASSWORD_OK = 0,
      PASSWORD_ASCII_ONLY = 1,      // for GSuite at the moment
      PASSWORD_NO_WHITESPACE = 2,   // for GSuite at the moment
      PASSWORD_TOO_SHORT = 3;

var passwordField = null,
    passwordFieldStatus = null,
    confirmField = null,
    confirmFieldStatus = null,
    validatorFunction = null,       // user-supplied function that validates the password fields
    minPasswordLength = -1,
    strings = {};                   // localized status messages, generated server-side and copied here

function validatePasswords(event)
{
  try {
    const password = passwordField.value,
          confirmation = confirmField.value;

    if (password.length == 0 && confirmation.length == 0) {
      // both fields are empty, nothing to validate
      passwordFieldStatus.innerHTML = "";
      confirmFieldStatus.innerHTML = "";
      return;
    }

    switch (validatorFunction(password)) {
      case PASSWORD_OK:
        passwordFieldStatus.innerHTML = strings["ok"];
        break;

      case PASSWORD_ASCII_ONLY:
        passwordFieldStatus.innerHTML = strings["ascii_only"];
        break;

      case PASSWORD_NO_WHITESPACE:
        passwordFieldStatus.innerHTML = strings["no_whitespace"];
        break;

      case PASSWORD_TOO_SHORT:
        if (minPasswordLength == -1)
          passwordFieldStatus.innerHTML = strings["too_short"];
        else passwordFieldStatus.innerHTML = strings["too_short_with_count"].replace("%{minlength}", minPasswordLength);

        break;

      default:
        passwordFieldStatus.innerHTML = "?";
        break;
    }

    if (password == confirmation)
      confirmFieldStatus.innerHTML = strings["passwords_match"];
    else confirmFieldStatus.innerHTML = strings["passwords_dont_match"];
  } catch (e) {
    // TODO: what now?
  }
}

function initPasswordValidator(passwordFieldID, confirmFieldID, validator, minLength, localizedStrings)
{
  try {
    console.log("initPasswordValidator(): passwordFieldID=\"" + passwordFieldID +
                "\", confirmFieldID=\"" + confirmFieldID +
                "\", minLength: " + minLength + "\n");

    passwordField = document.getElementById(passwordFieldID);
    confirmField = document.getElementById(confirmFieldID);
    validatorFunction = validator;
    minPasswordLength = minLength;
    strings = localizedStrings;

    passwordFieldStatus = document.createElement("div");
    confirmFieldStatus = document.createElement("div");

    passwordField.parentNode.appendChild(passwordFieldStatus);
    confirmField.parentNode.appendChild(confirmFieldStatus);

    passwordField.addEventListener("input", validatePasswords);
    confirmField.addEventListener("input", validatePasswords);

    console.log("initPasswordValidator(): done");
  } catch (e) {
    console.log("Password field validator initialization failed!\n");
    console.log(e)
  }
}
