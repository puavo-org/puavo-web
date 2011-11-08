/***
@title:
Live Search

@version:
2.0

@author:
Andreas Lagerkvist

@date:
2008-08-31

@url:
http://andreaslagerkvist.com/jquery/live-search/

@license:
http://creativecommons.org/licenses/by/3.0/

@copyright:
2008 Andreas Lagerkvist (andreaslagerkvist.com)

@requires:
jquery, jquery.liveSearch.css

@does:
Use this plug-in to turn a normal form-input in to a live ajax search widget. The plug-in displays any HTML you like in the results and the search-results are updated live as the user types.

@howto:
jQuery('#q').liveSearch({url: '/ajax/search.php?q='}); would add the live-search container next to the input#q element and fill it with the contents of /ajax/search.php?q=THE-INPUTS-VALUE onkeyup of the input.

@exampleHTML:
<form method="post" action="/search/">

	<p>
		<label>
			Enter search terms<br />
			<input type="text" name="q" />
		</label> <input type="submit" value="Go" />
	</p>

</form>

@exampleJS:
jQuery('#jquery-live-search-example input[name="q"]').liveSearch({url: Router.urlForModule('SearchResults') + '&q='});
***/
jQuery.fn.liveSearch = function (conf) {
	var config = jQuery.extend({
		url:			{'jquery-live-search-result': 'search-results.php?q='},
		id:				'jquery-live-search', 
		duration:		400, 
		typeDelay:		200,
		loadingClass:	'loading', 
		onSlideUp:		function () {}, 
		uptadePosition:	false,
		minLength:		0,
		width:			null
	}, conf);

	if (typeof(config.url) == "string") {
		config.url = { 'jquery-live-search-result': config.url }
	} else if (typeof(config.url) == "object") {
		if (typeof(config.url.length) == "number") {
			var urls = {}
			for (var i = 0; i < config.url.length; i++) {
				urls['jquery-live-search-result-' + i] = config.url[i];
			}
			config.url = urls;
		}
	}
	var searchStatus = {};
	var liveSearch	= jQuery('#' + config.id);
	var loadingRequestCounter = 0;

	// Create live-search if it doesn't exist
	if (!liveSearch.length) {
		liveSearch = jQuery('<div id="' + config.id + '"></div>')
						.appendTo(document.body)
						.hide()
						.slideUp(0);

		for (key in config.url) {
			liveSearch.append('<div id="' + key + '"></div>');
			searchStatus[key] = false;
		}

		// Close live-search when clicking outside it
		jQuery(document.body).click(function(event) {
			var clicked = jQuery(event.target);

			if (!(clicked.is('#' + config.id) || clicked.parents('#' + config.id).length || clicked.is('input'))) {
				liveSearch.slideUp(config.duration, function () {
					config.onSlideUp();
				});
			}
		});
	}

	return this.each(function () {
		var input							= jQuery(this).attr('autocomplete', 'off');
		var liveSearchPaddingBorderHoriz	= parseInt(liveSearch.css('paddingLeft'), 10) + parseInt(liveSearch.css('paddingRight'), 10) + parseInt(liveSearch.css('borderLeftWidth'), 10) + parseInt(liveSearch.css('borderRightWidth'), 10);
    var doWeHaveAnyResults = false;
		// Re calculates live search's position
		var repositionLiveSearch = function () {
			var tmpOffset	= input.offset();
			var tmpWidth = input.outerWidth();
			if (config.width != null) {
				tmpWidth = config.width;
			}
			var inputDim	= {
				left:		tmpOffset.left, 
				top:		tmpOffset.top, 
				width:		tmpWidth, 
				height:		input.outerHeight()
			};

			inputDim.topPos		= inputDim.top + inputDim.height;
			inputDim.totalWidth	= inputDim.width - liveSearchPaddingBorderHoriz;
			liveSearch.css({
				position:	'absolute', 
				left:		inputDim.left + 'px', 
				top:		inputDim.topPos + 'px',
				width:		inputDim.totalWidth + 'px'
			});
		};
		var showOrHideLiveSearch = function () {
		  if(doWeHaveAnyResults) input.css("color","#000000");
		  else if(loadingRequestCounter==0 && !doWeHaveAnyResults) input.css("color","#FF0000");
			if (loadingRequestCounter == 0) {
				showStatus = false;
				for (key in config.url) {
					if( searchStatus[key] == true ) {
						showStatus = true;
						break;
					}
				}

				if (showStatus == true) {
					for (key in config.url) {
						if( searchStatus[key] == false ) {
							liveSearch.find('#' + key).html('');
						}
					}
					showLiveSearch();
				} else {
					hideLiveSearch();
				}
			}
		};

		// Shows live-search for this input
		var showLiveSearch = function () {
		  if(input.hasClass('loading')){input.removeClass('loading')};
			// Always reposition the live-search every time it is shown
			// in case user has resized browser-window or zoomed in or whatever
			repositionLiveSearch();

			// We need to bind a resize-event every time live search is shown
			// so it resizes based on the correct input element
			$(window).unbind('resize', repositionLiveSearch);
			$(window).bind('resize', repositionLiveSearch);
			liveSearch.slideDown(config.duration)
		};

		// Hides live-search for this input
		var hideLiveSearch = function () {
		  if(input.hasClass('loading')){input.removeClass('loading')};
			liveSearch.slideUp(config.duration, function () {
				config.onSlideUp();
				for (key in config.url) {
					liveSearch.find('#' + key).html('');
				}
			});
		};

		input
			// On focus, if the live-search is empty, perform an new search
			// If not, just slide it down. Only do this if there's something in the input
			.focus(function () {
				if (this.value.length > config.minLength ) {
					showOrHideLiveSearch();
				}
			})
			.keypress(function () {if(this.value.length<=1) input.css("color","#000000");})
			// Auto update live-search onkeyup
			.keyup(function () {
				// Don't update live-search if it's got the same value as last time
				if (this.value != this.lastValue) {
					input.addClass(config.loadingClass);

					var q = this.value;

					// Stop previous ajax-request
					if (this.timer) {
						clearTimeout(this.timer);
						doWeHaveAnyResults=false;
					}

					if( q.length > config.minLength ) {
						// Start a new ajax-request in X ms
						this.timer = setTimeout(function () {
							for (url_key in config.url) {
								loadingRequestCounter += 1;
								jQuery.ajax({
									key: url_key,
									url: config.url[url_key] + q,
									success: function(data){
										if (data.length) {
										  doWeHaveAnyResults=true;
    										searchStatus[this.key] = true;
											liveSearch.find("#" + this.key).html(data);
										} else {
											searchStatus[this.key] = false;
										}
										loadingRequestCounter -= 1;
										showOrHideLiveSearch();
									}
								});
							}
						}, config.typeDelay);
					}
					else {
						for (url_key in config.url) {
							searchStatus[url_key] = false;
						}
						hideLiveSearch();
					}

					this.lastValue = this.value;
				}
			});
	});
};
