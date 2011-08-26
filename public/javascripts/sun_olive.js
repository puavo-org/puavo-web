$(document).ready(function() {
  function topMenuHandler(n,c) {
    n ? c.css("margin-top",50) : c.css("margin-top",25);
    n ? $("#top-menu-right").css("float","left") : $("#top-menu-right").css("float","right");
  };
  var container = $(".container");
  var topNavContainer = $(".topNavContainer");
  var narrowcontainer = (topNavContainer.height()>=36) ? true : false;
  topMenuHandler(narrowcontainer, container);

  	$(window).resize(function() {
    narrowcontainer = (topNavContainer.height()>=36) ? true : false;
    topMenuHandler(narrowcontainer, container);
  });
});
