#!/bin/bash
#
# Script to generate Core Storage volume system test files
# Requires Mac OS 10.7 upto Mac OS 10.15

EXIT_SUCCESS=0;
EXIT_FAILURE=1;

# Checks the availability of a binary and exits if not available.
#
# Arguments:
#   a string containing the name of the binary
#
assert_availability_binary()
{
	local BINARY=$1;

	which ${BINARY} > /dev/null 2>&1;
	if test $? -ne ${EXIT_SUCCESS};
	then
		echo "Missing binary: ${BINARY}";
		echo "";

		exit ${EXIT_FAILURE};
	fi
}

create_test_file_entries()
{
	MOUNT_POINT=$1;

	# Create an empty file
	touch ${MOUNT_POINT}/emptyfile

	# Create a directory
	mkdir ${MOUNT_POINT}/testdir1

	# Create a file
	echo "My file" > ${MOUNT_POINT}/testdir1/testfile1

	# Create a hard link to a file
	ln ${MOUNT_POINT}/testdir1/testfile1 ${MOUNT_POINT}/file_hardlink1

	# Create a symbolic link to a file
	ln -s ${MOUNT_POINT}/testdir1/testfile1 ${MOUNT_POINT}/file_symboliclink1

	# Create a hard link to a directory
	# ln ${MOUNT_POINT}/testdir1 ${MOUNT_POINT}/directory_hardlink1
	# ln: ${MOUNT_POINT}/testdir1: Is a directory

	# Create a symbolic link to a directory
	ln -s ${MOUNT_POINT}/testdir1 ${MOUNT_POINT}/directory_symboliclink1

	# Create a file with an UTF-8 NFC encoded filename
	touch `printf "${MOUNT_POINT}/nfc_t\xc3\xa9stfil\xc3\xa8"`

	# Create a file with an UTF-8 NFD encoded filename
	touch `printf "${MOUNT_POINT}/nfd_te\xcc\x81stfile\xcc\x80"`

	# Create a file with an UTF-8 NFD encoded filename
	touch `printf "${MOUNT_POINT}/nfd_\xc2\xbe"`

	# Create a file with an UTF-8 NFKD encoded filename
	touch `printf "${MOUNT_POINT}/nfkd_3\xe2\x81\x844"`

	# Create a file with filename that requires case folding if
	# the file system is case-insensitive
	touch `printf "${MOUNT_POINT}/case_folding_\xc2\xb5"`

	# Create a file with a forward slash in the filename
	touch `printf "${MOUNT_POINT}/forward:slash"`

	# Create a symbolic link to a file with a forward slash in the filename
	ln -s ${MOUNT_POINT}/forward:slash ${MOUNT_POINT}/file_symboliclink2

	# Create a file with a resource fork with content
	touch ${MOUNT_POINT}/testdir1/resourcefork1
	echo "My resource fork" > ${MOUNT_POINT}/testdir1/resourcefork1/..namedfork/rsrc

	# Create a file with an extended attribute with content
	touch ${MOUNT_POINT}/testdir1/xattr1
	xattr -w myxattr1 "My 1st extended attribute" ${MOUNT_POINT}/testdir1/xattr1

	# Create a directory with an extended attribute with content
	mkdir ${MOUNT_POINT}/testdir1/xattr2
	xattr -w myxattr2 "My 2nd extended attribute" ${MOUNT_POINT}/testdir1/xattr2

	# Create a file with an extended attribute that is not stored inline
	read -d "" -n 8192 -r LARGE_XATTR_DATA < LICENSE;
	touch ${MOUNT_POINT}/testdir1/large_xattr
	xattr -w mylargexattr "${LARGE_XATTR_DATA}" ${MOUNT_POINT}/testdir1/large_xattr
}

assert_availability_binary diskutil;
assert_availability_binary hdiutil;
assert_availability_binary sw_vers;

MACOS_VERSION=`sw_vers -productVersion`;
SHORT_VERSION=`echo "${MACOS_VERSION}" | sed 's/^\([0-9][0-9]*[.][0-9][0-9]*\).*$/\1/'`;

