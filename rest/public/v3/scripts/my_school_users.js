// for My School Users list Javascript

const OPEN_ARROW = "▼",
      CLOSED_ARROW = "▶";

function toggleGroup(e)
{
  const id = e.target.dataset.target;

  var tbl = document.getElementById("table-" + id),
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
  var links = document.getElementsByClassName("groupHeader");

  for (var i = 0; i < links.length; i++)
    if (links[i].dataset.target)
      links[i].onclick = toggleGroup;
}

function doSearch(e)
{
  var resultsDiv = document.getElementById("searchResults"),
      numMatches = document.getElementById("numMatches"),
      groupsDiv = document.getElementById("groupsList");

  const text = document.getElementById("searchBox").value.toLowerCase();

  // search by (first name, last name)
  const rawParts = text.split(" ");
  var parts = new Array();

  for (var i = 0; i < rawParts.length; i++) {
    const trimmed = rawParts[i].trim().toLowerCase();

    if (trimmed.length > 0)
      parts.push(trimmed);
  }

  if (text.length == 0 || parts.length == 0) {
    // no text, reset
    if (resultsDiv.firstChild)
      resultsDiv.removeChild(resultsDiv.firstChild);

    numMatches.style.display = "none";
    groupsDiv.style.display = "block";

    return true;
  }

  console.log("Searching for: " + parts);
  const t0 = performance.now();

  var resultsTable = document.getElementById("searchResultsTableTemplate").cloneNode(true);

  resultsTable.removeAttribute("id");

  const groups = document.getElementsByClassName("groupHeader");
  var numFound = 0;

  for (var i = 0; i < groups.length; i++) {
    const id = groups[i].dataset.target;
    const count = parseInt(groups[i].dataset.count, 10);
    const name = groups[i].dataset.name;
    const isUngrouped = groups[i].dataset.ungrouped === '1';

    for (var j = 0; j < count; j++) {
      const row = document.getElementById("row-" + id + "-" + j);
      const first = row.children[1].textContent.toLowerCase(),
            last = row.children[0].textContent.toLowerCase();
      var match = false;

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

      var rowCopy = row.cloneNode(true);

      // remove the ID so we don't search the previous search results
      rowCopy.removeAttribute("id");

      // insert the group name
      var td = document.createElement("td");

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
                           STRINGS["one_match"] :
                           STRINGS["multiple_matches"]);
    resultsTable.style.display = "table";
    resultsDiv.appendChild(resultsTable);
  } else {
    numMatches.innerHTML = STRINGS["no_matches"];
    resultsTable = null;
  }

  groupsDiv.style.display = "none";
  numMatches.style.display = "block";

  const t1 = performance.now();
  console.log("Search took " + (t1 - t0) + " ms");

  return true;
}

function cancelSearch(e)
{
  if (e.keyCode == 27) {
    document.getElementById("searchBox").value = "";
    doSearch(null);
  }
}

function setupPage()
{
  setupGroupHeaders();
  document.getElementById("searchBox").oninput = doSearch;
  document.getElementById("searchBox").onkeydown = cancelSearch;
}
