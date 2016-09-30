var $j = jQuery.noConflict(),
	actions = {
		changeScreen: function changeScreen() {
			var ref = this.getAttribute('data-cs-ref'),
				screen = CS.Service.getProductIndex().screensByReference[ref];

			if (screen) {
				displayScreen(screen[CS.Util.configuratorPrefix + 'Index__c']);
			} else {
				CS.Log.warn('Screen ref', ref, 'not found');
			}
		},
		lookup: function lookup(el) {
			var p = CS.Util.configuratorPrefix;
			var params = JSON.parse(this.getAttribute('data-cs-params'));
			var index = CS.Service.getProductIndex();
			var wrapper = CS.Service.config[params.ref];
			var definition = index.all[wrapper.definitionId];
			var lookupConfigId = definition[p + 'Lookup_Config__c'];
			var excludeIds = definition[p + 'Enable_Multiple_Selection__c'] ? wrapper.attr[p + 'Value__c'] : '';

			jQuery(el).removeAttr('disabled');

			openLookupWindow(params.ref, lookupConfigId, undefined, 800, excludeIds);
		},
		clearLookup: function clearLookup(el) {
			CS.setAttributeValue(this.getAttribute('data-cs-ref'), '');
		},
		clearMultiSelectLookup : function(params) {
			var wrapper = CS.getAttributeWrapper(params.ref);
			var val = wrapper ? wrapper.attr[CS.Util.configuratorPrefix + 'Value__c'] : '';
			var ids = val ? val.split(',') : [];

			ids = ids.filter(function(id) {
				return id != params.recordId;
			});

			CS.setAttributeValue(params.ref, ids.join(','));
		}
	};

