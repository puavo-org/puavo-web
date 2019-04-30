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
//= require jquery2
//= require jquery_ujs
//= require jquery.liveSearch
//= require i18n

window.jQuery(document).ready(function($) {
  "use strict";

  $('.clone_prev_input_element').click(function(e) {
    e.preventDefault();
    var clone_element = $(this).prev().find('input:first').clone();
    clone_element.val('');
    $(this).prev().append( clone_element );
  });

  $('.clone_table_row_input_element').click(function(e) {
    e.preventDefault();
    var tbl = $(".mountPoints");
    var clone = tbl.find("tr:last").clone();
    clone.find("input").val("");
    tbl.children().append(clone);
  });

  $('.search').liveSearch({
    minLength: 2,
    url: window.SEARCH_URLS,
    duration: 400,
    typeDelay: 400,
    width: 'auto'
  });

  $('.user_search').liveSearch({
    minLength: 2,
    url: window.USER_SEARCH_URLS,
    duration: 400,
    typeDelay: 400,
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

});
