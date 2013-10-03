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
  - printer queues the user can use

Sessions are stored in memory only but are not automatically deleted.

Post fields:
  - hostname

returns

    {
      "device": {
        "printer_device_uri": null,
        "personal_device": false,
        "allow_guest": false,
        "kernel_version": null,
        "kernel_arguments": null,
        "preferred_server": null,
        "preferred_image": null,
        "type": "fatclient",
        "school_dn": "puavoId=9,ou=Groups,dc=edu,dc=hogwarts,dc=fi",
        "hostname": "testfat",
        "dn": "puavoId=5370,ou=Devices,ou=Hosts,dc=edu,dc=hogwarts,dc=fi",
        "vertical_refresh": null,
        "printer_queue_dns": null,
        "mac_address": "bc:5f:f4:56:59:71",
        "puavo_id": "5370",
        "boot_mode": null,
        "xrand_disable": null,
        "graphics_driver": null,
        "resolution": null
      },
      "ltsp_server": {
        "state": {
          "updated": 1380803986,
          "fqdn": "myltsp",
          "ltsp_image": "",
          "load_avg": 0.5
        },
        "school_dns": [],
        "hostname": "myltsp",
        "dn": "puavoId=5371,ou=Servers,ou=Hosts,dc=edu,dc=hogwarts,dc=fi"
      },
      "user": {
        "profile_image_link": "http://127.0.0.1:9393/v3/users/admin/profile.jpg",
        "dn": "uid=admin,o=puavo",
        "username": "admin",
        "last_name": null,
        "first_name": null,
        "email": null,
        "user_type": null,
        "puavo_id": null,
        "school_dn": null
      },
      "printer_queues": [
        {
          "remote_uri": "ipp://boot.hogwarts.opinsys.net/printers/Kirkonkyla-Luokka-202",
          "dn": "puavoId=19159,ou=Printers,dc=edu,dc=hogwarts,dc=fi",
          "model": "HP Color LaserJet cp2025dn pcl3, hpcups 3.12.2",
          "location": "Satun luokka",
          "type": "36876",
          "local_uri": "socket://jokk-hptulostin-202.ltsp.hogwarts.opinsys.fi",
          "description": "Kirkonkyla-Luokka-202",
          "name": "Kirkonkyla-Luokka-202",
          "server_fqdn": "boot.hogwarts.opinsys.net"
        },
        {
          "remote_uri": "ipp://boot.hogwarts.opinsys.net/printers/Kirkonkyla-Luokka-202",
          "dn": "puavoId=19159,ou=Printers,dc=edu,dc=hogwarts,dc=fi",
          "model": "HP Color LaserJet cp2025dn pcl3, hpcups 3.12.2",
          "location": "Satun luokka",
          "type": "36876",
          "local_uri": "socket://jokk-hptulostin-202.ltsp.hogwarts.opinsys.fi",
          "description": "Kirkonkyla-Luokka-202",
          "name": "Kirkonkyla-Luokka-202",
          "server_fqdn": "boot.hogwarts.opinsys.net"
        }
      ],
      "created": 1380803997,
      "uuid": "d5eba820-0e56-0131-84e4-52540007db7f"
    }


### Examples

For authenticated users with kerberos:

    curl --data hostname=$(hostname) --negotiate --delegation always --user : $(puavo-resolve-api-server)/v3/sessions

For guests

    curl --data hostname=$(hostname) --header 'Authorization: Bootserver' $(puavo-resolve-api-server)/v3/sessions

## GET /v3/sessions

Return all sessions.

## GET /v3/sessions/:uuid

Return session by uuid.

## DELETE /v3/sessions/:uuid

Delete session by uuid.

### Examples

    curl --request DELETE $(puavo-resolve-api-server)/v3/sessions/<uuid from post>

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

