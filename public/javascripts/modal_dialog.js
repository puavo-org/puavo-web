/* Modal in-page popup dialogs. Only one of the can be active at a time. */

/*
  You MUST derive a class from this if you actually want to display dialogs! This base
  class doesn't do much on its own.
*/
class ModalDialogBase {
    constructor()
    {
        // backdrop (darkens the screen and covers it)
        this.backdrop = document.createElement("div");
        this.backdrop.id = "modalDialogBackdrop";

        // outer wrapper (specifies the size)
        this.modalDialogContainer = document.createElement("div");
        this.modalDialogContainer.id = "modalDialogContainer";

        // container (main layout)
        this.modalDialog = document.createElement("div");
        this.modalDialog.classList.add("modalDialog");

        // title
        this.title = document.createElement("div");
        this.title.className = "title";

        // dialog body (where the contents are)
        this.body = document.createElement("div");
        this.body.className = "body";

        // button row and the buttons in it
        this.buttons = document.createElement("div");
        this.buttons.className = "buttons";

        // assemble the pieces
        this.modalDialog.appendChild(this.title);
        this.modalDialog.appendChild(this.body);
        this.modalDialog.appendChild(this.buttons);
        this.modalDialogContainer.appendChild(this.modalDialog);
        this.backdrop.appendChild(this.modalDialogContainer);
    }

    // Set the window title and optionally the subtitle
    setTitle(title, subTitle)
    {
        if (subTitle)
            this.title.innerHTML = "<span>" + title + "</span><br><small>" + subTitle + "</small>";
        else this.title.innerHTML = "<span>" + title + "</span>";
    }

    // Creates a new button element
    createButton(title, clazz, id, callback)
    {
        var button = document.createElement("a");

        button.classList.add("button");

        if (id)
            button.id = id;

        if (clazz)
            button.classList.add(clazz);

        button.innerHTML = title;

        button.addEventListener("click", event => callback(this));

        return button;
    }

    // A generic callback dispatcher
    clickedButton(callback)
    {
        callback();
        this.close();
    }

    close()
    {
        document.getElementById("modalDialogBackdrop").remove();
    }
};

/*
class YesNoQuestion extends ModalDialogBase {
    constructor(title, subTitle, question, yesCallback, noCallback)
    {
        super();

        this.setTitle(title, subTitle);

        this.body.appendChild(document.createTextNode(question));

        this.buttons.appendChild(this.createButton("Kyllä", "button-good", "ok", "yn-yes", event => this.clickedButton(yesCallback)));
        this.buttons.appendChild(this.createButton("Ei", "button-danger", "cancel", "yn-no", event => this.clickedButton(noCallback)));
    }
};
*/
