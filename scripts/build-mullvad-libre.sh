#!/usr/bin/env bash
set -e

RUN_NUMBER=${GITHUB_RUN_NUMBER:-1}

echo "Getting latest Mullvad release..."
LATEST_TAG=$(curl -sL https://api.github.com/repos/mullvad/mullvadvpn-app/releases | jq -r '.[].tag_name | select(test("^[0-9]")) | select(contains("beta") | not)' | head -n 1)
echo "LATEST_TAG=${LATEST_TAG}"
# Remove v prefix if exists
VERSION=${LATEST_TAG#v}
echo "VERSION=${VERSION}"

echo "Downloading and extracting original .deb..."
wget -qO original.deb "https://github.com/mullvad/mullvadvpn-app/releases/download/${LATEST_TAG}/MullvadVPN-${VERSION}_amd64.deb"
mkdir pkgroot
dpkg-deb -R original.deb pkgroot

echo "Removing systemd and configuring Devuan init scripts..."
# 1. Remove systemd
rm -rf pkgroot/usr/lib/systemd
rm -rf pkgroot/etc/systemd 2>/dev/null || true

# 2. Modify control file
sed -i 's/Package: mullvad-vpn/Package: mullvad-libre/' pkgroot/DEBIAN/control

# 3. Create runit scripts
mkdir -p pkgroot/etc/sv/mullvad-daemon/log

cat << 'EOF' > pkgroot/etc/sv/mullvad-daemon/run
#!/bin/sh
MULLVAD_RESOURCE_DIR="/opt/Mullvad VPN/resources/"
export MULLVAD_RESOURCE_DIR
exec 2>&1
exec /usr/bin/mullvad-daemon -vv --disable-stdout-timestamps
EOF
chmod 0755 pkgroot/etc/sv/mullvad-daemon/run

cat << 'EOF' > pkgroot/etc/sv/mullvad-daemon/log/run
#!/bin/sh
mkdir -p /var/log/mullvad-daemon
exec svlogd -tt /var/log/mullvad-daemon
EOF
chmod 0755 pkgroot/etc/sv/mullvad-daemon/log/run

# 4. Create sysvinit script
mkdir -p pkgroot/etc/init.d
cat << 'EOF' > pkgroot/etc/init.d/mullvad-daemon
#!/bin/sh
### BEGIN INIT INFO
# Provides:          mullvad-daemon
# Required-Start:    $network $remote_fs $syslog
# Required-Stop:     $network $remote_fs $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Mullvad VPN daemon
### END INIT INFO

DAEMON=/usr/bin/mullvad-daemon
NAME=mullvad-daemon
export MULLVAD_RESOURCE_DIR="/opt/Mullvad VPN/resources/"

test -x $DAEMON || exit 0

case "$1" in
  start)
    echo "Starting $NAME..."
    start-stop-daemon --start --background --exec $DAEMON -- -vv --disable-stdout-timestamps
    ;;
  stop)
    echo "Stopping $NAME..."
    start-stop-daemon --stop --exec $DAEMON
    ;;
  restart)
    $0 stop
    sleep 1
    $0 start
    ;;
  *)
    echo "Usage: /etc/init.d/mullvad-daemon {start|stop|restart}"
    exit 1
    ;;
esac
exit 0
EOF
chmod 0755 pkgroot/etc/init.d/mullvad-daemon

# 5. Replace Debian scripts (postinst, prerm, postrm) to remove systemctl
cat << 'EOF' > pkgroot/DEBIAN/postinst
#!/usr/bin/env bash
set -eu
chmod u+s "/usr/bin/mullvad-exclude"

# Register sysvinit service if update-rc.d exists
if command -v update-rc.d >/dev/null 2>&1; then
    update-rc.d mullvad-daemon defaults || true
fi

function supported_apparmor() {
    [[ -e /etc/apparmor.d/abi/4.0 ]]
}
if supported_apparmor; then
    echo "Creating apparmor profile"
    cp /opt/Mullvad\ VPN/resources/apparmor_mullvad /etc/apparmor.d/mullvad
    apparmor_parser -r /etc/apparmor.d/mullvad || echo "Failed to reload apparmor profile"
fi
EOF
chmod 0755 pkgroot/DEBIAN/postinst

cat << 'EOF' > pkgroot/DEBIAN/prerm
#!/usr/bin/env bash
set -eu
# Stop daemon gracefully if running via sysvinit
if [ -x "/etc/init.d/mullvad-daemon" ]; then
    invoke-rc.d mullvad-daemon stop || true
fi
EOF
chmod 0755 pkgroot/DEBIAN/prerm

cat << 'EOF' > pkgroot/DEBIAN/postrm
#!/usr/bin/env bash
set -eu
if [ "$1" = "purge" ] && command -v update-rc.d >/dev/null 2>&1; then
    update-rc.d mullvad-daemon remove || true
fi
if supported_apparmor; then
    rm -f /etc/apparmor.d/mullvad
fi
EOF
chmod 0755 pkgroot/DEBIAN/postrm

# 6. Create README.devuan
mkdir -p pkgroot/usr/share/doc/mullvad-libre
cat << 'EOF' > pkgroot/usr/share/doc/mullvad-libre/README.devuan
Mullvad VPN for Devuan (No Systemd)

1. Start the service:
   - SysVinit / OpenRC: sudo service mullvad-daemon start
     (or: sudo rc-service mullvad-daemon start)
   - Runit: sudo ln -s /etc/sv/mullvad-daemon /var/service/

2. Usage:
   mullvad account login <your-account-number>
   mullvad connect
EOF

echo "Packaging..."
TIMESTAMP=$(date +%Y%m%d)
FULL_VERSION="${VERSION}.${TIMESTAMP}.${RUN_NUMBER}~devuandepot"

sed -i "s/Version: .*/Version: ${FULL_VERSION}/" pkgroot/DEBIAN/control

dpkg-deb --build --root-owner-group pkgroot "mullvad-libre_${FULL_VERSION}_amd64.deb"
echo "Build finished successfully."
