$(document).ready(function() {
    $('.edit').editable('user_validate', {
	submitdata : function(value, setting) {
	    return collect_submitdata($(this)) },
	callback : function(value, settings) {
	    current_element = $(this);
	    parent_element = current_element.parent().parent();
	    
	    result = jQuery.parseJSON(value);

	    parent_element.find('td').each(function(index, e) {
		if( ! $(e).hasClass('action') ) {
		    update_field_status(index, $(e), result);
		}
	    });

	    current_element.val( this.innerHTML = result[current_element.attr('id')]["value"] );
	    current_element.parent().find('input[type=hidden]').val(result[current_element.attr('id')]["value"]);
	    /*
            console.log(this);
            console.log(value);
            console.log(settings);
            */
	}
    });
    
    function update_field_status(index, td_element, result) {
	hidden_data = td_element.find('input[type=hidden]');
	error_span = td_element.find('span');
	label = td_element.find('div');
	if(result[index]["status"] == "true") {
	    error_span.html("");
	    if( label.hasClass("invalid") ) {
		label.removeClass("invalid");
	    }
	}
	if(result[index]["status"] == "false") {
	    error_span.html(result[index]["error"]);
	    if( !label.hasClass("invalid") ) {
		label.addClass("invalid");
	    } 
	}
    }

    function collect_submitdata(current_element) {
	var submitdata = {};
	// parent element contains one user's data
	parent_element = current_element.parent().parent();

	// Insert user's data to submitdata
	parent_element.find('input[type=hidden]').each(function(index, e) {
	    submitdata[e.name] = e.value;
	});

	submitdata["columns"] = new Array();
	$('input[name=columns[]]').each(function(e) {
	    submitdata["columns"][e] = this.value;
	});

	submitdata["uids_list"] = new Array();
	$('.uid').each(function(index, e){
	    if( parent_element.find('.uid').attr('id') !=  $(e).attr("id") ) {
		submitdata["uids_list"].push( $(e).val() );
	    }
	});

	return submitdata;
    }

    $('.destroy').click(function() {
	$(this).closest('tr').fadeOut('slow', function() {
	    $(this).remove();
	});
    });

    $('.user_row').mouseover(function() {
	$(this).closest('table').find('.destroy').hide();
	$(this).find('.destroy').show();
    });

    $('table.validate_users_list').mouseout(function() {
	$(this).closest('table').find('.destroy').hide();
    });
});