# Note that versions of Mac OS before 10.13 not support "sort -V"
MAXIMUM_VERSION=`echo "${SHORT_VERSION} 10.15" | tr ' ' '\n' | sed 's/[.]//' | sort -rn | head -n 1`;
MINIMUM_VERSION=`echo "${SHORT_VERSION} 10.7" | tr ' ' '\n' | sed 's/[.]//' | sort -n | head -n 1`;

# TODO correctly handle version 11.x and 12.x

if test "${MINIMUM_VERSION}" != "107" || test "${MAXIMUM_VERSION}" != "1015";
then
	echo "Unsupported MacOS version: ${MACOS_VERSION}";

	exit ${EXIT_FAILURE};
fi

if test -d ${MACOS_VERSION};
then
	echo "Specimens directory: ${MACOS_VERSION} already exists.";

	exit ${EXIT_FAILURE};
fi

SPECIMENS_PATH="specimens/${MACOS_VERSION}";

if test -d ${SPECIMENS_PATH};
then
	echo "Specimens directory: ${SPECIMENS_PATH} already exists.";

	exit ${EXIT_FAILURE};
fi

mkdir -p ${SPECIMENS_PATH};

set -e;

DEVICE_NUMBER=`diskutil list | grep -e '^/dev/disk' | tail -n 1 | sed 's?^/dev/disk??;s? .*$??'`;

PHYSICAL_VOLUME_DEVICE_NUMBER=$(( ${DEVICE_NUMBER} + 1 ));
LOGICAL_VOLUME_DEVICE_NUMBER=$(( ${DEVICE_NUMBER} + 2 ));

# Create raw disk image with an empty CoreStore volume group
IMAGE_NAME="cs_volume_group";
IMAGE_SIZE="512M";

hdiutil create -size ${IMAGE_SIZE} -type UDIF ${SPECIMENS_PATH}/${IMAGE_NAME};
hdiutil attach -nomount ${SPECIMENS_PATH}/${IMAGE_NAME}.dmg;

diskutil coreStorage create test_volume_group disk${PHYSICAL_VOLUME_DEVICE_NUMBER}s1;

hdiutil detach disk${PHYSICAL_VOLUME_DEVICE_NUMBER};

# Create raw disk image with a CoreStore volume group with a single logical volume
IMAGE_NAME="cs_single_volume";
IMAGE_SIZE="512M";

hdiutil create -size ${IMAGE_SIZE} -type UDIF ${SPECIMENS_PATH}/${IMAGE_NAME};
hdiutil attach -nomount ${SPECIMENS_PATH}/${IMAGE_NAME}.dmg;

diskutil coreStorage create test_volume_group disk${PHYSICAL_VOLUME_DEVICE_NUMBER}s1;

VOLUME_GROUP_IDENTIFIER=`diskutil coreStorage list | grep 'Logical Volume Group' | tail -n1 | sed 's/^.* //'`;

# Note that older versions of diskutil do not support using the volume group name
diskutil coreStorage createVolume ${VOLUME_GROUP_IDENTIFIER} 'Journaled HFS+' test_logical_volume 100%

create_test_file_entries "/Volumes/test_logical_volume";

hdiutil detach disk${LOGICAL_VOLUME_DEVICE_NUMBER};
hdiutil detach disk${PHYSICAL_VOLUME_DEVICE_NUMBER};

# Create raw disk image with a CoreStore volume group with a single encrypted logical volume
IMAGE_NAME="cs_single_volume_encrypted";
IMAGE_SIZE="512M";

hdiutil create -size ${IMAGE_SIZE} -type UDIF ${SPECIMENS_PATH}/${IMAGE_NAME};
hdiutil attach -nomount ${SPECIMENS_PATH}/${IMAGE_NAME}.dmg;

diskutil coreStorage create test_volume_group disk${PHYSICAL_VOLUME_DEVICE_NUMBER}s1;

