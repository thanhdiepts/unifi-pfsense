#!/bin/sh

# install-unifi.sh
# Installs the Uni-Fi controller software on a FreeBSD machine (presumably running pfSense).

# OS architecture
OS_ARCH=`getconf LONG_BIT`

# The latest version of UniFi:
UNIFI_SOFTWARE_URL="https://dl.ubnt.com/unifi/5.4.15/UniFi.unix.zip"

# The rc script associated with this branch or fork:
RC_SCRIPT_URL="https://raw.githubusercontent.com/gozoinks/unifi-pfsense/master/rc.d/unifi.sh"

#FreeBSD package source:
FREEBSD_PACKAGE_URL="https://pkg.freebsd.org/freebsd:10:x86:${OS_ARCH}/latest/All/"

#FreeBSD package list: 
FREEBSD_PACKAGE_LIST_URL="https://pkg.freebsd.org/freebsd:10:x86:${OS_ARCH}/latest/packagesite.txz" 


# If pkg-ng is not yet installed, bootstrap it:
if ! /usr/sbin/pkg -N 2> /dev/null; then
  echo "FreeBSD pkgng not installed. Installing..."
  env ASSUME_ALWAYS_YES=YES /usr/sbin/pkg bootstrap
  echo " done."
fi

# If installation failed, exit:
if ! /usr/sbin/pkg -N 2> /dev/null; then
  echo "ERROR: pkgng installation failed. Exiting."
  exit 1
fi

# Stop the controller if it's already running...
# First let's try the rc script if it exists:
if [ -f /usr/local/etc/rc.d/unifi.sh ]; then
  echo -n "Stopping the unifi service..."
  /usr/sbin/service unifi.sh stop
  echo " done."
fi

# Then to be doubly sure, let's make sure ace.jar isn't running for some other reason:
if [ $(ps ax | grep -c "/usr/local/UniFi/lib/[a]ce.jar start") -ne 0 ]; then
  echo -n "Killing ace.jar process..."
  /bin/kill -15 `ps ax | grep "/usr/local/UniFi/lib/[a]ce.jar start" | awk '{ print $1 }'`
  echo " done."
fi

# And then make sure mongodb doesn't have the db file open:
if [ $(ps ax | grep -c "/usr/local/UniFi/data/[d]b") -ne 0 ]; then
  echo -n "Killing mongod process..."
  /bin/kill -15 `ps ax | grep "/usr/local/UniFi/data/[d]b" | awk '{ print $1 }'`
  echo " done."
fi

# If an installation exists, we'll need to back up configuration:
if [ -d /usr/local/UniFi/data ]; then
  echo "Backing up UniFi data..."
  BACKUPFILE=/var/backups/unifi-`date +"%Y%m%d_%H%M%S"`.tgz
  /usr/bin/tar -vczf ${BACKUPFILE} /usr/local/UniFi/data
fi

# Add the fstab entries apparently required for OpenJDKse:
if [ $(grep -c fdesc /etc/fstab) -eq 0 ]; then
  echo -n "Adding fdesc filesystem to /etc/fstab..."
  echo -e "fdesc\t\t\t/dev/fd\t\tfdescfs\trw\t\t0\t0" >> /etc/fstab
  echo " done."
fi

if [ $(grep -c proc /etc/fstab) -eq 0 ]; then
  echo -n "Adding procfs filesystem to /etc/fstab..."
  echo -e "proc\t\t\t/proc\t\tprocfs\trw\t\t0\t0" >> /etc/fstab
  echo " done."
fi

# Run mount to mount the two new filesystems:
echo -n "Mounting new filesystems..."
/sbin/mount -a
echo " done."

# Install mongodb, OpenJDK, and unzip (required to unpack Ubiquiti's download):
# -F skips a package if it's already installed, without throwing an error.
echo "Installing required packages..."
tar xv -C / -f /usr/local/share/pfSense/base.txz ./usr/bin/install
#uncomment below for pfSense 2.2.x:
#env ASSUME_ALWAYS_YES=YES /usr/sbin/pkg install mongodb openjdk unzip pcre v8 snappy

fetch ${FREEBSD_PACKAGE_LIST_URL} 
tar vfx packagesite.txz 

AddPkg () { 
	pkgname=$1	
	pkginfo=`grep "\"name\":\"$pkgname\"" packagesite.yaml`
	pkgvers=`echo $pkginfo | pcregrep -o1 '"version":"(.*?)"' | head -1`
	if [ `pkg info | grep -c $pkgname-$pkgvers` -eq 1 ]; then
		echo "Package $pkgname-$pkgvers already installed."
	else
		env ASSUME_ALWAYS_YES=YES /usr/sbin/pkg add ${FREEBSD_PACKAGE_URL}${pkgname}-${pkgvers}.txz 
	fi
}
 
