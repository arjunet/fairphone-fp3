#!/bin/sh
# Start a telnet server on the new root, accessible via RNDIS

# Wait a moment for the network to settle
sleep 2

# Start telnetd on the RNDIS interface
/usr/sbin/telnetd -b 192.168.2.15:23 -l /bin/sh &

# Also try to start SSH if available
if [ -x /usr/sbin/sshd ]; then
    /usr/sbin/sshd
fi