function launchConfigurator(CS, delegate, params, callback) {
	var configData;

	if (!CS.indicator) {
		initIndicator(CS);
	}

	CS.indicator.start('#indicatorContainer', 0);
	if (params.configId) { // display existing pc
		delegate.loadConfiguration(params.configId, params.definitionId, function(definitionId, configData, loadLookupRecordUrl){
			populateLookups(delegate, configData, loadLookupRecordUrl, function(){
				continueShowEditor(definitionId, configData); //display new
			});
		});
	} else {
		continueShowEditor(params.definitionId, configData); //display new
	}

	function continueShowEditor(definitionId, configData) {
		CS.Log.info('Displaying product ', definitionId);
		// CS.init - parse product model and create in-memory data structures and CS.Service instance
		CS.init(delegate, '#configurationContainer', definitionId, configData, function() {
			// Build the list of screens for this product...
			var screens = CS.Service.getProductIndex().screensByProduct[definitionId];

			//TMP until fix in core
			if (!CS.Service.config[''].screens) {
				var productIndex = CS.Service.getProductIndex();

				_.each(_.filter(CS.Service.config, function onlyConfigs(it) { return it.config != null; }),
					function buildScreensProperty(it) {
						var screensByProduct = productIndex.screensByProduct[it.config[CS.Util.configuratorPrefix + 'Product_Definition__c']],
							configScreens = [],
							attrs = productIndex.attributeDefsByProduct[it.config[CS.Util.configuratorPrefix + 'Product_Definition__c']],
							attrRefsByDef = {},
							context = {ref: it.reference};

						 _.each(attrs, function(it) {
							attrRefsByDef[it.Id] = CS.Util.generateReference(it.Name, context);
						 });

						for (var idx in screensByProduct) {
							var screen = screensByProduct[idx],
								attrs = productIndex.attributeDefsByScreen[screen.Id],
								attrRefs = [];

							for (var attrId in attrs) {
								attrRefs.push(attrRefsByDef[attrId]);
							}

							configScreens[idx] = {
								id: screen.Id,
								reference: screen._reference,
								attrs: attrRefs
							};
						}

						it.screens = configScreens;
					}
				);
			}

			// load related product data, if any exists
			initRelatedProductUtils(CS);
			CS.RPUtils.loadRPData(delegate, function(){});

			// ...and display in #screensList <OL>
			//populateScreenList(screens);

			registerUIActions();

			// Display the first (index 0) configuration screen (attributes etc) for this product
			displayScreen(0);
			CS.indicator.stop();

			callback();
		});
	}

	function registerUIActions() {
		var Log = CS.Log;

		CS.UI.Actions.register('AddOrEditRelatedProduct', {
			action: function(params) {
				Log.debug('Add or Edit related product action...', params.ref);
				var ref = params.ref,
					el = params.el,
					wrapper = CS.getAttributeWrapper(ref);

				if (!wrapper) {
					Log.error('Cannot find Attribute reference', ref);
					return;
				}

				if (el.jquery) {
					el.attr('disabled', 'disabled').css('opacity', '0.3');
				}

				if (wrapper.relatedProducts.length > 0) {
					editRelatedProduct(params);
				} else {
					selectRelatedProductDialog(wrapper, params);
				}
			}
		});

		CS.UI.Actions.register('AddRelatedProduct', {
			action: function(params) {
				Log.debug('Add related product action...', params.ref);
				var ref = params.ref,
					el = params.el,
					wrapper = CS.getAttributeWrapper(ref);

				if (!wrapper) {
					Log.error('Cannot find Attribute reference', ref);
					return;
				}

				if (el.jquery) {
					el.attr('disabled', 'disabled').css('opacity', '0.3');
				}

				selectRelatedProductDialog(wrapper, params);
			}
		});

		CS.UI.Actions.register('EditRelatedProduct', {
			action: function(params) {
				Log.debug('Edit related product action...', params.ref);
				var ref = params.ref,
					el = params.el,
					wrapper = CS.getAttributeWrapper(ref);

				if (!wrapper) {
					Log.error('Cannot find Attribute reference', ref);
					return;
				}

				if (el.jquery) {
					el.attr('disabled', 'disabled').css('opacity', '0.3');
				}

				editRelatedProduct(params);
			}
		});

		CS.UI.Actions.register('RemoveRelatedProduct', {
			action: function(params) {
				Log.debug('Remove related product...', params.ref);
				CS.Service.removeRelatedProduct(params.ref);
				CS.Rules.evaluateAllRules('Remove related product');
			}
		});

		CS.UI.Actions.register('AddLookup', {
			action: function(params) {
				var el = params.el.get(0);
				actions.lookup.apply(el, [el]);
			}
		});

		CS.UI.Actions.register('RemoveLookup', {
			action: function(params) {
				var wrapper = CS.getAttributeWrapper(params.ref),
					val = wrapper ? wrapper.attr[CS.Util.configuratorPrefix + 'Value__c'] : '',
					ids = val ? val.split(',') : [],
					newIds;

				newIds = _.filter(ids, function(it) { return it != params.id; });
				CS.setAttributeValue(params.ref, newIds.join(','));
			}
		});

		CS.UI.Actions.register('ClearLookup', {
			action: function(params) {
				var wrapper = CS.getAttributeWrapper(params.ref);
				var val = (wrapper ? wrapper.attr[CS.Util.configuratorPrefix + 'Value__c'] : '');
				var ids = (val ? val.split(',') : []);

				CS.setAttributeValue(params.ref, '');

				if (wrapper && wrapper.attr) {
					wrapper.attr[CS.Util.configuratorPrefix + 'Display_Value__c'] = '';
				}
			}
		});

		CS.UI.Actions.register('ClearMultiSelectLookup', {
			action: actions.clearMultiSelectLookup
		});

		function selectRelatedProductDialog(wrapper, params){
			// check how many RP products are available
			var availableProductOptions = CS.RPUtils.getSelectProductOptionsForAttrId(wrapper.definition.Id);

			if (availableProductOptions["ProductCategories"].length === 0 && availableProductOptions["ProductDefinitions"].length === 0) {
				Log.debug('No available product options for Attribute ', wrapper.definition.Id);
				return false;
			}

			if (availableProductOptions["ProductCategories"].length > 0 || availableProductOptions["ProductDefinitions"].length > 1) {
				// many product options available, open dialog for selection
				var self = this;
				CS.RPUtils.View.openDialog(wrapper, params, function(wrapper, params) {
					var args = [wrapper, params];
					addRelatedProduct.apply(self, args);
				});
			} else {
				// direct call to add new related product
				addRelatedProduct(wrapper, params);
			}
		}

		function loadProductModel(deferred, params) {
			CS.Service.loadProduct(params.productId, function() {
				var productIndex = CS.Service.getProductIndex(params.productId);
				if (params.availableProducts && params.availableProducts.push) {
					params.availableProducts.push(productIndex.all[params.productId]);
				}

				jQuery.extend(CS.screens, CS.DataBinder.prepareScreenTemplates(productIndex));
				params.productIndex = productIndex;

				deferred.resolve(params);
			});
		}

		function startBusyIndicator(deferred, params) {
			if (CS.indicator && CS.indicator.start) {
				CS.indicator.start();
			}
			deferred.resolve(params);
		}

		/**
		 * A custom handler for rejected promises, used in place of the default
		 * error handler method to inform the user of incorrect behaviour during
		 * adding or editing of related products
		 */
		function errorHandler(e) {
			CS.Log.error(e);
			CS.displayInfo('Could not open related product: ' + e);
			if (CS.indicator && CS.indicator.stop) {
				CS.indicator.stop();
			}
		}

		function addRelatedProduct(wrapper, params) {
			var availableProductOptions,
				availableProducts = [],
				index = CS.Service.getProductIndex();

			Log.debug('Add related product...', params.ref);

			var availableProductOptions = CS.RPUtils.getSelectProductOptionsForAttrId(wrapper.definitionId);
			var availableCategories = availableProductOptions['ProductCategories'];
			var availableDefinitions = availableProductOptions['ProductDefinitions'];

			var productId = (availableCategories.length === 0 && availableDefinitions.length === 1) ? availableDefinitions[0].Id : params.Id;
			var productIndex = CS.Service.getProductIndex(productId);

			var self = this;
			var executionChain = CS.Util.getDeferred();
			var promise = CS.Util.getPromise(executionChain)
				.then(CS.Util.defer(startBusyIndicator, self));

			if (!productIndex) {
				promise = promise.then(CS.Util.defer(loadProductModel, self));
			} else {
				promise = promise.then(CS.Util.defer(function(d, p) {
					p.productIndex = productIndex;
					d.resolve(p);
				}, self));
				availableProducts.push(productIndex.all[productId]);
			}

			promise = promise.then(function success() {
				Log.debug('availableProducts:', availableProducts);

				if (availableProducts.length === 1) {
					params.Id = availableProducts[0].Id;
				}

				return CS.Service.addRelatedProduct(params.ref, params.Id, afterDisplay);
			});

			CS.Util.onPromiseError(promise, errorHandler);
			executionChain.resolve({
				productId: productId,
				availableProducts: availableProducts
			});
		}

		function editRelatedProduct(params) {
			Log.debug('Edit related product...', params.ref);
			var config = CS.Service.config[params.ref],
				productId = config && config.config ? config.config[CS.Util.configuratorPrefix+'Product_Definition__c'] : undefined,
				productIndex = productId ? CS.Service.getProductIndex(productId) : undefined;

			var self = this;
			var executionChain = CS.Util.getDeferred();
			var promise = CS.Util.getPromise(executionChain)
				.then(CS.Util.defer(startBusyIndicator, self));

			if (!productIndex) {
				promise = promise.then(CS.Util.defer(loadProductModel, self));
			} else {
				promise = promise.then(CS.Util.defer(function(d, p) {
					p.productIndex = productIndex;
					d.resolve(p);
				}, self));
			}

			promise = CS.Service.selectConfiguration(params.ref, promise)
				.then(function success() {
					if (delegate.productHasChanged) {
						delegate.productHasChanged(CS.Service.getCurrentProductId(), 0);
					}
					displayScreen(0);
				});

			CS.Util.onPromiseError(promise, errorHandler);
			executionChain.resolve({ productId: productId });
		}
	}

	function removeRelatedProduct(params) {
		Log.debug('Remove related product...', params.ref);
		CS.Service.removeRelatedProduct(params.ref);
		CS.Rules.evaluateAllRules('Remove related product');
	}

	function selectRelatedProduct(params) {
		var ref = params.ref,
			productId = params.Id;

		CS.Service.addRelatedProduct(ref, productId, afterDisplay);
	}
}

