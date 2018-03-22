#
# time2backup global functions
#
# This file is part of time2backup (https://time2backup.org)
#
# MIT License
# Copyright (c) 2017-2018 Jean Prunneaux
#

# Index of functions
#
#   check_backup_date
#   get_common_path
#   get_relative_path
#   get_protocol
#   url2ssh
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
	[ $# -lt 2 ] && return 1

	local directory1 directory2

	# get absolute paths
	directory1=$(lb_abspath "$1")
	[ $? != 0 ] && return 2

	directory2=$(lb_abspath "$2")
	[ $? != 0 ] && return 2

	# compare characters of paths one by one
	local path
	local -i i=0

	while true ; do
		# if a character changes in the 2 paths,
		if [ "${directory1:0:$i}" != "${directory2:0:$i}" ] ; then

			path=${directory1:0:$i}

			# if it's a directory, return it
			if [ -d "$path" ] ; then
				# special case of /
				if [ "$path" == "/" ] ; then
					echo /
				else
					# other directory
					if [ "${path:${#path}-1}" == "/" ] ; then
						# return path without the last /
						echo "${path:0:${#path}-1}"
					else
						echo "$path"
					fi
				fi
			else
				# if it's not a directory, return parent directory
				dirname "$path"
			fi

			# quit function
			return 0
		fi
		i+=1
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
	[ $# -lt 2 ] && return 1

	local src dest common_path

	# get absolute paths
	src=$(lb_abspath "$1")
	[ $? != 0 ] && return 2

	dest=$(lb_abspath "$2")
	[ $? != 0 ] && return 2

	# get common path
	common_path=$(get_common_path "$src" "$dest")
	[ $? != 0 ] && return 2

	# go into the first path
	cd "$src" 2> /dev/null || return 3

	local relative_path="./"

	# loop to find common path
	while [ "$(pwd)" != "$common_path" ] ; do

		# go to upper directory
		cd .. 2> /dev/null || return 3

		# append double dots to relative path
		relative_path+="../"
	done

	# print relative path
	echo "$relative_path/"
}


# Get protocol for backups or destination
# Usage: get_protocol URL
# Return: files|ssh|t2b
get_protocol() {

	local protocol=$(echo $1 | cut -d: -f1)

	# get protocol
	case $protocol in
		ssh|t2b)
			# double check protocol
			echo "$*" | grep -q -E "^$protocol://"
			if [ $? == 0 ] ; then
				echo $protocol
				return 0
			fi
			;;
	esac

	# if not found or error of protocol, it is regular files
	echo files
}


# Transform URLs to SSH path
# e.g. ssh://user@host/path/to/file -> user@host:/path/to/file
# Usage: url2ssh URL
# Return: path
url2ssh() {

	local ssh_host=$(echo "$1" | awk -F '/' '{print $3}')
	local ssh_prefix="ssh://$ssh_host"

	echo "$ssh_host:${1#$ssh_prefix}"
}


# Test if backup destination support hard links
# Usage: test_hardlinks PATH
# Exit codes:
#   0: destination supports hard links
#   1: cannot get filesystem type
#   2: destination does not support hard links
test_hardlinks() {

	# supported filesystems
	local fstype supported_fstypes=(ext2 ext3 ext4 btrfs aufs \
		hfs hfsplus apfs \
		ntfs)

	# get destination filesystem
	fstype=$(lb_df_fstype "$*")
	[ -z "$fstype" ] && return 1

	# if destination filesystem does not support hard links, return error
	lb_array_contains "$fstype" "${supported_fstypes[@]}" || return 2
}


# Calculate space to be taken by folders
# Usage: folders_size PATH
# Exit codes:
#   0: OK
#   1: Usage error (path does not exists)
folders_size() {

	# get number of subfolders
	local nb_directories=$(find "$*" -type d 2> /dev/null | wc -l)

	# set default size to 4096 bytes (ext*, FAT32)
	local directory_size=4096

	# get size of folders regarding FS type (in bytes)
	case $(lb_df_fstype "$*") in
		hfs|hfsplus)
			directory_size=68
			;;
		exfat)
			directory_size=131072
			;;
	esac

	# return nb folders * size (result in bytes)
	echo $(($nb_directories * $directory_size))
}


# Test space available on disk
# Usage: test_space_available BACKUP_SIZE_IN_BYTES PATH
# Exit codes:
#   0: there is space enough to backup
#   1: not space enough
test_space_available() {

	# if 0, always OK
	[ "$1" == 0 ] && return 0

	local space_available backup_size=$1
	shift

	# get space available (destination path is the next argument)
	space_available=$(lb_df_space_left "$*")

	# if there was an unknown error, continue
	if ! lb_is_integer $space_available ; then
		lb_display --log "Cannot get available space. Trying to backup although."
		return 0
	fi

	# transform space size from KB to bytes
	space_available=$(($space_available * 1024))

	lb_debug --log "Space available on disk (in bytes): $space_available"

	# if space is not enough, error
	if [ $space_available -lt $backup_size ] ; then
		lb_debug --log "Not enough space on device! Needed (in bytes): $backup_size/$space_available"
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
	lb_is_integer $1 || return 1

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

	[ "$lb_current_os" != Windows ] && return 0

	# test if a file
	[ -f "$*" ] || return 1

	sed -i 's/$/\r/g' "$*"
}
