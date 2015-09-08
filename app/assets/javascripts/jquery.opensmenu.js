/* global jQuery */
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

    function closeMenu() {
      subMenu.removeClass("open");
      subMenuButton.removeClass("touch-selected");
      menuOpen = false;
    }

    // If menu is open on a touch device, close it when user touches somewhere
    // else.
    $(document).bind("touchstart", function(e) {
      if (!menuOpen) return;

      // Allow touching of the link elements
      if (e && e.target.tagName === "A") return;
      closeMenu();
    });

    subMenuButton.bind("mouseleave", closeMenu);

    subMenuButton.bind("touchstart mouseenter", function() {
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

}(jQuery));
