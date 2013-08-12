# Single Sign-On

Service is located at `/v3/sso`.

## Client services

For now client services must be configured to `/etc/puavo-rest.yml`

```yaml
sso:
  "someservice.example.com": "shared secret"
  "anotherservice.example.com": "another shared secret"
```

## Usage

Client service requesting authentication must redirect user to
`/v3/sso` with `return_to` query value which determines where user
is redirected back. Hostname of the `return_to` url must match with above
configuration.

Example

    https://organisation.opinsys.net/v3/sso?return_to=http%3A%2F%2Fexample.com

User is authenticated on `/v3/sso` using a Kerberos ticket or by asking
user credentials using a HTML form. On successful authentication user is
redirected back to `return_to` url with a [JSON Web Token][jwt] in the query
string.

Example

    http://example.com/?jwt=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJ1c2VyIjoiZXBlbGkiLCJpYXQiOjEzNzQyMzk4NjZ9.6U4g2el8-zOuCmbBj_TvTZ6xCsa8tXeOaafKJyyDyE0

See [node-jwtsso][] for [Express] middleware implementation.

[jwt]: http://tools.ietf.org/html/draft-jones-json-web-token
[node-jwtsso]: https://github.com/opinsys/node-jwtsso
[Express]: http://expressjs.com/
