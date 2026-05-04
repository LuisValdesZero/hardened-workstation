#!/bin.bash

it should download DNSCrypt-proxy and install into ~/applications/dnscrypt-proxy

https://github.com/DNSCrypt/dnscrypt-proxy/releases/download/2.1.15/dnscrypt-proxy-linux_x86_64-2.1.15.tar.gz

then copy /home/engineer/workspace/hardened-workstation/common/dnscrypt-proxy.toml to ~/applications/dnscrypt-proxy

└─$ ~/applications/dnscrypt-proxy/dnscrypt-proxy --config dnscrypt-proxy.toml --service install
[2026-05-04 12:02:00] [FATAL] Failed to install DNSCrypt client proxy: Init already exists: /etc/systemd/system/dnscrypt-proxy.service
