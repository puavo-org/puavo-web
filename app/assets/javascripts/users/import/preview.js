$(document).ready(function() {
    $('.edit.select').editable('user_validate', {
		loadurl : 'options',
		loaddata : function(value, settings) {
			return {column: $(this).closest('td').find('input[type=hidden]').attr('class')};
		},
		type       : 'select',
		submit     : 'OK',
		onblur: 'submit',
		submitdata : function(value, setting) {
			return collect_submitdata($(this)) },
		callback : function(value, settings) {
			update_after_validation($(this), value);
		},
    });

    $('.edit.text').editable( 'user_validate', {
		onblur: 'submit',
		submitdata : function(value, setting) {
			return collect_submitdata($(this)) },
		callback : function(value, settings) {
			update_after_validation($(this), value);
		},
    });
    

    $('.edit').mouseover(function() {
		td_element = $(this).closest('td')
		if( td_element.find('input[type=text]').length == 0 && td_element.find('select').length == 0 ) {
			$(this).addClass('edit_hoover');
		}
    }).mouseout(function() {
		$(this).removeClass('edit_hoover');
    }).click(function() {
		$(this).removeClass('edit_hoover');
    });


    function update_after_validation(current_element, validation_results_json) {
		var current_index = null;
		parent_tr_element = current_element.closest('tr');
		current_td_element = current_element.closest('td');
		current_hidden_element = current_td_element.find('input[type=hidden]');
		validation_results = jQuery.parseJSON(validation_results_json);
		parent_tr_element.find('td').each(function(index, td_element) {
			if( ! $(td_element).hasClass('action') ) {
				set_or_remove_error_message(index, $(td_element), validation_results)
				if( $(td_element).find('input[type=hidden]').attr('id') == current_hidden_element.attr('id') ) {
					current_index = index;
				}
			}
		});

		current_element.html( validation_results[current_index]["value"] );
		current_hidden_element.val( validation_results[current_index]["value"] );
    }

    function set_or_remove_error_message(index, td_element, validation_validation_results) {
		hidden_data = td_element.find('input[type=hidden]');
		label = td_element.find('div');
		if(validation_results[index]["status"] == "true") {
			label.attr('title', "");
			if( label.hasClass("invalid") ) {
				label.removeClass("invalid");
			}
		}
		if(validation_results[index]["status"] == "false") {
			label.attr('title', validation_results[index]["error"]);
			if( !label.hasClass("invalid") ) {
				label.addClass("invalid");
			} 
		}
    }

    function collect_submitdata(current_element) {
		var submitdata = {};
		// parent element contains one user's data
		parent_element = current_element.parent().parent();
		hidden_element = current_element.parent().find('input[type=hidden]')

		// Insert user's data to submitdata
		parent_element.find('input[type=hidden]').each(function(index, e) {
			submitdata[e.name] = e.value;
		});

		submitdata["columns"] = new Array();
		$('input[name*="columns"]').each(function(e) {
			submitdata["columns"][e] = this.value;
		});

		submitdata["column"] = hidden_element.attr('class');

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

	$('#select_change_school_users').click(function() {
		$('input[type=checkbox]').each(function() {
			// Toggle
			$(this).attr('checked', !$(this).attr('checked'));
		});
	});

	if( $('input[type=checkbox]').length < 1 ) {
		$('#select_change_school_users').parent().hide();
	}
});