VOLUME_GROUP_IDENTIFIER=`diskutil coreStorage list | grep 'Logical Volume Group' | tail -n1 | sed 's/^.* //'`;

# Note that older versions of diskutil do not support using the volume group name
# Note that Mac OS 10.7 does not support "diskutil coreStorage encryptVolume"
diskutil coreStorage createVolume ${VOLUME_GROUP_IDENTIFIER} 'Journaled HFS+' test_logical_volume 100% -passphrase cs-TEST

create_test_file_entries "/Volumes/test_logical_volume";

set +e

# On Mac OS 10.10 detach of the encrypted volume can fail with "Resource busy"
hdiutil detach disk${LOGICAL_VOLUME_DEVICE_NUMBER};

set -e

hdiutil detach disk${PHYSICAL_VOLUME_DEVICE_NUMBER};

MINIMUM_VERSION=`echo "${SHORT_VERSION} 10.8" | tr ' ' '\n' | sed 's/[.]//' | sort -n | head -n 1`;

# Note that encryptVolume and decryptVolume are not supported by Mac OS 10.7
if test "${MINIMUM_VERSION}" = "108";
then
	# Create raw disk image with a CoreStore volume group with a single logical volume and encrypt it
	IMAGE_NAME="cs_single_volume_encrypted2";
	IMAGE_SIZE="512M";

	hdiutil create -size ${IMAGE_SIZE} -type UDIF ${SPECIMENS_PATH}/${IMAGE_NAME};
	hdiutil attach -nomount ${SPECIMENS_PATH}/${IMAGE_NAME}.dmg;

	diskutil coreStorage create test_volume_group disk${PHYSICAL_VOLUME_DEVICE_NUMBER}s1;

	VOLUME_GROUP_IDENTIFIER=`diskutil coreStorage list | grep 'Logical Volume Group' | tail -n1 | sed 's/^.* //'`;

	# Note that older versions of diskutil do not support using the volume group name
	diskutil coreStorage createVolume ${VOLUME_GROUP_IDENTIFIER} 'Journaled HFS+' test_logical_volume 100%

	create_test_file_entries "/Volumes/test_logical_volume";

	LOGICAL_VOLUME_IDENTIFIER=`diskutil coreStorage list | grep 'Logical Volume ' | tail -n1 | sed 's/^.* //'`;

	diskutil coreStorage encryptVolume ${LOGICAL_VOLUME_IDENTIFIER} -passphrase cs-TEST

	set +e

	# On Mac OS 10.10 detach of the encrypted volume can fail with "Resource busy"
	hdiutil detach disk${LOGICAL_VOLUME_DEVICE_NUMBER};

	set -e

	hdiutil detach disk${PHYSICAL_VOLUME_DEVICE_NUMBER};

	# Create raw disk image with a CoreStore volume group with a single decrypted logical volume
	IMAGE_NAME="cs_single_volume_decrypted";
	IMAGE_SIZE="512M";

	hdiutil create -size ${IMAGE_SIZE} -type UDIF ${SPECIMENS_PATH}/${IMAGE_NAME};
	hdiutil attach -nomount ${SPECIMENS_PATH}/${IMAGE_NAME}.dmg;

	diskutil coreStorage create test_volume_group disk${PHYSICAL_VOLUME_DEVICE_NUMBER}s1;

	VOLUME_GROUP_IDENTIFIER=`diskutil coreStorage list | grep 'Logical Volume Group' | tail -n1 | sed 's/^.* //'`;

	# Note that older versions of diskutil do not support using the volume group name
	diskutil coreStorage createVolume ${VOLUME_GROUP_IDENTIFIER} 'Journaled HFS+' test_logical_volume 100% -passphrase cs-TEST

	create_test_file_entries "/Volumes/test_logical_volume";

	LOGICAL_VOLUME_IDENTIFIER=`diskutil coreStorage list | grep 'Logical Volume ' | tail -n1 | sed 's/^.* //'`;

	diskutil coreStorage decryptVolume ${LOGICAL_VOLUME_IDENTIFIER} -passphrase cs-TEST

	hdiutil detach disk${LOGICAL_VOLUME_DEVICE_NUMBER};

	set +e

	# On Mac OS 10.15 detach of the logic volume will automatically detach the physical volume
	hdiutil detach disk${PHYSICAL_VOLUME_DEVICE_NUMBER};

	set -e
