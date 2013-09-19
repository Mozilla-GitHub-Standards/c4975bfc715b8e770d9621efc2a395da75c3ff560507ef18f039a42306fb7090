#!/bin/sh

cd /home/app

# Run the load-agent command via circus.

cat >> circus.ini << EOF

[watcher:loads-agent]
working_dir=/home/app/loads
cmd=./bin/loads-agent --broker tcp://loads.{"Ref":"DNSPrefix"}.lcip.org:7780
numprocesses = 1
stdout_stream.class = FileStream
stdout_stream.filename = /home/app/loads/circus.stdout.log
stdout_stream.refresh_time = 0.5
stdout_stream.max_bytes = 1073741824
stdout_stream.backup_count = 3
stderr_stream.class = StdoutStream
stderr_stream.class = FileStream
stderr_stream.filename = /home/app/loads/circus.stderr.log
stderr_stream.refresh_time = 0.5
stderr_stream.max_bytes = 1073741824
stderr_stream.backup_count = 3

EOF

# Install picl-idp repo so that we can run its loadtests.
# This is a pretty awful hack, need better support in loads for
# customizing the agent.

cd /home/app
$UDO git clone https://github.com/mozilla/picl-idp
cd ./picl-idp
git checkout loadtest-tweaks
$UDO npm install
cd ./loadtest
make build