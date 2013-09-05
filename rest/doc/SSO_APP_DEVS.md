<div class="master-docs">
This the documentation for the git master branch. For the current production
documentation please see
<a href="https://api.opinsys.fi/v3/sso/developers">https://api.opinsys.fi/v3/sso/developers</a>
</div>

# Opinsys Single Sign-On

For now to implement Opinsys SSO to a external service you must receive a
shared secret from Opinsys support (tuki aet opinsys.fi). To receive it you
must provide following:

  - Fully qualified domain name (fqdn)
    - The service must be available on this domain
  - Optionally a path prefix for the service
    - Required only if multiple external services must be served from the same
      domain with different shared secrets
  - Name and small description of the service
    - Will be displayed on the login form and admin configuration panel for
      school admins
  - Email address of the service maintainer
  - Optionally a link describing the service in more detail


Once the shared sercret is in place the external service may redirect
user's web browser to `https://api.opinsys.fi/v3/sso` with a `return_to`
query string key which determines where user is redirected back. The hostname
of the `return_to` URL must match with the fqdn provided to us.

Example redirect URL might be:

    https://api.opinsys.fi/v3/sso?return_to=http%3A%2F%2Fexample.com

When user is authenticated he/she will be redirected to the URL specified in
`return_to` query string key. The URL is augmented with a `jwt` query string
key which will contain a [JSON Web Token][jwt]. The external service is
expected to decode this token, validate it with the given shared secret and
make sure that it is not issued too long a ago or in future. The token will
contain following claims:

  - `iat`
    - Issued at. Identifies the time at which the JWT was issued as unix timestamp.
  - `jti`
    - A unique identifier for the JWT
  - `id`
    - Organisation wide unique id
  - `username`
  - `first_name`
  - `last_name`
  - `user_type`
    - TODO: list possible values
  - `email`
    - Unfortunately this is not set for all users.
  - `organisation_name`
    - Human readable organisation name.
  - `organisation_domain`
    - For example `jyvaskyla.opinsys.fi`.

## Organisation presetting

If the external service knows in advance from which organisation the user
is coming from it can make the login bit easier by specifying an additional
query string key `organisation` to the redirect URL:

    https://api.opinsys.fi/v3/sso?organisation=kehitys.opinsys.fi&return_to=http%3A%2F%2Fexample.com

Using this users don't have to manually type their organisation during login.

## Kerberos

When user is coming from a Opinsys managed desktop Kerberos will be used for
the authentication. User will not even see the Opinsys login form in this case.
He/she will be directly redirected back to `return_to` url with a `jwt` key.
The organisation presetting is ignored when Kerberos is active because the
organisation will read from the Kerberos ticket. This is enabled by default for
all external services using Opinsys SSO.

## Implementation help

  - [JSON Web Token draft][jwt]
  - Known working JSON Web Token implementations
    - For [Ruby](https://github.com/progrium/ruby-jwt)
    - For [node.js](https://npmjs.org/package/jwt-simple)
  - [Express][] middleware implementation: [node-jwtsso][]
  - Example [external service](https://github.com/opinsys/node-jwtsso/blob/master/example/app.js)


## Service activation

By default external services are not activated for all Opinsys organisations.
Each organisation or individual schools must activate the external services on
their behalf. They can do this directly from their management interface for the
external services they feel comfortable to share the above information about
the students and teachers.

[jwt]: http://tools.ietf.org/html/draft-jones-json-web-token
[node-jwtsso]: https://github.com/opinsys/node-jwtsso
[Express]: http://expressjs.com/