function populateLookups(delegate, configData, loadLookupRecordUrl, callback) {
	require(['./node_modules/q/q'], function(Q) {
		CS.Log.info('Populating Lookup data');

		var cfgPrefix = CS.Util.configuratorPrefix;
		var lookupPromises = [];

		if (!CS.lookupRecords) {
			CS.lookupRecords = {};
		}

		for (var key in configData) {
			if (!configData[key] || !configData[key].attr || configData[key].displayInfo !== 'Lookup') {
				continue;
			}

			var attrVal = configData[key].attr[cfgPrefix + 'Value__c'];

			if (!attrVal) {
				continue;
			}

			var ids = attrVal ? attrVal.split(',') : [];

			_.each(ids, function(id) {
				var d = Q.defer();
				lookupPromises.push(d.promise);

				var lookupAttribute = {
					'attributeId': configData[key].attr.Id,
					'attributeValue': id,
					'attributeDefinitionId': configData[key].attr[cfgPrefix + 'Attribute_Definition__r'].Id,
					'attributeLookupConfigId': configData[key].attr[cfgPrefix + 'Attribute_Definition__r'][cfgPrefix + 'Lookup_Config__c'],
					'attributeObjectMappingId': configData[key].attr[cfgPrefix + 'Attribute_Definition__r'][cfgPrefix + 'Lookup_Config__r'][cfgPrefix + 'Search_Columns__c']
				};

				(function(d, lookupAttribute) {
					delegate.loadLookupRecord(
						JSON.stringify(lookupAttribute),
						function(result, event) {
							try {
								var lookupData = {};
								var attKey = lookupAttribute.attributeValue;
								var rec = result[attKey] || {};
								var lookupData = jQuery.extend({}, rec);

								lookupData.columnMap = rec.columnMap;
								CS.lookupRecords[attKey] = lookupData;

								CS.Log.debug('LookupData for key ', attKey, lookupData);

								d.resolve(attKey);
							} catch (e) {
								CS.Log.error('Could not load lookup data for: ', attKey, e.message, e);
								d.reject(e);
							}
						},
						{escape: false}
					);
				})(d, lookupAttribute);
			});
		}

		Q.all(lookupPromises).done(callback);
	});
}

function populateScreenList(screens) {
	var screenHtml = '',
		len = $j(screens).length, //EP added
		currentScreenIdx = CS.Service.getCurrentScreenIndex(),
		currentConfigRef = CS.Service.getCurrentConfigRef(),
		snippet;

	$j.each(screens, function (i, it) {
		if (i === currentScreenIdx) {
			screenHtml += '<span style="font-weight: bold">' + it.Name + '</span>' + getScreenStatusIcon(currentConfigRef, i) + (i == len-1 ? '' : '<span>&nbsp;&gt;&nbsp;</span> ');
		} else {
			screenHtml += '<span><a href="#" data-cs-ref="' + it._reference + '" data-cs-action="changeScreen">' + it.Name + '</a></span>' + getScreenStatusIcon(currentConfigRef, i) + (i == len-1 ? '' : '<span>&nbsp;&gt;&nbsp;</span> ');
		}
	});
	$j('#screensList').html('<div>' + screenHtml + '<div class="clear"></div></div>');
	applyActions('#screensList');
}

function getScreenStatusIcon(currentConfigRef, screenNo) {
	var currentConfig = CS.Service.config[currentConfigRef];

	if(!currentConfig || !currentConfig.screens || currentConfig.screens.length <= screenNo || currentConfig.screens[screenNo].validation === undefined) {
		return ''; // validation did not yet pass trough so return sliently and expose no icon indicators
	}
	var screenStatusIconCss = (CS.Service.config[currentConfigRef].screens[screenNo].validation.isValid) ? 'ok' : 'warning';
	return '<span><div class="screenStatusIcon ' + screenStatusIconCss + '" id=""></div></span>';
}

var displayScreenTimeout = 5000; // ms
var displayScreenTick = 100; // ms
function displayScreen(idx, currentTicker) {
	CS.Util.waitFor(
		function until() {
			CS.Log.info('***** cs_online.displayScreen(): Waiting for rules to load and initialize...');
			return (CS.Util.isObject(CS.Rules.rules) && CS.Rules.rules.hasOwnProperty(''));
		},
		function payload() {
			CS.Service.displayScreen(idx, function() {
				afterDisplay();
			});
		}
	);
}

function afterDisplay() {
	var productId = CS.Service.getCurrentProductId();
	var screenFlowName = CS.Service.getScreenFlowName();
	var index = CS.Service.getProductIndex();

	var usesScreenflow = false;
	if (screenFlowName !== '') {
		var screenflowIdsByProducts = index.screenFlowIdsByNameAndProduct[screenFlowName];
		if (screenflowIdsByProducts && screenflowIdsByProducts[productId]) {
			var screenFlowId = screenflowIdsByProducts[productId];
			populateScreenList(index.screensByScreenFlow[screenFlowId]);
			usesScreenflow = true;
		}
	}

	if (!usesScreenflow) {
		populateScreenList(index.screensByProduct[productId]);
	}

	displayButtons();
	CS.Rules.evaluateAllRules('after display');
	activateControls();
}

function activateControls() {
	applyActions('#configurationContainer');
}

function clickAction(el, f) {
	var args = arguments.length > 2 ? [].slice.call(arguments, 2) : [];
	if (el.tagName) {
		var group = $j(el).attr('data-cs-group');
		jQuery('button[data-cs-group="' + group + '"]').attr('disabled', 'disabled').css('opacity', '0.3');
	}
	args.push(el);
	f.apply(el, args);
}

function displayButtons() {
	var pp = CS.Util.configuratorPrefix;
	var buttonsHTML = '';
	var currentScreenIdx = CS.Service.getCurrentScreenIndex();
	var ref = CS.Service.getCurrentConfigRef();
	var currentConfig = CS.Service.config[ref].config;

	var rootRef = ref;
	if (typeof ref === 'string' && ref.indexOf('_') > 0) {
		var refParts = ref.split(/_/);
		if (refParts.length > 0 && !isNaN(refParts[refParts.length - 1])) {
			refParts[refParts.length - 1] = 0;
			rootRef = refParts.join('_');
		}
	}
	var numScreens = CS.Service.config[ref].screens.length;

	var productIndex = CS.Service.getProductIndex(currentConfig[pp + 'Product_Definition__c']);
	var productId = CS.Service.getCurrentProductId();
	var productDefinition = productIndex.productsById[productId];

	if (currentScreenIdx > 0) {
		buttonsHTML += '<button data-cs-group="Previous" onclick="clickAction(this, displayScreen, ' + (currentScreenIdx - 1) + ')">Previous</button>&nbsp;&nbsp; ';
	}

	if (currentScreenIdx < numScreens - 1) {
		buttonsHTML += '<button data-cs-group="Next" onclick="clickAction(this, displayScreen, ' + (currentScreenIdx + 1) + ')">Next</button>&nbsp;&nbsp; ';
	}

	if (ref === '') {
		buttonsHTML += '<button data-cs-group="Cancel" onclick="clickAction(this, cancel, buildCancelUrl(params))">Cancel</button>&nbsp;&nbsp; ';
		buttonsHTML += '<button data-cs-group="Finish" onclick="clickAction(this, finish)">Finish</button>&nbsp;&nbsp; ';
		if (productDefinition[pp + 'Allow_progress_from_incomplete_screens__c']) {
			buttonsHTML += '<button data-cs-group="ForceFinish" onclick="clickAction(this, saveConfiguration)" class="hidden">Save without Validation</button>&nbsp;&nbsp; ';
			buttonsHTML += '<button data-cs-group="ForceFinish" onclick="clickAction(this, finish)" class="hidden">Validate and Save</button>&nbsp;&nbsp; ';
		}
	} else {
		buttonsHTML += '<button data-cs-group="Cancel" onclick="clickAction(this, cancelRelated)">Cancel</button>&nbsp;&nbsp; ';
		buttonsHTML += '<button data-cs-group="Finish" onclick="clickAction(this, cont)">Continue</button>&nbsp;&nbsp; ';
		if (productDefinition[pp + 'Allow_progress_from_incomplete_screens__c']) {
			buttonsHTML += '<button data-cs-group="ForceFinish" onclick="clickAction(this, saveRelated)" class="hidden">Save without Validation</button>&nbsp;&nbsp; ';
			buttonsHTML += '<button data-cs-group="ForceFinish" onclick="clickAction(this, cont)" class="hidden">Validate and Save</button>&nbsp;&nbsp; ';
		}
	}


	jQuery('.CS_configButtons').html(buttonsHTML);
}