fi

# Create raw disk image with a CoreStore volume group with a single logical volume
IMAGE_NAME="cs_single_volume_converted";
IMAGE_SIZE="512M";

hdiutil create -fs 'Journaled HFS+' -size ${IMAGE_SIZE} -type UDIF -volname test_logical_volume ${SPECIMENS_PATH}/${IMAGE_NAME};
hdiutil attach ${SPECIMENS_PATH}/${IMAGE_NAME}.dmg;

create_test_file_entries "/Volumes/test_logical_volume";

diskutil coreStorage convert disk${PHYSICAL_VOLUME_DEVICE_NUMBER}s1;

hdiutil detach disk${LOGICAL_VOLUME_DEVICE_NUMBER};
hdiutil detach disk${PHYSICAL_VOLUME_DEVICE_NUMBER};

# Note that versions of Mac OS before 10.13 not support "sort -V"
MINIMUM_VERSION=`echo "${SHORT_VERSION} 10.11" | tr ' ' '\n' | sed 's/[.]//' | sort -n | head -n 1`;

# Note that multiple logical volumes are no longer supported by Mac OS 10.11 or later
# diskutil coreStorage createVolume will fail with: "Your Logical Volume Group already has a Logical Volume".
if test "${MINIMUM_VERSION}" != "1011";
then
	# Create raw disk image with a CoreStore volume group with a multiple logical volumes
	IMAGE_NAME="cs_multi_volume";

	# Note that versions of Mac OS before 10.13 not support "sort -V"
	MINIMUM_VERSION=`echo "${SHORT_VERSION} 10.10" | tr ' ' '\n' | sed 's/[.]//' | sort -n | head -n 1`;

	if test "${MINIMUM_VERSION}" = "1010";
	then
		IMAGE_SIZE="1G";
	else
		IMAGE_SIZE="512M";
	fi

	hdiutil create -size ${IMAGE_SIZE} -type UDIF ${SPECIMENS_PATH}/${IMAGE_NAME};
	hdiutil attach -nomount ${SPECIMENS_PATH}/${IMAGE_NAME}.dmg;

	diskutil coreStorage create test_volume_group disk${PHYSICAL_VOLUME_DEVICE_NUMBER}s1;

	VOLUME_GROUP_IDENTIFIER=`diskutil coreStorage list | grep 'Logical Volume Group' | tail -n1 | sed 's/^.* //'`;

	# Note that older versions of diskutil do not support using the volume group name
	diskutil coreStorage createVolume ${VOLUME_GROUP_IDENTIFIER} 'Journaled HFS+' test_logical_volume1 64m

	create_test_file_entries "/Volumes/test_logical_volume1";

	diskutil coreStorage createVolume ${VOLUME_GROUP_IDENTIFIER} 'Journaled HFS+' test_logical_volume2 64m

	create_test_file_entries "/Volumes/test_logical_volume2";

	diskutil coreStorage createVolume ${VOLUME_GROUP_IDENTIFIER} 'Journaled HFS+' test_logical_volume3 64m

	create_test_file_entries "/Volumes/test_logical_volume3";

	hdiutil detach disk$(( ${DEVICE_NUMBER} + 4 ));
	hdiutil detach disk$(( ${DEVICE_NUMBER} + 3 ));
	hdiutil detach disk${LOGICAL_VOLUME_DEVICE_NUMBER};
	hdiutil detach disk${PHYSICAL_VOLUME_DEVICE_NUMBER};
fi

PHYSICAL_VOLUME1_DEVICE_NUMBER=$(( ${DEVICE_NUMBER} + 1 ));
PHYSICAL_VOLUME2_DEVICE_NUMBER=$(( ${DEVICE_NUMBER} + 2 ));
LOGICAL_VOLUME_DEVICE_NUMBER=$(( ${DEVICE_NUMBER} + 3 ));

