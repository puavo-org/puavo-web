$(document).ready(function() {
    $('.clone_prev_input_element').click(function() {
	clone_element = $(this).prev().find('input:first').clone()
	clone_element.val('');
	$(this).prev().append( clone_element );
    });

    $('#search').liveSearch({
	minLength: 2,
	url: '/users/search?words='
    });
});