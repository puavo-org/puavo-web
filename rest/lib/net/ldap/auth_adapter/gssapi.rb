### This software is from https://github.com/syskill/ruby-net-ldap-gssapi
### and slightly adapted for Puavo Web by Opinsys.
### The original copyright notice:
#
# The MIT License (MIT)
#
# Copyright (c) 2015-2018 Smartling, Inc.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

require 'gssapi'
require 'net/ldap'

module Net
  class LDAP
    class GSSAPIError < Error; end

    class AuthAdapter
      class GSSAPI < Net::LDAP::AuthAdapter
        #--
        # Required parameters: :hostname
        # Optional parameters: :servicename
        #
        # Hostname must be a fully-qualified domain name.
        #
        # Service name defaults to "ldap", which is almost certainly what you want.
        #++
        def bind(auth)
          host, svc = [auth[:hostname], auth[:servicename] || "ldap"]
          creds = auth[:credentials]
          raise Net::LDAP::BindingInformationInvalidError, "Invalid binding information" unless (host && svc)

          gsscli = ::GSSAPI::Simple.new(host, svc)
          context_established = nil
          challenge_response = proc do |challenge|
            if !context_established
              resp = gsscli.init_context(challenge)
              if resp.equal?(true)
                context_established = true
              elsif !resp || resp.empty?
                raise Net::LDAP::GSSAPIError, "Failed to establish GSSAPI security context"
              end
              resp
            else
              # After the security context has been established, the LDAP server will
              # offer to negotiate the security strength factor (SSF) and maximum
              # output size. We request an SSF of 0, i.e. no protection (integrity
              # and confidentiality protections aren't implemented here, yet) and no
              # size limit.
              #
              # N.b. your LDAP server may reject the bind request with an error
              # message like "protocol violation: client requested invalid layer."
              # That means that it is configured to require stronger protection.
              gsscli.wrap_message("\x01\xff\xff\xff".force_encoding("binary"), false)
            end
          end

          Net::LDAP::AuthAdapter::Sasl.new(@connection).
            bind(method: :sasl, mechanism: "GSSAPI",
                 initial_credential: gsscli.init_context(nil, credentials: creds),
                 challenge_response: challenge_response)
        end
      end
    end
  end
end

Net::LDAP::AuthAdapter.register(:gssapi, Net::LDAP::AuthAdapter::GSSAPI)
