// for My School Users list Javascript

const OPEN_ARROW = "▼",
      CLOSED_ARROW = "▶";

function toggleGroup(e)
{
    const id = e.target.dataset.target;

    let tbl = document.getElementById("table-" + id),
        arr = document.getElementById("arrow-" + id);

    if (tbl.style.display == "none" || tbl.style.display == "") {
        tbl.style.display = "block";
        arr.innerHTML = OPEN_ARROW;
    } else {
        tbl.style.display = "none";
        arr.innerHTML = CLOSED_ARROW;
    }
}

function setupGroupHeaders()
{
    for (let h of document.getElementsByClassName("groupHeader"))
        if (h.dataset.target)
            h.onclick = toggleGroup;
}

function doSearch(e)
{
    const text = document.getElementById("searchBox").value.toLowerCase();

    let resultsDiv = document.getElementById("searchResults"),
        numMatches = document.getElementById("numMatches"),
        groupsDiv = document.getElementById("groupsList");

    // Search by (first name, last name)
    const rawParts = text.split(" ");
    let parts = [];

    for (let i = 0; i < rawParts.length; i++) {
        const trimmed = rawParts[i].trim().toLowerCase();

        if (trimmed.length > 0)
            parts.push(trimmed);
    }

    if (text.length == 0 || parts.length == 0) {
        // No text -> reset
        if (resultsDiv.firstChild)
            resultsDiv.removeChild(resultsDiv.firstChild);

        numMatches.style.display = "none";
        groupsDiv.style.display = "block";

        return true;
    }

    console.log("Searching for: " + parts);
    const t0 = performance.now();

    let resultsTable = document.getElementById("searchResultsTableTemplate").cloneNode(true);

    resultsTable.removeAttribute("id");

    const groups = document.getElementsByClassName("groupHeader");
    let numFound = 0;

    for (let i = 0; i < groups.length; i++) {
        const id = groups[i].dataset.target;
        const count = parseInt(groups[i].dataset.count, 10);
        const name = groups[i].dataset.name;
        const isUngrouped = groups[i].dataset.ungrouped === '1';

        for (let j = 0; j < count; j++) {
            const row = document.getElementById(`row-${id}-${j}`);

            const first = row.children[1].textContent.toLowerCase(),
                  last = row.children[0].textContent.toLowerCase();

            let match = false;

            if (parts.length == 1) {
                if (first.startsWith(parts[0]) || last.startsWith(parts[0]))
                    match = true;
            } else {
                if ((first.startsWith(parts[0]) && last.startsWith(parts[1])) ||
                    (last.startsWith(parts[0]) && first.startsWith(parts[1])))
                    match = true;
            }

            if (!match)
                continue;

            let rowCopy = row.cloneNode(true);

            // remove the ID so we don't search the previous search results
            rowCopy.removeAttribute("id");

            // insert the group name
            let td = document.createElement("td");

            if (!isUngrouped) {
                // ungrouped users have no group name
                td.appendChild(document.createTextNode(name));
            }

            rowCopy.insertBefore(td, rowCopy.children[0]);

            resultsTable.appendChild(rowCopy);
            numFound++;
        }
    }

    if (resultsDiv.firstChild)
    resultsDiv.removeChild(resultsDiv.firstChild);

    if (numFound) {
        numMatches.innerHTML = numFound + " " + ((numFound == 1) ?
            STRINGS["one_match"] : STRINGS["multiple_matches"]);

        resultsTable.style.display = "table";
        resultsDiv.appendChild(resultsTable);
    } else {
        numMatches.innerHTML = STRINGS["no_matches"];
        resultsTable = null;
    }

    groupsDiv.style.display = "none";
    numMatches.style.display = "block";

    const t1 = performance.now();
    console.log(`Search took ${t1 - t0} ms`);

    return true;
}

function cancelSearch(e)
{
    if (e.keyCode == 27) {
        document.getElementById("searchBox").value = "";
        doSearch(null);     // force empty search to clear any results
    }
}

function setupPage()
{
    setupGroupHeaders();
    document.getElementById("searchBox").oninput = doSearch;
    document.getElementById("searchBox").onkeydown = cancelSearch;
}
