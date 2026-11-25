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

## GET /v3/users/:username

Get user information

### Returns

    {
      "email": "olli.oppilas@example.com",
      "first_name": "Olli",
      "last_name": "Oppilas",
      "username": "oppilas",
      "dn": "puavoId=202228,ou=People,dc=edu,dc=kehitys,dc=net"
    }

## GET /v3/users/_search

### Query strings

  - `q`: keywords to search with. Separate with a `+` or space

### Returns

Array of users objects

## GET /v3/whoami

Like previous but for the authenticated uses

## GET /v3/users/:username/profile.jpg

Get profile image for the user

### Returns

    (Content-Type: image/jpeg)

# Devices

## GET /v3/devices/:hostname

Get device information by device hostname.

### Returns

    {
      "kernel_arguments": "lol",
      "kernel_version": "0.1",
      "image": "myimage",
      "dn": "puavoId=10,ou=Devices,ou=Hosts,dc=edu,dc=hogwarts,dc=net",
      "puavo_id": "10",
      "mac_address": "08:00:27:88:0c:a6",
      "type": "laptop",
      "school": "puavoId=1,ou=Groups,dc=edu,dc=hogwarts,dc=net",
      "hostname": "testlaptop",
      "boot_mode": "netboot",
      "xrand_disable": false,
      "allow_guest": true,
      "personal_device": true,
      "preferred_language": "en"
    }

# External files

## GET /v3/:organisation/external_files

Get metadata list of external files.


### Returns

    [
     {
       "name": <filename>,
       "data_hash": <sha1 checksum of the file>
     },
     ...
    ]

## GET /v3/devices/_search

### Query strings

  - `q`: keywords to search with. Separate with a `+` or space

### Returns

Array of device objects

## GET /v3/:organisation/external_files/:name/metadata


Get metadata for external file.

### Returns

    {
      "name": <filename>,
      "data_hash": <sha1 checksum of the file>
    }

## GET /v3/:organisation/external_files/:name

Get file contents.

### Returns

    (Content-Type: application/octet-stream))

# Sessions

## POST /v3/sessions

Create new session.  Sessions are stored in memory only
but are not automatically deleted.

### Post fields

  - hostname (optional)
    - Device hostname

