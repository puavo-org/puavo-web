/** 
 * @description		prototype.js based hover menu
 * @author        	Peter Slagter; peter [at] procurios [dot] nl; http://twitter.com/pesla or http://techblog.procurios.nl/k/618/news/view/34556/14863/ProtoFish-advanced-hover-menu-based-on-Prototype.html
 * @license			ProtoFish is based on the MIT license (http://protofish.procurios.nl/protofish-license).
 * 					If you want to remove this copyright notice, contact me for a crate of beer, and we'll see whats possible ;)
 * @parameters		id: menu id <string>, timeout: amount of milliseconds delay on mouseout <string>, cssClass: hover class <string>
 * 					remActive: whether or not remove active class when user enters menu <boolean>, ARIA: choose to use ARIA roles and states <boolean>
 * 					useShortKey: whether or not to use a shortkey to focus menu <boolean> 
 * 
*/

var ProtoFish = Class.create({

	'initialize': function(id, timeout, cssClass, remActive, ARIA, useShortKey) {
		
		// Store function parameters
		this.id = id;
		this.timeout = timeout || '400';
		this.cssClass = cssClass || 'hover';
		this.remActive = remActive || false;
		this.ARIA = ARIA || false;
		this.useShortKey = useShortKey || false;
		
		// Initialize timeout queue & activeTimeout variable
		this.queue = [];
		this.activeTimeout = '';
		this.menuFocus = false;
		this.menuCount = 0;
		this.isParent = false;
		
		// Store keys
		this.shiftDown = false;
		this.mDown = false;
		this.ctrlDown = false;
		this.altDown = false;

		// Get relevant DOM elements and store them
		if ($(id) && $(id).down()) {
			if (this.ARIA != false) {
				$(id).writeAttribute('role', 'menubar');
				this.menuContainers = $(id).select('ul');
				this.menuContainers.each( function(elem, i) {
					elem.writeAttribute('role', 'menu');
				});
			}
			this.listItems = $(id).select('li');
			this.activeItems = $(id).select('li.active');

			// Set tabindex of first menuitem
			this.listItems[0].down('a').setAttribute('tabindex','0');
			
			// Start observing my menu!
			this.initObservers();
		}
	},
	
	'initObservers': function() {
		this.listItems.each( function(elem) {
	
			// Mouseover and mouseout handlers for regular mouse based navigation
			elem.observe('mouseover', function(event, element){
				this.enterMenu(element);
				element.addClassName(this.cssClass);
			}.bindAsEventListener(this, elem));
			elem.observe('mouseout', function(event, element) {
				this.queue.push([this.leaveMenu.delay(this.timeout/1000, this), element]);
			}.bindAsEventListener(this, elem));
			
			
			if (this.ARIA != false) {
				elem.down('a').writeAttribute('role', 'menuitem');
			
				if (elem.down('ul')) {
					elem.down('a').writeAttribute('aria-haspopup', 'true');
				}
			}
			
		}.bind(this));
		
		Event.observe(document, 'keydown', function(event) {			
			var code = event.keyCode;
			var allowedCodes = [9,13,27,32,37,38,39,40];
			
			if (allowedCodes.indexOf(code) != -1) {
				this.keyBoardNav(event, code, allowedCodes);
			}
			
			if (event.keyCode == 16) {
				this.shiftDown = true;
			} else if (this.useShortKey != false) {
				if (event.keyCode == 77) {
					this.mDown = true;
				}
				if (event.keyCode == 17) {
					this.ctrlDown = true;
				}
				if (event.keyCode == 18) {
					this.altDown = true;
				}
				
				if (this.mDown == true && this.ctrlDown == true && this.altDown == true) {
					this.listItems[0].down('a').focus();
				}
			}
			
			
		}.bind(this));

		Event.observe(document, 'keyup', function(event) {
			if (event.keyCode == 16) {
				this.shiftDown = false;
			} else if (this.useShortKey != false) {
				if (event.keyCode == 77) {
					this.mDown = false;
				}
				if (event.keyCode == 17) {
					this.ctrlDown = false;
				}
				if (event.keyCode == 18) {
					this.altDown = false;
				}
			}
		}.bind(this));
		
		Event.observe(document, 'click', function(event) {
			var element = Event.element(event);
			
			if (element != $(this.id) && !element.descendantOf(this.id) && this.menuFocus == true) {
				this.listItems.invoke('removeClassName', this.cssClass);
				this.menuFocus = false;
			}
		}.bind(this));
				
		$$('body')[0].observe('focusin', this.handleMenuFocus.bind(this));
		
		if (window.addEventListener) {
			$$('body')[0].addEventListener('focus', this.handleMenuFocus.bind(this), true);
		}
	},
	
	'handleMenuFocus': function(event) {	
		var element = Event.element(event);

		if (element.up('#'+this.id)) {
			this.menuFocus = true;
			this.menuCount = this.listItems.indexOf(element.up('li'));
			
			this.isParent = (element.next()) ? true : false;
			
			if (this.isParent == false) {
				element.up().addClassName(this.cssClass);
				
				while (element.up('li')) {
					element.up('li').addClassName(this.cssClass);
					element = element.up('li');
				}
			} else if (this.isParent == true) {
				element.up().removeClassName('hover');
			}
			
		} else {
			this.listItems.invoke('removeClassName', this.cssClass);
			this.menuFocus = false;
		}
	},
	
	'keyBoardNav': function(event, code, allowedCodes) {
		if (this.menuFocus == true) {
			
			if (allowedCodes.indexOf(code) != 0) {
				event.preventDefault();
			}
			
			var element = this.listItems[this.menuCount];
			
			switch (true) {
				case code == Event.KEY_DOWN:
					if (!element.up('li')) {
						var nextElement = element.down('li');
					} else {
						var nextElement = (element.next('li')) || element.up('ul').childElements().first();
						if (nextElement) {
							element.removeClassName(this.cssClass);
						}
					}
					
					if (nextElement) {
						this.menuCount = this.listItems.indexOf(nextElement);
						nextElement.addClassName(this.cssClass);
						nextElement.down('a').focus();
					}
					
					break;
					
				case code == Event.KEY_UP:
					if (!element.up('li')) {
						var prevElement = false;
					} else {
						var prevElement = element.previous('li') || element.up('ul').childElements().last();
						element.removeClassName(this.cssClass);
					}
		
					if (prevElement) {
						this.menuCount = this.listItems.indexOf(prevElement);
						prevElement.addClassName(this.cssClass);
						prevElement.down('a').focus();
					}
					
					break;
					
				case code == Event.KEY_RIGHT:
					if (!element.up('li')) {
						var rightElement = element.next('li');
						if (rightElement) {
							element.removeClassName(this.cssClass);
						}
					} else {
						var rightElement = element.down('li') || false;
					}
		
					if (rightElement) {
						this.menuCount = this.listItems.indexOf(rightElement);
						rightElement.addClassName(this.cssClass);
						rightElement.down('a').focus();
					}
					
					break;
				
				case code == Event.KEY_LEFT:
					if (!element.up('li')) {
						var leftElement = element.previous('li');
						if (leftElement) {
							element.removeClassName(this.cssClass);
						}
					} else {
						var leftElement = element.up('li') || false;
						if (leftElement) {
							element.removeClassName(this.cssClass);
						}
					}
		
					if (leftElement) {
						this.menuCount = this.listItems.indexOf(leftElement);
						leftElement.addClassName(this.cssClass);
						leftElement.down('a').focus();
					}
					
					break;
				
				case code == Event.KEY_TAB:
					if (this.shiftDown == false) {
						this.menuCount++;
			
						var prevElement = this.listItems[this.menuCount-1];
						
						if (!prevElement.down('li')) {
							prevElement.removeClassName(this.cssClass);
							
							while (prevElement.up('li') && !prevElement.next('li')) {
								prevElement.up('li').removeClassName(this.cssClass);
								prevElement = prevElement.up('li');
							}
						}
					} else if (this.shiftDown == true) {
						this.menuCount--;
					
						var element = this.listItems[this.menuCount];
						var nextElement = this.listItems[this.menuCount+1];
						nextElement.removeClassName(this.cssClass);
						
						if (element) {
							while (element.up('li') && element.up('li').hasClassName(this.cssClass) == false) {
								element.up('li').addClassName(this.cssClass);
								element = element.up('li');
							}
						}
					}
					
					break;
					
				case code == Event.KEY_ESC:
					while (element.up('li')) {
						element.removeClassName(this.cssClass);
						var parentElement = element.up('li');
						element = element.up('li');
					}
					
					if (parentElement) {
						parentElement.down('a').focus();
						this.menuCount = this.listItems.indexOf(element);
					}

					break;
					
				case code == 32:
					if (this.isParent == true) {
						this.parentBehavior(element);
					} else {
						var href = element.down('a').href;
						window.location.href = href;
					}

					break;
					
				case code == Event.KEY_RETURN:
					if (this.isParent == true) {
						this.parentBehavior(element);
					}

					break;
			}
		}
	},
	
	'parentBehavior': function(element) {
		var nextElement = element.down('li');
		
		if (nextElement) {
			this.menuCount = this.listItems.indexOf(nextElement);
			nextElement.addClassName(this.cssClass);
			nextElement.down('a').focus();
		}
	},
	
	'enterMenu': function() {
		while (this.queue.length) {
			clearTimeout(this.queue[0][0]);
			this.leaveMenu(this);
		}
		
		// If removal of .active class is set to true, do it
		if (this.remActive == true) {
			if (typeof this.activeTimeout == "number") {
				clearTimeout(this.activeTimeout);
				delete this.activeTimeout;
			}
			
			this.activeItems.invoke('removeClassName', 'active');
		}
	},

	'leaveMenu': function(parent) {
		if (parent.queue.length) {
			var el = parent.queue.shift()[1];
			el.removeClassName(parent.cssClass);
		}
		
		// If removal of .active class is set to true, restore the active class
		if (parent.remActive == true) {
			parent.activeItems.invoke('addClassName', 'active');
		}
	}
});