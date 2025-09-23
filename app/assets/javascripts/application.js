/* global jQuery */
// This is a manifest file that'll be compiled into application.js, which will include all the files
// listed below.
//
// Any JavaScript/Coffee file within this directory, lib/assets/javascripts, vendor/assets/javascript
// or vendor/assets/javascripts of plugins, if any, can be referenced here using a relative path.
//
// It's not advisable to add code directly here, but if you do, it'll appear at the bottom of the
// the compiled file.
//
// WARNING: THE FIRST BLANK LINE MARKS THE END OF WHAT'S TO BE PROCESSED, ANY BLANK LINE SHOULD
// GO AFTER THE REQUIRES BELOW.
//
//= require jquery3
//= require jquery_ujs
//= require jquery.liveSearch
//= require i18n

// Finds all abbr elements with "timestamp" class, and converts them to localized localtime strings
function localizeTimestamps()
{
    const intlDataset = document.documentElement.dataset;

    const dateFormatter = Intl.DateTimeFormat(intlDataset.intlLocale, {
        weekday: "short",
        year: "numeric",
        month: "numeric",
        day: "numeric",
        timeZone: intlDataset.intlTimezone
    });

    const fullFormatter = Intl.DateTimeFormat(intlDataset.intlLocale, {
        weekday: "short",
        year: "numeric",
        month: "numeric",
        day: "numeric",
        hour: "numeric",
        minute: "numeric",
        second: "numeric",
        hour12: false,
        timeZone: intlDataset.intlTimezone
    });

    for (const e of document.querySelectorAll("div#pageContainer abbr.timestamp")) {
        e.innerText = e.classList.contains("dateonly") ?
            dateFormatter.format(new Date(`${e.textContent} 12:00:00Z`)) :
            fullFormatter.format(new Date(e.textContent));
    }
}

window.jQuery(document).ready(function($) {
  "use strict";

  $('.clone_prev_input_element').click(function(e) {
    e.preventDefault();
    var clone_element = $(this).prev().find('input:first').clone();
    clone_element.val('');
    clone_element.attr('readonly', false);
    $(this).prev().append( clone_element );
  });

  $('.clone_table_row_input_element').click(function(e) {
    e.preventDefault();
    var tbl = $(".mountPoints");
    var clone = tbl.find("tr:last").clone();
    clone.find("input").val("");
    tbl.children().append(clone);
  });

  // Setup top bar quick search. This exists on all pages.
  $('.quickSearch').liveSearch({
    id: "quickSearchResults",     // unique ID for the results box
    url: "/quick_search?query=",  // search URL
    field: "quickSearch",         // search term source
    typeDelay: 400,
    minLength: 2,
    width: 'auto'
  });

  $('#autopoweroff input:radio').change( function() {
    if ( $(this).attr('value') != 'custom' ) {
      $(this).closest('table').find('select').each( function() {
        $(this).val('');
      });
    }
  });


  // Prevent multi submits from any form.  All submit buttons have name=commit
  //
  // input[name=commit][type=submit] will match all standard rails forms and
  // also the "once" class can be used for any other element
  $("input[name=commit][type=submit], .once").on("click", function(e) {
    // Set disabled on the next tick so that the form get submitted the one
    // time
    setTimeout(function() {
      e.target.disabled = true;
    }, 0);
  });

  localizeTimestamps();
});
