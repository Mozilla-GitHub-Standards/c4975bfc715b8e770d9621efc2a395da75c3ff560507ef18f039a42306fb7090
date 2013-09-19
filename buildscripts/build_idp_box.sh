#!/bin/sh
#
# Build a webhead node for picl-idp.
#
# This script builds a custom machine setup for running the picl-idp nodejs
# application.  It's running on top of a stack more familiar to the services
# team than the black-box of the awsbox AMI.

set -e

UDO="sudo -u app"

YUM="yum --assumeyes --enablerepo=epel"
$YUM install nodejs npm gmp gmp-devel

# Grab and build the latest master of picl-idp.

cd /home/app
$UDO git clone https://github.com/mozilla/picl-idp
cd picl-idp
$UDO npm install

cat >> config/awsboxen.json << EOF
{
  "kvstore": {
    "cache": "memcached",
    "backend": "cassandra"
  },
  "smtp": {
    "host": "localhost",
    "port": 25,
    "secure": false
  },
  "secretKeyFile": "/home/app/picl-idp/config/secret-key.json",
  "publicKeyFile": "/home/app/picl-idp/config/public-key.json",
  "bridge": {
    "url": "http://accounts.{"Ref":"DNSPrefix"}.lcip.org"
  },
  "dev": {
    "verified": true
  }
}
EOF

# Generate signing keys.
# These need to be shared by all webheads, so we bake them into the AMI.
# XXX TODO: they'll need to be much better managed than this in production!
$UDO node ./scripts/gen_keys.js

# Write a circus config file to run the app with nodejs.

cd ../
cat >> circus.ini << EOF
[watcher:keyserver]
working_dir=/home/app/picl-idp
cmd=node bin/key_server.js
numprocesses = 1
stdout_stream.class = FileStream
stdout_stream.filename = /home/app/picl-idp/circus.stdout.log
stdout_stream.refresh_time = 0.5
stdout_stream.max_bytes = 1073741824
stdout_stream.backup_count = 3
stderr_stream.class = FileStream
stderr_stream.filename = /home/app/picl-idp/circus.stderr.log
stderr_stream.refresh_time = 0.5
stderr_stream.max_bytes = 1073741824
stderr_stream.backup_count = 3


[env:keyserver]
PORT=8000
CONFIG_FILES=/home/app/picl-idp/config/awsboxen.json,/home/app/picl-idp/config/cloud_formation.json
EOF


# Slurp the picl-idp server log into heka.

cat >> /home/app/hekad/hekad.toml << EOF
[picl-idp-log]
type = "LogfileInput"
logfile = "/home/app/picl-idp/server.log"
logger = "picl-idp"

EOF


# Configure postfix to send emails via parametereized SMTP relay.
# The default SMTPRelay is blank, meaning it sends email direct from the box.
# But you can use CloudFormation parameters to point it at e.g. Amazon SES.

$YUM install postfix
alternatives --set mta /usr/sbin/sendmail.postfix

cat >> /etc/postfix/main.cf << EOF
relayhost = {"Ref":"SMTPRelay"}
smtp_sasl_auth_enable = yes
smtp_sasl_security_options = noanonymous
smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd
smtp_use_tls = yes
smtp_tls_security_level = encrypt
smtp_tls_note_starttls_offer = yes
EOF

# Create placeholder for the SES relay credentials.
cat >> /etc/postfix/sasl_passwd << EOF
email-smtp.us-east-1.amazonaws.com:25 {"Ref":"SMTPUsername"}:{"Ref":"SMTPPassword"}
EOF
/usr/sbin/postmap /etc/postfix/sasl_passwd

service sendmail stop
chkconfig sendmail off

service postfix start
chkconfig postfix on