(function() {

    function toAscii(str) {
        return str
            .replace(/ä/g, "a")
            .replace(/ö/g, "ö")
            .replace(/å/g, "a")
            ;
    }

    var input = document.getElementById("username");

    input.addEventListener("blur", function(e) {
        input.value = toAscii(input.value.toLowerCase());

        var domain = input.value.split("@")[1];

        // append topdomain if non is set
        if (domain && !domain.match(/\./)) {
            input.value = input.value + "." + TOP_DOMAIN;
        }

    });

}());
