$(document).ready(function() {
    $('.clone_prev_input_element').click(function() {
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
	$('a[href^=http]').click( function() {
	    window.open(this.href);
		return false;
	});
	if($("p.message_success")){
		var notice = $("p.message_success");
		notice.delay(3000).slideUp(500).fadeOut(200, function() {
			notice.remove();
		});		
	}
});

