# PuavoRest

standalone JSON API server for boot servers and public web

installation from opinsys-debs https://github.com/opinsys/opinsys-debs/tree/master/packages/puavo-users

## api routes

all routes return json documents unless mentioned otherwise

## devices

### GET /v3/devices/:hostname

get device information by device hostname

return

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

## external files

### GET /v3/:organisation/external_files

get metadata list of external files


return

    [
     {
       "name": <filename>,
       "data_hash": <sha1 checksum of the file>
     },
     ...
    ]

### GET /v3/:organisation/external_files/:name/metadata


get metadata for external file

return

    {
      "name": <filename>,
      "data_hash": <sha1 checksum of the file>
    }

### GET /v3/:organisation/external_files/:name

get file contents

return

    (Content-Type: application/octet-stream))

## ltsp servers

### GET /v3/ltsp_servers

get metadata for all ltsp servers

return

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


### GET /v3/ltsp_servers/_most_idle

*DEPRECATED! use `post /v3/sessions`*

get the most idle ltsp server


### GET /v3/ltsp_servers/:hostname

get ltsp server metadata by hostname

return

    {
      "dn": "puavoId=11,ou=Servers,ou=Hosts,dc=edu,dc=hogwarts,dc=fi",
      "hostname": "ltspserver1",
      "updated": "2013-06-04 16:04:08 +0300",
      "ltsp_image": "test-image",
      "load_avg": 0.1
    },

### PUT /v3/ltsp_servers/:hostname

set ltsp server status

post fields:
  - ltsp_image
  - load_avg
  - cpu_count (optional)

### POST /v3/sessions

create new thin client session

will return the most appropriate ltsp server depending on
  - preferred device image attribute on device, school or organisation
  - preferred server attribute on device
  - preferred school attribute on ltsp server
  - ltsp server load
  - details https://github.com/opinsys/puavo-users/blob/master/rest/resources/sessions.rb#L33

sessions are stored in memory only but are not automatically deleted

post fields:
  - hostname

return

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

### GET /v3/sessions

return all sessions

### GET /v3/sessions/:uuid

return session by uuid

### DELETE /v3/sessions/:uuid

delete session by uuid

### GET /v3/devices/:hostname/wlan_networks

configured client wlan networks

return

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

### GET /v3/devices/:hostname/wlan_hotspot_configurations

get wlan hotspot configurations

return

    [
      {
        "password": "",
        "wlan_ap": true,
        "type": "open",
        "ssid": "orgwlan"
      }
    ]

