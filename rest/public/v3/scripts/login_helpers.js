(function() {
    var input = document.getElementById("username");

    input.addEventListener("blur", function(e) {
        var domain = input.value.split("@")[1];

        // append topdomain if non is set
        if (domain && !domain.match(/\./)) {
            input.value = input.value + "." + TOP_DOMAIN;
        }
    });
}());
