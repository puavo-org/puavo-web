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


jQuery(document).ready(function($) {

  $('.clone_prev_input_element').click(function(e) {
    e.preventDefault();
    var clone_element = $(this).prev().find('input:first').clone();
    clone_element.val('');
    $(this).prev().append( clone_element );
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
});

