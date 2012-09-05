$(document).ready(function() {
    $('#device_submit').hide();
    
    $('#device_type').change( function() {
	$('#new_device').submit();
    });

    $('#device_type').val('');
});