### Returns

    {
      "preferred_language": "en",
      "device": {
        "printer_device_uri": null,
        "personal_device": false,
        "allow_guest": false,
        "kernel_version": null,
        "kernel_arguments": null,
        "preferred_server": null,
        "preferred_image": null,
        "type": "fatclient",
        "school_dn": "puavoId=9,ou=Groups,dc=edu,dc=hogwarts,dc=net",
        "hostname": "testfat",
        "dn": "puavoId=5370,ou=Devices,ou=Hosts,dc=edu,dc=hogwarts,dc=net",
        "printer_queue_dns": null,
        "mac_address": "bc:5f:f4:56:59:71",
        "puavo_id": "5370",
        "boot_mode": null,
        "xrand_disable": null,
        "resolution": null
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
          "remote_uri": "ipp://boot.hogwarts.puavo.net/printers/Kirkonkyla-Luokka-202",
          "dn": "puavoId=19159,ou=Printers,dc=edu,dc=hogwarts,dc=net",
          "model": "HP Color LaserJet cp2025dn pcl3, hpcups 3.12.2",
          "location": "Satun luokka",
          "type": "36876",
          "local_uri": "socket://jokk-hptulostin-202.ltsp.hogwarts.puavo.net",
          "description": "Kirkonkyla-Luokka-202",
          "name": "Kirkonkyla-Luokka-202",
          "server_fqdn": "boot.hogwarts.puavo.net"
        },
        {
          "remote_uri": "ipp://boot.hogwarts.puavo.net/printers/Kirkonkyla-Luokka-202",
          "dn": "puavoId=19159,ou=Printers,dc=edu,dc=hogwarts,dc=net",
          "model": "HP Color LaserJet cp2025dn pcl3, hpcups 3.12.2",
          "location": "Satun luokka",
          "type": "36876",
          "local_uri": "socket://jokk-hptulostin-202.ltsp.hogwarts.puavo.net",
          "description": "Kirkonkyla-Luokka-202",
          "name": "Kirkonkyla-Luokka-202",
          "server_fqdn": "boot.hogwarts.puavo.net"
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

## GET /v3/devices/:hostname/wlan_networks

Configured client WLAN networks.

### Returns

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

### Returns

    [
      {
        "password": "",
        "wlan_ap": true,
        "type": "open",
        "ssid": "orgwlan"
      }
    ]

# Organisations


## GET /v3/current_organisation

Return current organisation

### Returns

    {
      "auto_power_off_hour": null,
      "auto_power_on_hour": null,
      "base": "dc=edu,dc=hogwarts,dc=net",
      "samba_domain_name": "EDUHOGWARTS",
      "domain": "hogwarts.puavo.net",
      "puppet_host": "hogwarts.puppet.puavo.net",
      "owners": [
        4
      ],
      "preferred_language": null,
      "name": "hogwarts",
      "auto_power_off_mode": null
    }

## GET /v3/organisations/:domain

Return organisation info by domain

### Returns

    (see prev)

## GET /v3/organisations

Return all organisations. On bootservers this will return only the organisation
the bootserver belongs to.

### Returns

    (Array)

## GET /v3/boot_configurations/:mac_address

Get boot configuration for given mac address in grub format

## POST /v3/:hostname/boot_done

Log that boot has been done.

### Example

    curl -X POST  --header 'Authorization: Bootserver' $(puavo-resolve-api-server)/v3/devices/$(hostname)


## GET /v3/device_images

Return array of unique device images that are configured to the organisation,
schools or devices.

### Authentication

Basic auth or boot server auth

### Query strings

  - `boot_server`/`boot_server[]`: Boot server hostname
    - to limit the search to given boot servers

### Example

    curl --header 'Authorization: Bootserver' $(puavo-resolve-api-server)/v3/device_images?boot_server[]=boot1&boot_server[]=boot2

### Returns

    (Array)

# Remote recovery

The routes exist when `recovery` is configured, see RECOVERY.md. Binary
values are base64. `expires_at` is the end of the recovery, the same in
every state. Deletes answer 200. Errors are `RecoveryRequestNotFound`,
`CodeInUse`, `WrongState`, `UnsupportedDeviceType`,
`DeviceWithoutSerialNumber` and the usual ones.

## POST /v3/devices/:hostname/recovery

An organisation owner opens a recovery of the device. Basic auth. An
earlier recovery of the device ends. Returns `code`, `serial_number`,
`state` and `expires_at`. A device type without remote recovery answers
`UnsupportedDeviceType`. Laptops and boot servers have it.

## GET /v3/devices/:hostname/recovery

An organisation owner looks at the recovery of the device. Basic auth.
Returns `state`, `serial_number`, `opened_by`, `created_at`,
`expires_at` and `wrong_codes`, the `code` while open, and
`queue_position` while queued.

## DELETE /v3/devices/:hostname/recovery

An organisation owner closes the recovery of the device. Basic auth.

## POST /v3/recovery/requests

The device joins the recovery opened for it. No authentication.

Body: `organisation_id`, `serial_number`, `code`, `bundle` and
`return_public_key`. Other fields are ignored.

Returns `id`, `state`, `expires_at` and `poll_seconds`, with 201. The
id is the device's secret. A wrong code answers as no recovery and
counts against the recovery in every state. The first join wins: a
right code while a request is queued answers `CodeInUse`. The same
join sent again, with the same bundle and return key, answers 200 with
the queued request.

## GET /v3/recovery/requests/:id

The device polls its request. Returns `id`, `state`, `expires_at`,
`poll_seconds`, `approval`, and `result` or `error` by state. A queued
request also has `queue_position`. `poll_seconds` is the queue position
in seconds, within a minimum and a maximum.

## DELETE /v3/recovery/requests/:id

The device ends the recovery after its result. Otherwise it cancels its
request, which opens the recovery again.

## GET /v3/recovery/queue

The key service fetches queued requests, the earliest opened recovery
first. OAuth 2 token with the scope `puavo.recovery.kps`. Returns
`requests` with `id`, `organisation_id`, `serial_number`, `bundle`,
`return_public_key` and `approval`.

## PUT /v3/recovery/requests/:id/result

The key service answers a queued request. OAuth 2 token with the scope
`puavo.recovery.kps`. Body: either `result`, or `error` with `code` and
`message`. Returns `state`.