function getLocationOrigin() {
	var locationOrigin = '';
	if (!window.location.origin) {
		// IE9 fix - IE9 window.location object doesn't contain "origin" property
		locationOrigin =
			window.location.protocol + "//" +
			window.location.hostname +
			(window.location.port ? ':' + window.location.port: '');
	} else {
		locationOrigin = window.location.origin;
	}
	return locationOrigin;
}

function buildCancelUrl(pageParams) {
	if (!pageParams) {
		pageParams = {};
	}
	if (!pageParams.hasOwnProperty('retURL')) {
		throw new Error('buildCancelUrl requires the first parameter to be an object containing a field named "retURL"');
	}

	var params = {};
	if (pageParams.hasOwnProperty('isDtp') && typeof pageParams.isDtp === 'string' && pageParams.isDtp.trim() !== '') {
		params['isdtp'] = pageParams.isDtp;
	}

	return buildUrl(pageParams.retURL, params);
}

function buildAfterFinishUrl(pageParams, serviceParams) {
	var configId = serviceParams.configId || serviceParams.rootConfigIds.replace(/[\[\]&]|quot;/gi, '');
	var basketId = serviceParams.basketId;
	var offerId = serviceParams.offerId;

	var returnToId = '/';
	if (offerId && offerId.trim && offerId.trim() != '') {
		returnToId += offerId;
	} else {
		returnToId += ((typeof basketId == 'string' && basketId != '') ? basketId : configId);
	}

	// Redirect the user's browser to the basket details page if the new basket was created
	var isNewBasket = serviceParams.isNewBasket;
	isNewBasket = (typeof isNewBasket === 'string' && isNewBasket.toLowerCase() === 'true');

	if (pageParams && typeof pageParams['retURL'] === 'string' && pageParams.retURL.trim() !== '' && !isNewBasket) {
		returnToId = pageParams.retURL.trim();
	}

	if (returnToId.indexOf('http') !== 0) {
		returnToId = getLocationOrigin() + returnToId;
	}

	var params = {};

	if (pageParams && typeof pageParams['isDtp'] === 'string' && pageParams.isDtp.trim() !== '') {
		params['isdtp'] = pageParams.isDtp;
	}

	return buildUrl(returnToId, params);
}

function buildUrl(baseUrl, params) {
	var url = baseUrl;

	if (params && typeof params === 'object') {
		var encodedParams = [];
		for (var k in params) {
			if (params.hasOwnProperty(k)) {
				encodedParams.push(encodeURIComponent(k) + "=" + encodeURIComponent(params[k]));
			}
		}

		if (encodedParams.length > 0) {
			url += (url.indexOf("?") > -1 ? "&" : "?") + encodedParams.join("&");
		}
	}

	return url;
};

function applyActions(scope) {
	var elementsWithActionAttrs = $j(scope).find('[data-cs-action]');
	$j.each(elementsWithActionAttrs, function (i, it) {
		var el = $j(it),
			action = actions[el.attr('data-cs-action')];
		if (action) {
			el.click(function(){
				clickAction(this, action);
			});
		}
	});
}

function cancel(url) {
	location.href = url;
}

function cancelRelated() {
	CS.Service.cancelCurrentConfiguration(afterDisplay);
}

function saveRelated() {
	CS.Service.saveAndContinue(afterDisplay);
}

function cont() {
	var validationResult = CS.Service.validateCurrentConfig(true);

	if (validationResult.isValid) {
		var ref = CS.Service.getCurrentConfigRef(),
			currentConfig = CS.Service.config[ref].config;

		currentConfig[CS.Util.configuratorPrefix+'Configuration_Status__c'] = 'Valid';
		saveRelated();
	} else {
		updateFinishButtonUI(this);

		CS.markConfigurationInvalid(
			CS.Service.getCurrentConfigRef(),
			'There are validation errors within the configuration. Please address the problems indicated below.'
		);
	}
}

function updateFinishButtonUI(button, isReset) {
	if (typeof isReset === 'undefined') {
		isReset = false;
	}

	var group = jQuery(button).attr('data-cs-group');
	var finishButtons = jQuery('button[data-cs-group="' + group + '"]');
	var forceFinishButtons = jQuery('button[data-cs-group="ForceFinish"]');
	if (isReset || forceFinishButtons.length < 1) {
		finishButtons
			.removeAttr('disabled')
			.css('opacity', '');
	} else {
		if (group === 'ForceFinish') {
			forceFinishButtons
				.removeAttr('disabled')
				.css('opacity', '');
		} else {
			finishButtons
				.removeClass('visible')
				.addClass('hidden');
			forceFinishButtons
				.removeClass('hidden')
				.addClass('visible');
		}
	}
}

var popup,
	currentLookupId;

jQuery(window).focus(function() {
	closePopup();
});

window.addEventListener('message', handleMessage);

function handleMessage(event) {
	if (jQuery.browser.msie) {
		closeLookupOverlay();
	}

	// set message without encoding (for regular 'raw' string)
	var message = event.data;
	try {
		// base64-decode event.data message in case it's encoded
		message = atob(event.data);
	}
	catch(ex) {}

	try {
		message = JSON.parse(message);
		if (message.action == 'Lookup.SelectRecord') {
			lookupSelect(message.id, message.name, message.data);
		}
	} catch (e) {
		CS.Log.info('Received unparseable message, ignoring', message);
	}

}

