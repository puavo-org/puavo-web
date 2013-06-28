
# API Routes

All routes return json documents unless mentioned otherwise.

## Examples

Basic usage

    curl $(puavo-resolve-api-server)/v3/devices/$(hostname)

displays information of the current device

Usage with kerberos:

    curl --negotiate --delegation always --user : $(puavo-resolve-api-server)/v3/users/$(whoami)

Option `--user :` is required to activate the authentication code properly in
curl for some reason.

# Users

## GET /v3/users

Get list of all user data

returns

    [
      <user object, see next>,
      ...
    ]

## GET /v3/users/:username

Get user information

returns

    {
      "email": "olli.oppilas@example.com",
      "first_name": "Olli",
      "last_name": "Oppilas",
      "username": "oppilas",
      "dn": "puavoId=202228,ou=People,dc=edu,dc=kehitys,dc=fi"
    }

## GET /v3/whoami

Like previous but for the authenticated uses

## GET /v3/users/:username/profile.jpg

Get profile image for the user

returns

    (Content-Type: image/jpeg)

# Devices

## GET /v3/devices/:hostname

Get device information by device hostname.

returns

    {
      "kernel_arguments": "lol",
      "kernel_version": "0.1",
      "vertical_refresh": "2",
      "resolution": "320x240",
      "graphics_driver": "nvidia",
      "image": "myimage",
      "dn": "puavoId=10,ou=Devices,ou=Hosts,dc=edu,dc=hogwarts,dc=fi",
      "puavo_id": "10",
      "mac_address": "08:00:27:88:0c:a6",
      "type": "thinclient",
      "school": "puavoId=1,ou=Groups,dc=edu,dc=hogwarts,dc=fi",
      "hostname": "testthin",
      "boot_mode": "netboot",
      "xrand_disable": "FALSE",
      "allow_guest": "FALSE",
      "personal_device": "TRUE"
    }

# External files

## GET /v3/:organisation/external_files

Get metadata list of external files.


returns

    [
     {
       "name": <filename>,
       "data_hash": <sha1 checksum of the file>
     },
     ...
    ]

## GET /v3/:organisation/external_files/:name/metadata


Get metadata for external file.

returns

    {
      "name": <filename>,
      "data_hash": <sha1 checksum of the file>
    }

## GET /v3/:organisation/external_files/:name

Get file contents.

returns

    (Content-Type: application/octet-stream))

# LTSP servers

## GET /v3/ltsp_servers

Get metadata for all ltsp servers.

returns

    [
      {
        "dn": "puavoId=11,ou=Servers,ou=Hosts,dc=edu,dc=hogwarts,dc=fi",
        "hostname": "ltspserver1",
        "updated": "2013-06-04 16:04:08 +0300",
        "ltsp_image": "test-image",
        "load_avg": 0.1
      },
      ...
    ]


## GET /v3/ltsp_servers/_most_idle

*DEPRECATED! use `post /v3/sessions`*

Get the most idle ltsp server.


## GET /v3/ltsp_servers/:hostname

Get ltsp server metadata by hostname.

returns

    {
      "dn": "puavoId=11,ou=Servers,ou=Hosts,dc=edu,dc=hogwarts,dc=fi",
      "hostname": "ltspserver1",
      "updated": "2013-06-04 16:04:08 +0300",
      "ltsp_image": "test-image",
      "load_avg": 0.1
    },

## PUT /v3/ltsp_servers/:hostname

Set LTSP server status.

Post fields:
  - ltsp_image
  - load_avg
  - cpu_count (optional)

## POST /v3/sessions

Create new thin client session.

Will return the most appropriate ltsp server depending on
  - preferred device image attribute on device, school or organisation
  - preferred server attribute on device
  - preferred school attribute on ltsp server
  - ltsp server load
  - details https://github.com/opinsys/puavo-users/blob/master/rest/resources/sessions.rb#L33

Sessions are stored in memory only but are not automatically deleted.

Post fields:
  - hostname

returns

    {
      "created": "2013-06-06 09:54:05 +0300",
      "uuid": "cd600a50-b0a3-0130-b677-080027880ca6",
      "ltsp_server": {
        "dn": "puavoId=11,ou=Servers,ou=Hosts,dc=edu,dc=hogwarts,dc=fi",
        "hostname": "ltspserver1",
        "updated": "2013-06-06 09:54:01 +0300",
        "ltsp_image": "test-image",
        "load_avg": 0.095
      },
      "client": {
        "preferred_server": "puavoId=11,ou=Servers,ou=Hosts,dc=edu,dc=hogwarts,dc=fi,
        "preferred_image": "someimage",
        "school": "puavoId=1,ou=Groups,dc=edu,dc=hogwarts,dc=fi",
        "hostname": "testthin"
      }
    }

## GET /v3/sessions

Return all sessions.

## GET /v3/sessions/:uuid

Return session by uuid.

## DELETE /v3/sessions/:uuid

Delete session by uuid.

## GET /v3/devices/:hostname/wlan_networks

Configured client WLAN networks.

returns

    [
      {
        "password": "",
        "wlan_ap": true,
        "type": "open",
        "ssid": "orgwlan"
      },
      {
        "password": "",
        "wlan_ap": null,
        "type": "open",
        "ssid": "3rdpartywlan"
      }
    ]

## GET /v3/devices/:hostname/wlan_hotspot_configurations

Get WLAN hotspot configurations.

returns

    [
      {
        "password": "",
        "wlan_ap": true,
        "type": "open",
        "ssid": "orgwlan"
      }
    ]

# Organisations

Available only in development

## GET /v3/current_organisation

Return current organisation

returns

    {
      "auto_power_off_hour": null,
      "auto_power_on_hour": null,
      "base": "dc=edu,dc=hogwarts,dc=fi",
      "samba_domain_name": "EDUHOGWARTS",
      "domain": "hogwarts.opinsys.net",
      "puppet_host": "hogwarts.puppet.opinsys.net",
      "owners": [
        4
      ],
      "preferred_language": null,
      "name": "hogwarts",
      "auto_power_off_mode": null
    }

## GET /v3/organisations/:domain

Return organisation info by domain

returns

    (see prev)

## GET /v3/organisations

Rerturn all organisation data

returns

    (Array)

