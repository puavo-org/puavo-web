# Remote recovery

A device that failed to unlock its encrypted disk gets its recovery key
back. An organisation owner opens a recovery of the device in Puavo Web
and tells the person at the device its code. The device joins with the
code and its request, and puavo-rest signs the opening as an approval.
A key service fetches queued requests and answers each with a result
for the device. The routes are in ROUTES.md.

```
device ──▶ puavo-rest ◀── Puavo Web ◀── owner
               ▲
               └── key service
```

## Configuration

In `/etc/puavo-rest.yml`. The routes exist only when this is set.

```yaml
recovery:
  approval_issuer: puavo-rest              # "iss" of the approvals
  approval_key_id: recovery-approval-2026  # "kid" of the approvals
  approval_private_key: /etc/puavo-rest.d/recovery_approval_private_key.pem
```

The key is an EC P 256 key used for nothing else. The key service gets
its public half. The key service signs in with an OAuth 2 client that is
allowed the scope `puavo.recovery.kps` and the endpoints
`/v3/recovery/queue` and `/v3/recovery/requests/:id/result`.

Recoveries live in Redis and expire. A request may wait days for its
device, so Redis must keep its data across restarts.

## States

```
open ──join──▶ queued ──result──▶ done
  ▲               │  └──error──▶ failed
  └────cancel─────┘
```

A cancel from failed also opens the recovery again. A device has one
recovery at a time. A recovery expires a fixed time after its opening,
in every state, and its approval and result with it. A queued request
waits until its result, its cancel or that expiry, also while its device
is off. Too many wrong codes close the recovery, in every state. An
ended recovery is gone, and every call on it answers 404.