function openLookupWindow(ref, lookupId, dynamicValueAttributes, width, excludeIds) {
	closePopup();
	CS.currentLookupRef = ref;

	/*
	 * Dynamic filter from JQuery
	 */
	var nameIdPairs;
	var nameValuePairs;
	var prefix = CS.Util.configuratorPrefix;
	var index = CS.Service.getProductIndex();
	var lc = index.all[lookupId];
	var lcFilterId = lc ? lc[prefix + 'Filter__c'] : undefined;
	var lcFilter = lcFilterId ? index.all[lcFilterId] : undefined;
	var referencedAttributes = [];
	var parentReference = CS.Util.getParentReference(CS.currentLookupRef);
	var attrDef = index.all[CS.getAttributeWrapper(CS.currentLookupRef).definitionId];
	var definitionId = attrDef[prefix + 'Product_Definition__c'];
	var isMultiSelect = attrDef[prefix + 'Enable_Multiple_Selection__c'] && attrDef[prefix + 'Max__c'] != 1;

	var dynamicFilterValues = _getDynamicFilterValues(lookupId, parentReference, lcFilter);
	var field = CS.getAttributeDisplayValue(ref) || '';
	var searchValue = isMultiSelect ? '' : field;

	var lookupPageUrl = _getLookupPageUrl(lookupId, searchValue, definitionId, dynamicFilterValues, excludeIds);

	var popupWidth = 800;
	var popupHeight = 480;
	if (!jQuery.browser.msie) {
		var p = _getPopupPosition(popupWidth, popupHeight);
		popup = window.open(lookupPageUrl, 'CSlookup', 'width=' + popupWidth + ',height=' + popupHeight + ',top=' + p.top + ',left=' + p.left + ',scrollbars=yes,toolbar=no,location=no,status=no,menubar=no');
	} else {
		jQuery('#popupOverlay')
			.css('display', 'block')
			.on('click', closeLookupOverlay);
		jQuery('#lookupContainer')
			.html('<iframe border="0" height="' + popupHeight + '" width="' + popupWidth + '" src="' + lookupPageUrl + '"></iframe>');
	}
}

function _getDynamicFilterValues(lookupId, parentReference, filterLookupQuery) {
	var lookupConfig = CS.Service.getProductIndex(CS.Service.getCurrentProductId()).all[lookupId];
	var prefix = CS.Util.configuratorPrefix;

	if (!filterLookupQuery && !lookupConfig[prefix + 'lookup_customisations_impl__c']) {
		return [];
	}

	var dynamicFilterValues = [];
	referencedAttributes = CS.Service.getLookupQueryReferencedAttributes(lookupId);
	_.each(referencedAttributes, function(it) {
		var reference = CS.Util.generateReference(it, {ref: parentReference});

		var attWrapper = CS.getAttributeWrapper(reference);
		if (!attWrapper.definition) {
			var productIndex = CS.Service.getProductIndex();
			attWrapper.definition = productIndex.all[attWrapper.definitionId];
		}
		var definition = attWrapper.definition;
		var attValue = CS.getAttributeValue(reference);
		var typeInfo = {'type': definition[prefix + 'Data_Type__c'], 'scale': definition[prefix + 'Scale__c']};
		attValue = CS.DataConverter.normalizeValue(CS.DataConverter.unlocalizeValue(attValue, typeInfo), typeInfo);

		dynamicFilterValues.push([it, attValue]);
	});
	return dynamicFilterValues;
}

function _getLookupPageUrl(lookupId, searchValue, definitionId, dynamicFilterValues, excludeIds) {
	var lookupPagePath = '/apex/' + CS.Util.configuratorPrefix + 'Lookup';
	if (CS.params && CS.params.communitiesPrefix) {
		lookupPagePath = CS.params.communitiesPrefix + lookupPagePath;
	}

	dynamicFilterValues = dynamicFilterValues || [];
	var filterParams = dynamicFilterValues.map(function(item) {
		return (item.join ? item.join('%3D') : '');
	}).join('|').replace(/\s/g, "+");

	return lookupPagePath +
		'?lookupId=' + lookupId +
		'&searchValue=' + searchValue +
		'&productDefinitionId=' + definitionId +
		'&attributeValues=' + filterParams +
		'&excludeIds=' + urlEncode(excludeIds ? excludeIds : '');
}

function _getPopupPosition(popupWidth, popupHeight, $window, $screen) {
	if (typeof $window === 'undefined') {
		$window = window;
	}
	if (typeof $screen === 'undefined') {
		$screen = screen;
	}

	// Account for dual/multiple screen setups
	var dualScreenLeft = $window.screenLeft !== undefined ? $window.screenLeft : $screen.left;
	var dualScreenTop = $window.screenTop !== undefined ? $window.screenTop : $screen.top;

	var docWidth = $window.innerWidth || document.documentElement.clientWidth || $screen.width;
	var docHeight = $window.innerHeight || document.documentElement.clientHeight || $screen.height;

	var popupTop = (docHeight < popupHeight ? 0 : ((docHeight - popupHeight) / 2) + dualScreenTop) + ($window.screenY ? $window.screenY - dualScreenTop : 0);
	var popupLeft = (docWidth < popupWidth ? 0 : ((docWidth - popupWidth) / 2) + dualScreenLeft) + ($window.screenX ? $window.screenX - dualScreenLeft : 0);

	return {
		top: popupTop,
		left: popupLeft
	};
}

function closeLookupOverlay() {
	jQuery('#popupOverlay').css('display', 'none');
	jQuery('#lookupContainer').html('');
}

function urlEncode(val) {
	return encodeURIComponent(val).replace(/\s/g, "+");
}

function openCalloutWindow(url, id, params, width) {
	closePopup();
	popup = window.open(url, 'callout', 'width=800, height=480, scrollbars=yes, toolbar=no, location=no, status=no, menubar=no');
}

function closePopup() {
	if (popup) {
		var tmp = popup;
		popup = null;
		tmp.close();
	}
}

