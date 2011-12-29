(function($){

  $.support.touch = "ontouchstart" in window;

  /*
   * Submenu jQuery plugin.
   *
   * Usage: $( button selector ).opensMenu(menu selector);
   *
   * */
  $.fn.opensMenu = function(menuSelector) {
    var subMenuButton = this;
    var subMenu = $(menuSelector);

    var open = false;

    // For touch devices
    $(document).bind("touchstart", function(e) {
      // Allow touching of the link elements
      if (e && e.target.tagName === "A") return;
      if (open) {
        subMenu.removeClass("open");
        open = false;
      }
    });

    subMenuButton.bind("touchstart", function() {
      subMenu.addClass("open");

      // Use small timeout so that close event won't fire at same time.
      if (!open) {
        setTimeout(function() {
          open = true;
        }, 500);
      }

    });

    return this;
  };

  $.fn.opensMenu.css = ".open { display: block !important; }";


  $(document).ready(function() {

    $('.clone_prev_input_element').click(function(e) {
      e.preventDefault();
      clone_element = $(this).prev().find('input:first').clone()
      clone_element.val('');
      $(this).prev().append( clone_element );
    });

    $('#search').liveSearch({
      minLength: 2,
      url: search_urls,
      duration: 400,
      typeDelay: 400,
      width: 'auto'
    });

    // Open external links always in new page
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


  });

}(jQuery));
