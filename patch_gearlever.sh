sed -i '/ninja -C build install/a\
echo "Installing Python dependencies locally into the deb..."\
apt-get install -y python3-pip\
pip3 install desktop-entry-lib --target=$PWD/../../pkgroot/usr/lib/python3/dist-packages/ --no-user\
' scripts/build-gearlever.sh
