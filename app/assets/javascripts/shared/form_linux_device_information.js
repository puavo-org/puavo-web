$(document).ready(function() {
	$('#autopoweroff input:radio').change( function() {
		if ( $(this).attr('value') != 'custom' ) {
			$(this).closest('table').find('select').each( function() {
				$(this).attr('value', '');
			});
		}
	});
});