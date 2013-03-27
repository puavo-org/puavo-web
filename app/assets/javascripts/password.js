$(document).ready(function() {
	if($("p.message_success").length > 0 || $("p.message_notice").length > 0){
		var notice = $("p[class^='message_']");
		notice.delay(3000).slideUp(500).fadeOut(200, function() {
			notice.remove();
		});		
	}
});
