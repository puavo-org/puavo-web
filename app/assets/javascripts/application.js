(function($){

  $.support.touch = "ontouchstart" in window;

  /*
   * Submenu jQuery plugin.
   *
   * Usage: $(button selector).opensMenu(menu selector);
   *
   * */
  $.fn.opensMenu = function(menuSelector) {
    var subMenuButton = this;
    var subMenu = $(menuSelector);

    var menuOpen = false;
    var menuClickBlock = false;

    // Do not allow menu item clicking immediately after menu opening.
    // Prevents unwanted navigation to the first item.
    subMenu.find("a:first").bind("click", function(e) {
      if (menuClickBlock) {
        e.preventDefault();
      }
    });

    // If menu is open on a touch device, close it when user touches somewhere
    // else.
    $(document).bind("touchstart", function(e) {
      if (!menuOpen) return;

      // Allow touching of the link elements
      if (e && e.target.tagName === "A") return;

      subMenu.removeClass("open");
      subMenuButton.removeClass("touch-selected");
      menuOpen = false;

    });

    subMenuButton.bind("touchstart", function() {
      // This will get fired also when menu item is clicked, because the items
      // are children of the main button. So we have to bail out if menu is
      // open.
      if (menuOpen) return;


      menuClickBlock = true;

      // CSS Class opens the menu
      subMenu.addClass("open");

      // So that we can style touch
      subMenuButton.addClass("touch-selected");

      // Use small timeout so that close event won't fire at same time.
      setTimeout(function() {

        // Remove menu item block
        menuClickBlock = false;

        menuOpen = true;
      }, 500);

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


  });

}(jQuery));
