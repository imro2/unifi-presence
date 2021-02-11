**This is an alpha version. It will undergo a rename to both files and device ids.** 
**Only minimal changes were made to the readme to make it less confusing given the different functionality and configuration**

# unifi-sensor
Vera Plugin for Presence Detection using a Unifi Controller

This is based on the unifi-Sensor plugin by BlueSmurf/livehouse-automation. It also heavily borrows from rigpapa's VirtualSensor plugin.

My first attempt was just to replace the shell script for lua code, but then I got carried away and redesigned the plugin. It now logs in and stays logged in. It has one main device that represents connection to the Unifi controller and then as many child devices as you want monitor for presence. It requires a MAC address, where the original plugin could use device name or IP. Instead of getting a list of all devices, it checks each MAC separately and only retrieves information for that device. This way it does not matter how may devices are in your Unifi site.

Introduction:

The Unifi Sensor operates in much the same way as the Ping Sensor on which it's based. The difference is it queries your Unifi Controller and looks for a MAC - if that address is found, the sensor trips. This method means you can detect the presence of devices that don't respond to ping, or go into a deep sleep state (eg Galaxy S smartphones) and ignores network pings.

Installation:

Download the plugin files.Copy these files to Vera using Apps->Develop Apps->Luup Files

- D_UnifiSensor.json
- D_UnifiSensor.xml
- I_UnifiSensor.xml
- S_UnifiSensor.xml
- J_UnifiSensor.js
- L_UnifiSensor.lua

Once the files are in place, create a new device in Apps->Develop Apps->Create Device. Fill in following text boxes:

Upnp Device Filename: D_UnifiSensor.xml 
Upnp Implementation Filename: I_UnifiSensor.xml

**You'll need to reload the Luup Engine and refresh your browser before the device will appear in the UI.**

Configuration:

Create a separate **local** user on your Unifi Controller for Vera to use, do not use your main Admin account. I had problems creating local user in the new UI, but temporarily switching to the old UI let me do it.

In the UI for the device, go into the Settings tab and provide the information needed - it should be self-explanatory.

After that go to Virtual Sensors tab and add new child devices using the Create Virtual Sensor button. When you click the button, wait until the new device appears in the list above. Once there, fill in a MAC address in the text box and possibly rename the device by clicking on its name. Wait a minute for first poll to occur after which you should see a time stamp under Last Update.

The parent device icon will show Green if you have at least one virtual sensor with a MAC address configured and the sensor was able to successfully authenticate with the controller.

Future:

- rename files and plugin to make it unique from livehouse-automation