function lookupSelect(id, name, data) {
	// copy data so IE does not lose the reference when the window closes
	var localData = {};
	var prefix = CS.Util.configuratorPrefix;

	var attrWrapper = CS.getAttributeWrapper(CS.currentLookupRef) || {};
	var configWrapper = CS.getConfigurationWrapper(CS.Util.getAnchorReference(CS.Util.getParentReference(CS.currentLookupRef)));
	var prodDefId = configWrapper ? configWrapper.config[prefix + 'Product_Definition__c'] : undefined;
	var prodDef = CS.Service.getProductIndex(prodDefId).all[attrWrapper.definitionId];
	var isMultiSelectLookup = prodDef && prodDef[prefix + 'Enable_Multiple_Selection__c'] && prodDef[prefix + 'Max__c'] != 1;
	var val = attrWrapper ? attrWrapper.attr[prefix + 'Value__c'] : undefined;
	var ids = val ? val.split(',') : [];

	for (key in data) {
		localData[key] = data[key];
	}

	if (!isMultiSelectLookup) {
		val = id;
		attrWrapper.attr[prefix + 'Display_Value__c'] = name;
	} else {
		ids.push(id);
		val = ids.join(',');
	}
	CS.lookupRecords[id] = localData;
	CS.setAttributeValue(CS.currentLookupRef, val);
	CS.Rules.evaluateAllRules('after cs_online.lookupSelect()');
}

function initIndicator(CS) {
	//Damjan Jelas 12/04/2013
	//Indicator extension
	(function(CS) {
		var module = CS.indicator = {};
		module = (function(indicator) {
			var $ = jQuery,
			log = CS.log,
			cssClass = 'indicator',
			cssBackgroundClass = 'indicatorBackground',
			startLast,
			stopLast,
			timer,
			start = function(selector, miliseconds) {
				if (!CS.isLoadingOverlayEnabled()) {
					return;
				}

				if (selector) {
					var container = $(selector);

					//implicit parameter memory, so we can call 'start' after 'stop' on the same element without selector parameter
					startLast = function() {
						if( container.find('.' + cssClass).length === 0){				//don't create elements if they exist
							container.end();
							container.html('<div class="' + cssClass + '"></div>');
							container.append('<div class="' + cssBackgroundClass + '"></div>');
							container.show();
							log('Starting indicator for: ' + selector);
						}
						clearTimer();
					};
					stopLast = function() {
						stop(selector);
					};
				}
				if (startLast) {
					if (!miliseconds) {
						startLast();
					} else{
						//don't create new delayed function if we already have one
						//user should call 'stop' method before 'start' if he want's to re-initialize delay
						if (!timer) {
							timer = setTimeout(startLast, miliseconds);
							log('Setting indicator timer: ID-' + timer + ', Delay-' + miliseconds);
						}
					}
				}
			},
			clearTimer = function() {
				if (timer) {
					log('Removing indicator timer: ID-' + timer );
					clearTimeout(timer);
					timer = null;
				}
			},
			stop = function (selector) {
				if (!CS.isLoadingOverlayEnabled()) {
					return;
				}

				if (selector) {
					var container = $(selector);
					container.children('.' + cssClass ).remove();
					container.children('.' + cssBackgroundClass).remove();
					container.hide();
					log('Stoping indicator for: ' + selector);
				} else {
					clearTimer();
					stopLast && stopLast();
				}
			};
			//expose
			indicator.start = start;
			indicator.stop = stop;
			return indicator;
		})(module || {});
	})(CS);
}

/**
 * Related Products - v2 support
 *
 * APO - Available Product Option
 * RP - Related Product
 */
