/**
 * J_UnifiSensor.js
 * Configuration interface for UnifiSensor
 *
 * Based on UnifiSensor https://github.com/peterv-vera/unifi-sensor
 * and VirtuelSensor https://github.com/toggledbits/VirtualSensor
 */

var UnifiSensor = (function (api) {
	// example of unique identifier for this plugin...
	var uuid = '73955f3a-7775-11e7-b5a5-be2e44b06b34';
	var unifisensor_svs = 'urn:peterv-vera:serviceId:UnifiSensor1';
	var myModule = {};
	
	var deviceID = api.getCpanelDeviceId();
	
	function onBeforeCpanelClose(args){
        console.log('handler for before cpanel close');
    }
    
	function init(){
        // register to events...
        api.registerEventHandler('on_ui_cpanel_before_close', myModule, 'onBeforeCpanelClose');
    }
	
	function initPlugin(){
	}
	
	///////////////////////////

	function period_set(deviceID, varVal) {
	  api.setDeviceStateVariablePersistent(deviceID, unifisensor_svs, "Period", varVal, 0);
	} 
	
	function timeout_set(deviceID, varVal) {
	  api.setDeviceStateVariablePersistent(deviceID, unifisensor_svs, "DeviceTimeout", varVal, 0);
	}

	// functions for additional unifi variables
	
	function url_set(deviceID, varVal) {
	  api.setDeviceStateVariablePersistent(deviceID, unifisensor_svs, "UnifiURL", varVal, 0);
	}

	function username_set(deviceID, varVal) {
	  api.setDeviceStateVariablePersistent(deviceID, unifisensor_svs, "UnifiUser", varVal, 0);
	} 
	
	function passwd_set(deviceID, varVal) {
	  api.setDeviceStateVariablePersistent(deviceID, unifisensor_svs, "UnifiPassword", varVal, 0);
	}
	
	function site_set(deviceID, varVal) {
	  api.setDeviceStateVariablePersistent(deviceID, unifisensor_svs, "UnifiSite", varVal, 0);
	}
	
	function ReloadEngine(){
		api.luReload();
	}
	
	function UnifiSensorSettings(deviceID) {
		try {
			init();
			
			var period  = api.getDeviceState(deviceID,  unifisensor_svs, 'Period');
			var timeout  = api.getDeviceState(deviceID,  unifisensor_svs, 'DeviceTimeout');
			// variables for additional unifi stuff
			var url  = api.getDeviceState(deviceID,  unifisensor_svs, 'UnifiURL');
			var username  = api.getDeviceState(deviceID,  unifisensor_svs, 'UnifiUser');
			var passwd  = api.getDeviceState(deviceID,  unifisensor_svs, 'UnifiPassword');
			var site  = api.getDeviceState(deviceID,  unifisensor_svs, 'UnifiSite');
			
			if(isNaN(timeout)) timeout = 0;

			var html =  '<table>' +
				' <tr><td>Poll Period </td><td><input  type="text" id="query_period" size=16 value="' +  period + '" onchange="UnifiSensor.period_set(' + deviceID + ', this.value);"> seconds</td></tr>' +
				' <tr><td>Device Timout </td><td><input type="text" id="query_retries" size=16 value="' +  timeout + '" onchange="UnifiSensor.timout_set(' + deviceID + ', this.value);"> seconds</td></tr>' +
				' <tr><td>Unifi URL </td><td><input type="text" id="unifi_url" size=20 value="' +  url + '" onchange="UnifiSensor.url_set(' + deviceID + ', this.value);"></td></tr>' +
				' <tr><td>Unifi Username </td><td><input type="text" id="unifi_user" size=16 value="' +  username + '" onchange="UnifiSensor.username_set(' + deviceID + ', this.value);"></td></tr>' +
				' <tr><td>Unifi Password </td><td><input type="text" id="unifi_passwd" size=16 value="' +  passwd + '" onchange="UnifiSensor.passwd_set(' + deviceID + ', this.value);"></td></tr>' +
				' <tr><td>Unifi Site </td><td><input type="text" id="unifi_site" size=16 value="' +  site + '" onchange="UnifiSensor.site_set(' + deviceID + ', this.value);"></td></tr>' +
				'</table>';
			html += '<input type="button" value="Save and Reload" onClick="UnifiSensor.ReloadEngine()"/>';
			api.setCpanelContent(html);
		} catch (e) {
            Utils.logError('Error in UnifiSensor.UnifiSensorSettings(): ' + e);
        }
	}
	
	
	
	function handleRowChange( ev ) {
		var el = jQuery( ev.currentTarget );
		var row = el.closest( 'div.row' );
		var vsdevice = parseInt( row.attr( 'id' ).replace( /^d/, "" ) );
		var device = parseInt( jQuery( 'select.devicemenu', row ).val() );
		var macaddress = jQuery( 'input#macaddress', row ).val() || "";

		/* First the device */
		api.setDeviceStateVariablePersistent( vsdevice, unifisensor_svs, "MACAddress", macaddress,
		{
			'onSuccess': function() {
				jQuery.ajax({
					url: api.getDataRequestURL(),
					data: {
						id: "lr_UnifiSensor",
						action: 'restart',
						device: vsdevice
					},
					dataType: "json",
					timeout: 5000
				}).fail( function( jqXHR, textStatus, errorThrown ) {
					console.log( "restart failed, maybe try again later" );
				}).always( function() {
				});
			},
			'onFailure' : function() {
				alert('There was a problem saving the configuration. Vera/Luup may have been restarting. Please try again in 5-10 seconds.');
			}
		});

	}

	function waitForReload() {
		jQuery.ajax({
			url: api.getDataRequestURL(),
			data: {
				id: "lr_UnifiSensor",
				action: "alive",
				r: Math.random()
			},
			dataType: "json",
			timeout: 2000
		}).done( function( data, statusText, jqXHR ) {
			if ( data && data.alive ) {
				jQuery( 'div#vs-content div#notice' ).html( "" );
				redrawChildren();
			} else {
				jQuery( 'div#vs-content div#notice' ).append( "&ndash;" );
				setTimeout( waitForReload, 3000 );
			}
		}).fail( function( jqXHR, textStatus, errorThrown ) {
			jQuery( 'div#vs-content div#notice' ).append( "&bull;" );
			setTimeout( waitForReload, 3000 );
		});
	}
	
	function handleAddChildClick( ev ) {
		var el = jQuery( ev.currentTarget );
		var row = el.closest( 'div.row' );
		api.performActionOnDevice( api.getCpanelDeviceId(), unifisensor_svs, "AddChild", {
			onSuccess: function( xhr ) {
				el.prop( 'disabled', true );
				jQuery( 'div#notice', row ).text("Creating child... please wait while Luup reloads...");
				setTimeout( waitForReload, 5000 );
			},
			onFailure: function( xhr ) {
				alert( "An error occurred. Try again in a moment; Vera may be busy." );
			}
		} );
	}
	
	function handleNameClick( ev ) {
		var $el = jQuery( ev.currentTarget );
		var id = $el.closest( 'div.row' ).attr( 'id' ).replace( /^d/, "" );
		var dev = parseInt( id );
		if ( isNaN( dev ) ) return;
		var devobj = api.getDeviceObject( dev );
		if ( devobj ) {
			var txt = devobj.name;
			while ( true ) {
				txt = prompt( 'Enter new sensor name:', txt );
				if ( txt == null ) break;
				if ( txt.match( /^.+$/ ) ) {
					/* This causes a Luup reload, so don't do it this way. We have our own way. */
					/* api.setDeviceProperty( dev, 'name', txt, { persistent: true } ); */
					api.performActionOnDevice( devobj.id_parent, unifisensor_svs, "SetSensorName", { actionArguments: { DeviceNum: dev, NewName: txt } });
					$el.text( txt );
					break;
				}
			}
		}
	}
	
	function localISOTime( t ) {
		var dt = new Date();
		dt.setTime( t );

		function fill( s, n, c ) {
			while ( s.length < n ) s = ( c || '0' ) + s;
			return s;
		}

		return String( dt.getFullYear() ) + '-' +
			fill( String( dt.getMonth()+1 ), 2 ) + '-' +
			fill( String( dt.getDate() ), 2 ) + ' ' +
			fill( String( dt.getHours() ), 2 ) + ':' +
			fill( String( dt.getMinutes() ), 2 ) + ':' +
			fill( String( dt.getSeconds() ), 2 );
	}
	
	function updateCurrentValues() {
		jQuery( 'div#vs-content div.vssensor' ).each( function() {
			var $row = jQuery( this );
			var col = jQuery( 'div.vswhen', $row );
			var vs = parseInt( $row.attr( 'id' ).replace( /^d/, "" ) );

			var when = parseInt( api.getDeviceStateVariable( vs, unifisensor_svs, "LastSeen" ) );
			var str;
			if ( ! isNaN( when ) ) {
				str = localISOTime( when * 1000 );
			} else {
				str = 'never seen';
			}
			col.html( str );

		});
	}

	function onUIDeviceStatusChanged() {
		updateCurrentValues();
	}
	
	function redrawChildren() {
		var myDevice = api.getCpanelDeviceId();
		var devices = api.cloneObject( api.getListOfDevices() );
		devices.sort( function( a, b ) {
			if ( (a.name || "").toLowerCase() == (b.name || "").toLowerCase() ) {
				return 0;
			}
			return (a.name || "").toLowerCase() < (b.name || "").toLowerCase() ? -1 : 1;
		});

		var container = jQuery( 'div#vs-content' ).empty();
		var count = 0;
		var row = jQuery( '<div class="row vshead" />' );
		row.append( '<div class="col-xs-12 col-sm-3 col-lg-2">Virtual Sensor</div>' );
		row.append( '<div class="col-xs-12 col-sm-7 col-lg-7">MAC Address</div>' );
		row.append( '<div class="col-xs-12 col-sm-2 col-lg-3">Last Update</div>' );
		container.append( row );
		for ( ix=0; ix<(devices || []).length; ix++ ) {
			var v = devices[ix];
			if ( v.id_parent == myDevice ) {
				row = jQuery( '<div class="row vssensor" />' );
				row.attr( 'id', "d" + String(v.id) );

				var col = jQuery( '<div class="col-xs-12 col-sm-3 col-lg-2 vsname" />' );
				row.append( col.text( v.name + ' (#' + v.id + ')' ) );

				/* Device menu for row */
				col = jQuery( '<div class="col-xs-12 col-sm-7 col-lg-7 form-inline" />' );
				/* Textbox for MAC address */
				col.append( '<label>MAC: <input id="macaddress" class="form-control"></label>' );
				jQuery( 'input#macaddress', col ).val( api.getDeviceStateVariable( v.id, unifisensor_svs, "MACAddress" ) || "" )
					.on( 'change.vsensor', handleRowChange );


				row.append( col );

				col = jQuery( '<div class="col-xs-12 col-sm-2 col-lg-3 vswhen" />' );
				row.append( col );

				jQuery( 'div.vsname', row ).on( 'click.vsensor', handleNameClick );

				container.append( row );
				++count;
			}
		}

		var enab = 0 !== parseInt( api.getDeviceStateVariable( myDevice, unifisensor_svs, "Enabled" ) || "0" );
		if ( !enab ) {
			container.append( '<div class="row"><div class="col-xs-12 col-sm-12"><span style="color: red;">NOTE: This instance is currently disabled--virtual sensor values do not update when the parent instance is disabled.</span></div></div>' );
		} else {
			row = jQuery( '<div class="row vscontrol" />' );
			var br = jQuery( '<div class="col-xs-12 col-sm-12 form-inline" />' );
			br.append( '<button id="addchild" class="btn btn-md btn-primary">Create New Virtual Sensor</button>' );
			br.append( '<div id="notice" class="vsensor-notice" />' );
			container.append( row.append( br ) );
			jQuery( 'button#addchild', container ).on( 'click.unifisensor', handleAddChildClick );
		}

		updateCurrentValues();
		api.registerEventHandler( 'on_ui_deviceStatusChanged', UnifiSensor, 'onUIDeviceStatusChanged' );

	}
	
	
	function doVirtualSensors(deviceID) {
		try {
			initPlugin();

			var html = '<style>';
			html += 'div#vs-content .vshead { background-color: #428bca; color: #fff; min-height: 42px; font-size: 16px; font-weight: bold; line-height: 1.5em; padding: 8px 0; }';
			html += 'div#vs-content div.vssensor { border-top: 1px solid #428bca; padding: 8px 0; }';
			html += 'div#vs-content label { font-weight: normal; display: inline-block; }';
			html += 'div#vs-content div.vscontrol { border-top: 1px solid black; padding: 8px 0; }';
			html += 'div#vs-content div.vsensor-notice { padding: 8px 0px; font-weight: bold; font-size: 125%; }';
			html += '</style>';
			jQuery( 'head' ).append( html );

			html = '<div id="vs-content" />';
			//html += footer();
			api.setCpanelContent( html );

			redrawChildren();
		}
		catch (e)
		{
			alert(String(e));
			Utils.logError('Error in UnifiSensor.doVirtualSensors(): ' + e);
		}
	}
	
	///////////////////////////
	myModule = {
		uuid: uuid,
		init : init,
		onUIDeviceStatusChanged: onUIDeviceStatusChanged,
		onBeforeCpanelClose: onBeforeCpanelClose,
		UnifiSensorSettings : UnifiSensorSettings,
		doVirtualSensors : doVirtualSensors,
		period_set: period_set,
		timeout_set: timeout_set,
		ReloadEngine: ReloadEngine,
		url_set: url_set,
		username_set: username_set,
		passwd_set: passwd_set,
		site_set: site_set
	};

	return myModule;

})(api);


//*****************************************************************************
// Extension of the Array object:
//  indexOf : return the index of a given element or -1 if it doesn't exist
//*****************************************************************************
if (!Array.prototype.indexOf) {
    Array.prototype.indexOf = function (element /*, from*/) {
        var len = this.length;

        var from = Number(arguments[1]) || 0;
        if (from < 0) {
            from += len;
        }

        for (; from < len; from++) {
            if (from in this && this[from] === element) {
                return from;
            }
        }
        return -1;
    };
}