# WARNING: the following might cause Disk Arbitration to time out.
IGNORE_WARNING=0;

MINIMUM_VERSION=`echo "${SHORT_VERSION} 10.8" | tr ' ' '\n' | sed 's/[.]//' | sort -n | head -n 1`;

# Note that a Core Storage volume with multiple physical disks is not supported by Mac OS 10.7
if test "${MINIMUM_VERSION}" = "108" && test ${IGNORE_WARNING} -ne 0;
then
	# Create multiple raw disk images with a CoreStore volume group with a single logical volume
	IMAGE_NAME="cs_multi_physical";
	IMAGE_SIZE="512M";

	hdiutil create -size ${IMAGE_SIZE} -type UDIF ${SPECIMENS_PATH}/${IMAGE_NAME}1;
	hdiutil attach -nomount ${SPECIMENS_PATH}/${IMAGE_NAME}1.dmg;

	hdiutil create -size ${IMAGE_SIZE} -type UDIF ${SPECIMENS_PATH}/${IMAGE_NAME}2;
	hdiutil attach -nomount ${SPECIMENS_PATH}/${IMAGE_NAME}2.dmg;

	# Note that on Mac OS 10.8 this can fail with:
	# Error: -69780: Unable to create a new CoreStorage Logical Volume
	diskutil coreStorage create test_volume_group disk${PHYSICAL_VOLUME1_DEVICE_NUMBER}s1 disk${PHYSICAL_VOLUME2_DEVICE_NUMBER}s1;

	VOLUME_GROUP_IDENTIFIER=`diskutil coreStorage list | grep 'Logical Volume Group' | tail -n1 | sed 's/^.* //'`;

	# Note that older versions of diskutil do not support using the volume group name
	diskutil coreStorage createVolume ${VOLUME_GROUP_IDENTIFIER} 'Journaled HFS+' test_logical_volume 100%

	create_test_file_entries "/Volumes/test_logical_volume";

	hdiutil detach disk${LOGICAL_VOLUME_DEVICE_NUMBER};
	hdiutil detach disk${PHYSICAL_VOLUME2_DEVICE_NUMBER};
	hdiutil detach disk${PHYSICAL_VOLUME1_DEVICE_NUMBER};

	# Create multiple raw disk images with a CoreStore volume group with a single encrypted logical volume
	IMAGE_NAME="cs_multi_physical_encrypted";
	IMAGE_SIZE="512M";

	hdiutil create -size ${IMAGE_SIZE} -type UDIF ${SPECIMENS_PATH}/${IMAGE_NAME}1;
	hdiutil attach -nomount ${SPECIMENS_PATH}/${IMAGE_NAME}1.dmg;

	hdiutil create -size ${IMAGE_SIZE} -type UDIF ${SPECIMENS_PATH}/${IMAGE_NAME}2;
	hdiutil attach -nomount ${SPECIMENS_PATH}/${IMAGE_NAME}2.dmg;

	diskutil coreStorage create test_volume_group disk${PHYSICAL_VOLUME1_DEVICE_NUMBER}s1 disk${PHYSICAL_VOLUME2_DEVICE_NUMBER}s1;

	VOLUME_GROUP_IDENTIFIER=`diskutil coreStorage list | grep 'Logical Volume Group' | tail -n1 | sed 's/^.* //'`;

	# Note that older versions of diskutil do not support using the volume group name
	diskutil coreStorage createVolume ${VOLUME_GROUP_IDENTIFIER} 'Journaled HFS+' test_logical_volume 100% -passphrase cs-TEST

	create_test_file_entries "/Volumes/test_logical_volume";

	hdiutil detach disk${LOGICAL_VOLUME_DEVICE_NUMBER};
	hdiutil detach disk${PHYSICAL_VOLUME2_DEVICE_NUMBER};
	hdiutil detach disk${PHYSICAL_VOLUME1_DEVICE_NUMBER};
fi

exit ${EXIT_SUCCESS};

