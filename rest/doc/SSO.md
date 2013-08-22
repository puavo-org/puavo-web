#  Single Sign-On configuration in puavo-rest

For now client services must be configured to `/etc/puavo-rest.yml`

```yaml
sso:
  "someservice.example.com":
    name: Some Service
    secret: "shared secret"
  "anotherservice.example.com":
    name: Another Service
    secret: "another shared secret"
```
