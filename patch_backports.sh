sed -i '/apt-get source -b "$DEBIAN_PKG\/sid"/c\
echo "Downloading source for $DEBIAN_PKG..."\
apt-get source "$DEBIAN_PKG/sid"\
DIR=$(find . -maxdepth 1 -mindepth 1 -type d)\
cd $DIR\
echo "Patching debian/changelog to append ~devuandepot tag..."\
sed -i "1s/)/~devuandepot)/" debian/changelog\
echo "Compiling $DEBIAN_PKG..."\
dpkg-buildpackage -b -uc -us\
cd ..\
' scripts/build-backports.sh
