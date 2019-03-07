/* Used on devices index page to hide the form submit button
   and make the the combo box submit instantly when something
   is selected. */

$(document).ready(function(){
    $('#device_submit').hide();

    $('#device_type').change( function() {
        $('#new_device').submit();
    });

    $('#device_type').val('');
});
