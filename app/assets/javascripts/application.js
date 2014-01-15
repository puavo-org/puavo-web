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
//= require jquery
//= require jquery_ujs
//= require jquery.opensmenu
//= require jquery.jeditable
//= require jquery.liveSearch
//= require jquery.textarea
//= require users/import/new
//= require users/import/preview


window.jQuery(document).ready(function($) {
  "use strict";
  var activate_advanced = $('.printer-permissions input[value=advanced]')[0];

  function showAdvancedSettings(e) {
    var groups = $('.printer-permissions .groups');
    var devices = $('.printer-permissions .devices');
    if(e.checked) {
      groups.show();
      devices.show();
    } else {
      groups.hide();
      devices.hide();
    }
  }

  if(activate_advanced) {
    showAdvancedSettings(activate_advanced);
  }

  $('input[name="activate"]').click(function() {
    showAdvancedSettings(activate_advanced);
  });

  $('.clone_prev_input_element').click(function(e) {
    e.preventDefault();
    var clone_element = $(this).prev().find('input:first').clone();
    clone_element.val('');
    $(this).prev().append( clone_element );
  });

  $('.clone_table_row_input_element').click(function(e) {
    e.preventDefault();
    var this_table = $(this).parents('table').prev();
    var clone_element = this_table.find('tr:last').clone();
    clone_element.find('input').val('');
    this_table.children().append(clone_element);
  });

  $('.search').liveSearch({
    minLength: 2,
    url: window.SEARCH_URLS,
    duration: 400,
    typeDelay: 400,
    width: 'auto'
  });

  // Open external links always in a new tab
  $('a[href^=http]').click(function() {
    window.open(this.href);
    return false;
  });


  if ($.support.touch) {

    // Override mouse CSS so that it won't interfier.
    $("style#menuHandling").text($.fn.opensMenu.css);

    $(".organisation-menu-button").opensMenu(".organisation-menu");
    $(".school-menu-button").opensMenu(".school-menu");

    $(".tool").opensMenu(".tools .tool ul");

  }

  $('#autopoweroff input:radio').change( function() {
    if ( $(this).attr('value') != 'custom' ) {
      $(this).closest('table').find('select').each( function() {
        $(this).val('');
      });
    }
  });


  // Prevent multi submits from any form.  All submit buttons have name=commit
  $("input[name=commit][type=submit]").on("click", function(e) {
    // Set disabled on the next tick so that the form get submitted the one
    // time
    setTimeout(function() {
      e.target.disabled = true;
    }, 0);
  });


});