function initRelatedProductUtils(CS) {
	(function(CS) {
		var module = CS.RPUtils = {};

		module = (function(RPUtils) {
			var rpParams = {};
			var rpCache = null;
			var rpAttributeId = '';
			var selectedCategoryId = '';
			var breadcrumbStack = [];
			var APO_TYPE_CATEGORY = 'category';
			var APO_TYPE_PRODUCT_DEFINITION = 'product definition';
			var prefix = CS.Util.configuratorPrefix;

			var $ = jQuery,
			loadRPData = function(delegate, callback) {
				// check if PD has related products, if no RPs available be good citizen and skip remote call
				productDefinitionId = CS.Service.config[''].config[prefix + 'Product_Definition__c'];

				if (!anyRelatedProductAttributesForPD(productDefinitionId)) {
					// there are no related products for this product so we can skip remote call
					CS.Log.info("No Related Products for this product definition, skip remote action call to fetch Available Product Options.");
					return;
				}

				// if cache is already loaded skip remote call, otherwise fetch data
				if (RPUtils.rpCache === null) {
					var linkedObjectId = CS.params.linkedId.replace(/\//, '');
					var params = {
						"linkedObjectId" : linkedObjectId
					};

					delegate.loadRelatedProductSelectionData(JSON.stringify(params),
						function(result) {
							RPUtils.rpCache = result;
							callback();
						}
					);
				}
			},

			anyRelatedProductAttributesForPD = function(pdId) {
				var wrapper = CS.Service.getProductIndex(pdId);
				var attrs = wrapper.attributeDefsByProduct[Object.keys(wrapper.attributeDefsByProduct)[0]];

				for (attrId in attrs) {
					var attr = attrs[attrId];
					if (attr[prefix + 'Type__c'] === 'Related Product') {
						return true;
					}
				}
				return false;
			},

			// filter APO by Related Product Attribute Id
			getSelectProductOptionsForAttrId = function(attributeId) {
				if (RPUtils.rpCache === null) {
					return [];
				}

				var apoProductDefinitions = [];
				var apoProductCategories = [];
				var apoLength = RPUtils.rpCache.availableProductOptions.length;

				// get available product options for selected attribute definition
				for (var i = 0; i < apoLength; i++) {
					var apo = RPUtils.rpCache.availableProductOptions[i];

					if (apo[prefix + 'Attribute_Definition__c'] === attributeId) {
						if (apo[prefix + 'Product_Category__c'] !== undefined) {

							var apoCat = getCategoryById(apo[prefix + 'Product_Category__c']);

							if (apoCat) {

								if (apoCat[prefix + 'Restrict_Access__c'] && skipCategoryForProfile(apoCat.Id)) {
									continue;
								}

								apoProductCategories.push(
									getApoItem(
										apoCat.Id,
										apoCat.Name,
										apoCat[prefix + 'Sequence__c'],
										apoCat[prefix + 'Description__c'],
										APO_TYPE_CATEGORY
									)
								);
							}

						} else {

							var apoPD = getProductDefinitionById(apo[prefix + 'Product_Definition__c']);

							if (apoPD == undefined || (apoPD[prefix + 'Restrict_Access__c'] && skipProductDefinitionForProfile(apoPD.Id))) {
								continue;
							}

							apoProductDefinitions.push(
								getApoItem(
									apoPD.Id,
									apoPD.Name,
									apoPD[prefix + 'Sequence__c'],
									apoPD[prefix + 'Description__c'],
									APO_TYPE_PRODUCT_DEFINITION
								)
							)
						}
					}
				}

				return {
					'ProductCategories' : apoProductCategories.sort(compareBySequence),
					'ProductDefinitions' : apoProductDefinitions.sort(compareBySequence)
				}
			},

			// filter APO by categoryId
			getSelectProductOptionsForCategory = function(categoryId) {
				var apoProductDefinitions = [];
				var apoProductCategories = [];

				// traverse Cache Product Categories and filter by category
				var apoCacheProductCategories = RPUtils.rpCache.productCategories;
				for (var i = 0; i < apoCacheProductCategories.length; i++) {
					var apoCat = apoCacheProductCategories[i];

					if (apoCat[prefix + 'Parent_Category__c'] === categoryId) {
						if (apoCat) {

							if (apoCat[prefix + 'Restrict_Access__c'] && skipCategoryForProfile(apoCat.Id)) {
								continue;
							}

							apoProductCategories.push(
								getApoItem(
									apoCat.Id,
									apoCat.Name,
									apoCat[prefix + 'Sequence__c'],
									apoCat[prefix + 'Description__c'],
									APO_TYPE_CATEGORY
								)
							);
						}
					}
				}

				// traverse Cache Product Definitions and filter by category
				var apoCacheProductDefinitions = RPUtils.rpCache.productDefinitions;
				for (var i = 0; i < apoCacheProductDefinitions.length; i++) {
					var apoPD = apoCacheProductDefinitions[i];

					if (apoPD && apoPD[prefix + 'Product_Category__c'] === categoryId) {

						if (apoPD[prefix + 'Restrict_Access__c'] && skipProductDefinitionForProfile(apoPD.Id)) {
							continue;
						}

						apoProductDefinitions.push(
							getApoItem(
								apoPD.Id,
								apoPD.Name,
								apoPD[prefix + 'Sequence__c'],
								apoPD[prefix + 'Description__c'],
								APO_TYPE_PRODUCT_DEFINITION
							)
						);
					}
				}

				return {
					'ProductCategories' : apoProductCategories.sort(compareBySequence),
					'ProductDefinitions' : apoProductDefinitions.sort(compareBySequence)
				}
			},

			compareBySequence = function(a, b) {
				if (a.Sequence__c < b.Sequence__c) {
					return -1;
				}
				if (a.Sequence__c > b.Sequence__c) {
					return 1;
				}
				return 0;
			},

			getCategoryById = function(categoryId) {
				var apoProductCategories = RPUtils.rpCache.productCategories;
				for (var i = 0; i < apoProductCategories.length; i++) {
					var apoCat = apoProductCategories[i];
					if (apoCat.Id === categoryId) {
						return apoCat;
					}
				}
			},

			getProductDefinitionById = function(pdId) {
				var apoProductDefinitions = RPUtils.rpCache.productDefinitions;
				for (var i = 0; i < apoProductDefinitions.length; i++) {
					var apoPD = apoProductDefinitions[i];
					if (apoPD.Id === pdId) {
						return apoPD;
					}
				}
			},

			getApoItem = function (id, name, sequence, description, apoType) {
				return {
					'Id' : id,
					'Name' : name,
					'Sequence__c' : sequence,
					'Description' : (description) ? description : '-',
					'onclick' : (apoType === APO_TYPE_CATEGORY) ?
								' onclick="CS.RPUtils.View.selectCategory(\'' + id + '\')" '
								:
								' onclick="CS.RPUtils.View.selectProductDefinition(\'' + id + '\')" '
				}
			},

			skipCategoryForProfile = function (categoryId) {
				if (CS.RPUtils.rpCache.profilePermisions.length === 0) {
					return true;
				}

				var profileId = CS.RPUtils.rpCache.profileId.substr(0, 15);
				var profilePermisions = CS.RPUtils.rpCache.profilePermisions;

				for (var i = 0; i < profilePermisions.length; i++) {
					var profilePermision = profilePermisions[i];
					if (profilePermision[prefix + 'Product_Category__c'] === categoryId && profilePermision[prefix + 'Profile_Id__c'].substr(0, 15) === profileId) {
						return false;
					}
				}

				return true;
			},

			skipProductDefinitionForProfile = function (productDefinitionId) {
				if (CS.RPUtils.rpCache.profilePermisions.length === 0) {
					return true;
				}

				var profileId = CS.RPUtils.rpCache.profileId.substr(0, 15);
				var profilePermisions = CS.RPUtils.rpCache.profilePermisions;

				for (var i = 0; i < profilePermisions.length; i++) {
					var profilePermision = profilePermisions[i];
					if (profilePermision[prefix + 'Product_Definition__c'] === productDefinitionId && profilePermision[prefix + 'Profile_Id__c'].substr(0, 15) === profileId) {
						return false;
					}
				}

				return true;
			},

			/**
			 * View constants and methods
			 */
			EL_SCREEN_LIST = '#screensList',
			EL_CONFIGURATOR_CONTAINER = '#configurationContainer',

			EL_PRODUCT_DEFINITION_LIST = '#rpSelectProductDefinitionList',
			EL_SCREEN_TITLE = '#rpDialogContainer h2.pageDescription',
			EL_DIALOG_CONTAINER = '#rpDialogContainer',
			EL_CATEGORY_LIST = '#rpSelectCategoryList',
			EL_CANCEL_BUTTON = '#rpCancelButton',
			EL_BREADCRUMB = '#rpdBreadcrumb',

			openDialog = function(wrapper, params, callback) {

				// store params for callback when selection is done
				rpParams.wrapper = wrapper;
				rpParams.params = params;
				rpParams.callback = callback;

				rpAttributeId = wrapper.definitionId;

				// hide configurator screen
				jQuery(EL_CONFIGURATOR_CONTAINER).hide();
				jQuery(EL_SCREEN_LIST).hide();

				// show selection dialog
				showDialog();

				// hook events
				jQuery(EL_CANCEL_BUTTON).click(closeDialog);

				// set breadcrumbs
				jQuery(EL_BREADCRUMB).html(htmlBreadcrumbNavigation());

				// update related product dialog title
				var currentConfig = CS.Service.config;
				for (key in currentConfig) {
					if (currentConfig[key].definition && currentConfig[key].definition['Id'] === rpAttributeId) {
						jQuery(EL_SCREEN_TITLE).text(currentConfig[key].definition['Name']);
					}
				}

				// show view for new category or product option
				showSPOView();
			},

			closeDialog = function() {

				jQuery(EL_CONFIGURATOR_CONTAINER).show();
				jQuery(EL_SCREEN_LIST).show();

				jQuery(rpParams.params.el)
					.removeAttr('disabled')
					.css('opacity', '');

				jQuery(EL_DIALOG_CONTAINER).hide();

				// clean up
				rpAttributeId = '';
				selectedCategoryId = '';
				breadcrumbStack = [];
			},

			selectCategory = function(categoryId) {
				// if deeper subcategory selected push new catId to breadcrumbs stack
				if (breadcrumbStack.indexOf(categoryId) == -1) {
					breadcrumbStack.push(categoryId);
				} else {
					breadcrumbStack = breadcrumbStack.slice(0, breadcrumbStack.indexOf(categoryId) - 1);
				}

				// set current category
				selectedCategoryId = categoryId;

				// show view for new category
				showSPOView();
			},

			selectProductDefinition = function(pdId) {
				closeDialog();
				rpParams.params.Id = pdId;
				rpParams.callback(rpParams.wrapper, rpParams.params);
			},

			showDialog = function() {
				jQuery(EL_DIALOG_CONTAINER).show();
			},

			// show Select Product Options View
			showSPOView = function() {
				// for first APO level check related product "Available Product Options", for subcategories collect children (cats, pds)
				var availableProductOptions;
				if (selectedCategoryId === '') {
					availableProductOptions = getSelectProductOptionsForAttrId(rpAttributeId);
				} else {
					availableProductOptions = getSelectProductOptionsForCategory(selectedCategoryId);
				}

				var apoCategories = availableProductOptions['ProductCategories'];
				var apoProductDefinitions = availableProductOptions['ProductDefinitions'];

				var html = '';
				var jsonTableData = {};

				if (apoCategories.length > 0) {
					jsonTableData.header = ['Product Name', 'Description'];
					jsonTableData.data = [];
					for (key in apoCategories) {
						var category = apoCategories[key];
						if(category.hasOwnProperty('Id')) {
							jsonTableData.data.push(category);
						}
					}
					html = htmlTableList(jsonTableData);
				} else {
					html = htmlNoData();
				}
				jQuery(EL_CATEGORY_LIST).html(html);

				html = '';
				jsonTableData = {};
				if (apoProductDefinitions.length > 0) {
					jsonTableData.header = ['Category Name', 'Description'];
					jsonTableData.data = [];
					for (key in apoProductDefinitions) {
						var apoPD = apoProductDefinitions[key];
						if(apoPD.hasOwnProperty('Id')) {
							jsonTableData.data.push(apoPD);
						}
					}
					html = htmlTableList(jsonTableData);
				} else {
					html = htmlNoData();
				}

				jQuery(EL_PRODUCT_DEFINITION_LIST).html(html);
				jQuery(EL_BREADCRUMB).html(htmlBreadcrumbNavigation());
			},

			htmlBreadcrumbNavigation = function() {
				var htmlBreadcrumb = '&nbsp;';
				var breadcrumbElements = [];
				var len = breadcrumbStack.length;

				breadcrumbElements.push('<a href="#" onclick="CS.RPUtils.View.showRootSelection()"> Root Product Options </a>');

				if (len > 0) {
					for (var i = 0; i < breadcrumbStack.length; i++) {
						var categoryId = breadcrumbStack[i];
						var category = getCategoryById(categoryId);

						breadcrumbElements.push('<a href="#" onclick="CS.RPUtils.View.selectCategory(\'' + categoryId + '\')"  >' + category.Name + '</a>');
					}
					breadcrumbElements.pop();
					htmlBreadcrumb = breadcrumbElements.join('&nbsp; &gt; &nbsp;')
				}

				return htmlBreadcrumb;
			},

			htmlTable = function(jsonTableData) {
				var html = '';

				var header = '<tr>'
						+ '<th class="" width="50%">' + jsonTableData.header[0] + '</th>'
						+ '<th class="">' + jsonTableData.header[1] + '</th>'
						+ '</tr>';

				var trData = '';

				for (var i = 0; i < jsonTableData.data.length; i++) {
					var apo = jsonTableData.data[i];

					// 'Id' : category['Id'],
					trData += '<tr class="dataRow even first" ' + apo['onclick'] + '>'
						+ '  <td class="dataCell" >' + apo['Name'] + '</td>'
						+ '  <td class="dataCell" >' + apo['Description'] + '</td>'
						+ '</tr>';
				}

				html = '<table widht="100%" class="list" cellspacing="0" cellpadding="0" border="0">'
						+ '<tbody>'
						+ header
						+ trData
						+ '</tbody>'
						+ '</table>';

				return html;
			},

			htmlTableList = function(jsonTableData) {
				var trData = '';
				for (var i = 0; i < jsonTableData.data.length; i++) {
					var apo = jsonTableData.data[i];
					trData += '<tr class="dataRow even first" ' + apo['onclick'] + '>'
						+ '  <td class="dataCell" >' + apo['Name'] + '</td>'
						+ '  <td class="dataCell">' + apo['Description'] + '</td>'
						+ '</tr>';
				}
				return trData;
			},

			htmlNoData = function() {
				var html = '<tr>'
					+ ' <td colspan="2">'
					+ '  No items to display'
					+ ' </td>'
					+ ' </tr>';
				return html;
			},

			showRootSelection = function() {
				selectedCategoryId = '';
				breadcrumbStack = [];
				showSPOView();
			};

			/**
			 * Expose private functionality for js unit test context
			 */
			if (typeof IS_TEST_CONTEXT === 'boolean' && IS_TEST_CONTEXT) {
				RPUtils.__TEST__ = {};
				RPUtils.__TEST__.getSelectProductOptionsForCategory = getSelectProductOptionsForCategory;
				RPUtils.__TEST__.skipCategoryForProfile = skipCategoryForProfile;
				RPUtils.__TEST__.skipProductDefinitionForProfile = skipProductDefinitionForProfile;
			}

			/**
			 * Expose public functionality
			 */
			// controller
			RPUtils.loadRPData = loadRPData;
			RPUtils.getSelectProductOptionsForAttrId = getSelectProductOptionsForAttrId;

			// view
			RPUtils.View = {};
			RPUtils.View.showRootSelection = showRootSelection;
			RPUtils.View.openDialog = openDialog;
			RPUtils.View.closeDialog = closeDialog;
			RPUtils.View.selectCategory = selectCategory;
			RPUtils.View.selectProductDefinition = selectProductDefinition;

			// model
			RPUtils.rpAttributeId = rpAttributeId;
			RPUtils.selectedCategoryId = selectedCategoryId;
			RPUtils.rpCache = rpCache;
			RPUtils.rpParams = rpParams;

			return RPUtils;
		})(module || {});
	})(CS);
};