AddPkg snappy
AddPkg python2
AddPkg v8
AddPkg mongodb
AddPkg unzip
AddPkg pcre
AddPkg alsa-lib
AddPkg freetype2
AddPkg fontconfig
AddPkg xproto
AddPkg kbproto
AddPkg libXdmcp
AddPkg libpthread-stubs
AddPkg libXau
AddPkg libxcb
AddPkg libICE
AddPkg libSM
AddPkg java-zoneinfo
AddPkg fixesproto
AddPkg xextproto
AddPkg inputproto
AddPkg libX11
AddPkg libXfixes
AddPkg libXext
AddPkg libXi
AddPkg libXt
AddPkg libfontenc
AddPkg mkfontscale
AddPkg mkfontdir
AddPkg dejavu
AddPkg recordproto
AddPkg libXtst
AddPkg renderproto
AddPkg libXrender
AddPkg javavmwrapper
AddPkg giflib
AddPkg openjdk8
AddPkg snappyjava

# Save current snappyjava version for later:
snappyjavavers=`grep "\"name\":\"snappyjava\"" packagesite.yaml | pcregrep -o1 '"version":"(.*?)"' | head -1`

# Clean up downloaded package manifest:
rm packagesite.*

echo " done."

# Switch to a temp directory for the Unifi download:
cd `mktemp -d -t unifi`

# Download the controller from Ubiquiti (assuming acceptance of the EULA):
echo -n "Downloading the UniFi controller software..."
/usr/bin/fetch ${UNIFI_SOFTWARE_URL}
echo " done."

# Unpack the archive into the /usr/local directory:
# (the -o option overwrites the existing files without complaining)
echo -n "Installing UniFi controller in /usr/local..."
/usr/local/bin/unzip -o UniFi.unix.zip -d /usr/local
echo " done."

# Update Unifi's symbolic link for mongod to point to the version we just installed:
echo -n "Updating mongod link..."
/bin/ln -sf /usr/local/bin/mongod /usr/local/UniFi/bin/mongod
echo " done."

# If partition size is < 4GB, add smallfiles option to mongodb
echo -n "Checking partition size..."
if [ `df -k | awk '$NF=="/"{print $2}'` -le 4194302 ]; then
	echo -e "\nunifi.db.extraargs=--smallfiles\n" >> /usr/local/UniFi/data/system.properties
fi
echo " done."

# Replace snappy java library to support AP adoption with latest firmware:
echo -n "Updating snappy java..."
cd `mktemp -d -t snappyjava`
fetch ${FREEBSD_PACKAGE_URL}snappyjava-${snappyjavavers}.txz
tar vfx snappyjava-${snappyjavavers}.txz
upstreamsnappyjava=`ls -a /usr/local/UniFi/lib/ | pcregrep -o1 '^snappy-java-(.*).jar$'`
mv /usr/local/UniFi/lib/snappy-java-${upstreamsnappyjava}.jar /usr/local/UniFi/lib/snappy-java-${upstreamsnappyjava}.jar.backup
cp ./usr/local/share/java/classes/snappy-java.jar /usr/local/UniFi/lib/snappy-java-${upstreamsnappyjava}.jar
echo " done."

# Fetch the rc script from github:
echo -n "Installing rc script..."
/usr/bin/fetch -o /usr/local/etc/rc.d/unifi.sh ${RC_SCRIPT_URL}
echo " done."

# Fix permissions so it'll run
chmod +x /usr/local/etc/rc.d/unifi.sh

# Add the startup variable to rc.conf.local.
# Eventually, this step will need to be folded into pfSense, which manages the main rc.conf.
# In the following comparison, we expect the 'or' operator to short-circuit, to make sure the file exists and avoid grep throwing an error.
if [ ! -f /etc/rc.conf.local ] || [ $(grep -c unifi_enable /etc/rc.conf.local) -eq 0 ]; then
  echo -n "Enabling the unifi service..."
  echo "unifi_enable=YES" >> /etc/rc.conf.local
  echo " done."
fi

# Restore the backup:
if [ ! -z "${BACKUPFILE}" ] && [ -f ${BACKUPFILE} ]; then
  echo "Restoring UniFi data..."
  mv /usr/local/UniFi/data /usr/local/UniFi/data-orig
  /usr/bin/tar -vxzf ${BACKUPFILE} -C /
fi

# Start it up:
echo -n "Starting the unifi service..."
/usr/sbin/service unifi.sh start
echo " done."
