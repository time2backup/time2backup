#
# time2backup global functions
#
# This file is part of time2backup (https://time2backup.github.io)
#
# MIT License
# Copyright (c) 2017 Jean Prunneaux
#

# Index of functions
#
#   check_backup_date
#   get_common_path
#   get_relative_path
#   get_protocol
#   test_hardlinks
#   folders_size
#   test_space_available
#   rsync_result
#   file_for_windows


# Check syntax of a backup date
# Usage: check_backup_date DATE
# Exit codes:
#   0: OK
#   1: non OK
check_backup_date() {
	echo $1 | grep -Eq "^$backup_date_format$"
}


# Get common path of 2 paths
# e.g. get_common_path /home/user/my/first/path /home/user/my/second/path
# will return /home/user/my/
# Usage: get_common_path PATH_1 PATH_2
# Return: absolute path of the common directory
# Exit codes:
#   0: OK
#   1: usage error
#   2: error with paths
get_common_path() {

	# usage error
	if [ $# -lt 2 ] ; then
		return 1
	fi

	# get absolute paths
	local gcp_dir1=$(lb_abspath "$1")
	if [ $? != 0 ] ; then
		return 2
	fi

	local gcp_dir2=$(lb_abspath "$2")
	if [ $? != 0 ] ; then
		return 2
	fi

	# compare characters of paths one by one
	declare -i gcp_i=0
	while true ; do

		# if a character changes in the 2 paths,
		if [ "${gcp_dir1:0:$gcp_i}" != "${gcp_dir2:0:$gcp_i}" ] ; then

			local gcp_path=${gcp_dir1:0:$gcp_i}

			# if it's a directory, return it
			if [ -d "$gcp_path" ] ; then

				if [ "${gcp_path:${#gcp_path}-1}" == "/" ] ; then
					# return path without the last /
					echo "${gcp_path:0:${#gcp_path}-1}"
				else
					echo "$gcp_path"
				fi
			else
				# if not, return parent directory
				dirname "$gcp_path"
			fi

			# quit function
			return 0
		fi
		gcp_i+=1
	done
}


# Get relative path to reach second path from a first one
# e.g. get_relative_path /home/user/my/first/path /home/user/my/second/path
# will return ../../second/path
# Usage: get_relative_path SOURCE_PATH DESTINATION_PATH
# Return: relative path
# Exit codes:
#   0: OK
#   1: usage error
#   2: error with paths
#   3: unknown cd error (may be access rights issue)
get_relative_path() {

	# usage error
	if [ $# -lt 2 ] ; then
		return 1
	fi

	# get absolute paths
	local grp_src=$(lb_abspath "$1")
	if [ $? != 0 ] ; then
		return 2
	fi

	local grp_dest=$(lb_abspath "$2")
	if [ $? != 0 ] ; then
		return 2
	fi

	# get common path
	local grp_common_path=$(get_common_path "$grp_src" "$grp_dest")
	if [ $? != 0 ] ; then
		return 2
	fi

	# go into the first path
	cd "$grp_src" 2> /dev/null
	if [ $? != 0 ] ; then
		return 3
	fi

	local grp_relative_path="./"

	# loop to find common path
	while [ "$(pwd)" != "$grp_common_path" ] ; do

		# go to upper directory
		cd .. 2> /dev/null
		if [ $? != 0 ] ; then
			return 3
		fi

		# append double dots to relative path
		grp_relative_path+="../"
	done

	# print relative path
	echo "$grp_relative_path/"
}


# Get protocol for backups or destination
# Usage: get_protocol URL
# Return: files|ssh|t2b
get_protocol() {

	local gptc_protocol=$(echo $1 | cut -d: -f1)

	# get protocol
	case $gptc_protocol in
		ssh|t2b)
			# double check protocol
			echo $* | grep -q -E "^$gptc_protocol://"
			if [ $? == 0 ] ; then
				echo $gptc_protocol
				return 0
			fi
			;;
	esac

	# if not found or error of protocol, it is regular files
	echo files
}


# Test if backup destination support hard links
# Usage: test_hardlinks PATH
# Exit codes:
#   0: destination supports hard links
#   1: cannot get filesystem type
#   2: destination does not support hard links
test_hardlinks() {

	# supported filesystems
	local thl_hardlinks_fs=(ext2 ext3 ext4 btrfs aufs \
	hfs hfsplus apfs \
	ntfs)

	# get destination filesystem
	local thl_fstype=$(lb_df_fstype "$*")
	if [ -z "$thl_fstype" ] ; then
		return 1
	fi

	# if destination filesystem does not support hard links, return error
	if ! lb_array_contains "$thl_fstype" "${thl_hardlinks_fs[@]}" ; then
		return 2
	fi
}


# Calculate space to be taken by folders
# Usage: folders_size PATH
# Exit codes:
#   0: OK
#   1: Usage error (path does not exists)
folders_size() {

	# get number of subfolders
	local fs_nbdir=$(find "$*" -type d 2> /dev/null | wc -l)

	# get size of folders regarding FS type (in bytes)
	case $(lb_df_fstype "$*") in
		hfs|hfsplus)
			fs_dirsize=68
			;;
		exfat)
			fs_dirsize=131072
			;;
		*)
			# set default to 4096 (ext*, FAT32)
			fs_dirsize=4096
			;;
	esac

	# return nb folders * size (result in bytes)
	echo $(($fs_nbdir * $fs_dirsize))
}


# Test space available on disk
# Usage: test_space_available BACKUP_SIZE_IN_BYTES PATH
# Exit codes:
#   0: there is space enough to backup
#   1: not space enough
test_space_available() {

	# if 0, always OK
	if [ $1 == 0 ] ; then
		return 0
	fi

	tsa_size=$1

	# get space available (destination path is the next argument)
	shift
	tsa_space_left=$(lb_df_space_left "$*")

	# if there was an unknown error, continue
	if ! lb_is_integer $tsa_space_left ; then
		lb_display --log "Cannot get available space. Trying to backup although."
		return 0
	fi

	# transform space size from KB to bytes
	tsa_space_left=$(($tsa_space_left * 1024))

	lb_debug --log "Space available on disk (in bytes): $tsa_space_left"

	# if space is not enough, error
	if [ $tsa_space_left -lt $tsa_size ] ; then
		lb_debug --log "Not enough space on device! Needed (in bytes): $tsa_size/$tsa_space_left"
		return 1
	fi
}


# Manage rsync exit codes
# Usage: rsync_result EXIT_CODE
# Exit codes:
#   0: rsync was OK
#   1: usage error
#   2: rsync error
rsync_result() {

	# usage error
	if ! lb_is_integer $1 ; then
		return 1
	fi

	# manage results
	case $1 in
		0|23|24)
			# OK or partial transfer
			return 0
			;;
		*)
			# critical errors that caused backup to fail
			return 2
			;;
	esac
}


# Transform a config file in Windows format
# Usage: file_for_windows PATH
# Exit codes:
#   0: OK
#   1: Usage error / Unknown error
file_for_windows() {

	if [ "$lb_current_os" != Windows ] ; then
		return 0
	fi

	if ! [ -f "$1" ] ; then
		return 1
	fi

	sed -i 's/$/\r/g' "$1"
}
