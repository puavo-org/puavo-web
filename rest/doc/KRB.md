# KERBEROS GSSAPI SPNEGO WTF

On LDAP master do

    # kadmin.local -r <REALM> -q "addprinc -randkey HTTP/<bootserver fqdn>"

and on bootserver

    # kadmin.local -q "ktadd -norandkey -k /etc/puavo/puavo-rest.keytab HTTP/$(hostname -f)"
    # chgrp puavo /etc/puavo/puavo-rest.keytab
    # chmod g+r /etc/puavo/puavo-rest.keytab

