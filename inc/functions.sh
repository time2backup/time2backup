#
#  time2backup global functions
#
#  This file is part of time2backup (https://time2backup.org)
#
#  MIT License
#  Copyright (c) 2017-2019 Jean Prunneaux
#

# Index
#
#   Global functions
#     test_period
#     period2seconds
#     remove_end_slash
#     check_backup_date
#     get_common_path
#     get_relative_path
#     get_protocol
#     url2host
#     url2path
#     url2ssh
#     file_for_windows
#     debug
#     notify
#     folders_size
#     set_verbose_log_levels
#     test_hardlinks
#     test_space_available
#     get_backup_date
#     get_backup_history
#     get_backup_path
#     get_backups
#     delete_backup
#     rotate_backups
#     report_duration
#     prepare_destination
#     free_space
#     clean_empty_backup
#     auto_exclude
#     try_sudo
#   Config functions
#     create_config_from_template
#     create_config
#     upgrade_config
#     load_config
#     crontab_config
#     apply_config
#     open_config
#   Log functions
#     create_logfile
#     delete_logfile
#   Infofile functions
#     create_infofile
#     find_infofile_section
#     get_infofile_value
#   Mount functions
#     mount_destination
#     unmount_destination
#   Lock functions
#     current_lock
#     create_lock
#     release_lock
#   rsync functions
#     prepare_rsync
#     get_rsync_remote_command
#     rsync_result
#   Remote backups
#     prepare_remote_destination
#     read_remote_config
#   Backup steps
#     test_backup
#     estimate_backup_time
#     run_before
#     run_after
#     move_backup
#     create_latest_link
#     notify_backup_end
#   Exit functions
#     catch_kills
#     uncatch_kills
#     clean_exit
#     cancel_exit
#     send_email_report
#     haltpc
#   Wizards
#     choose_operation
#     config_wizard


#
#  Global functions
#

# Test if a string is a period
# Usage: test_period PERIOD
# Exit codes:
#   0: period is valid
#   1: not valid syntax
test_period() {
	echo "$*" | grep -Eq "^[1-9][0-9]*(m|h|d)$"
}


# Convert a period in seconds
# Usage: period2seconds N(m|h|d)
# Return: seconds
period2seconds() {
	# convert minutes then to seconds
	echo $(($(echo "$*" | sed 's/m//; s/h/\*60/; s/d/\*1440/') * 60))
}


# Remove the last / of a path
# Usage: remove_end_slash PATH
# Return: new path
remove_end_slash() {
	# remove end slashes
	local path=$(echo "$*" | sed 's/\/*$//')

	# if it was / (now empty), keep it
	[ -z "$path" ] && path=/

	echo "$path"
}


# Check syntax of a backup date
# Usage: check_backup_date DATE
# Dependencies: $backup_date_format
# Exit codes:
#   0: OK
#   1: non OK
check_backup_date() {
	echo $1 | grep -Eq "^$backup_date_format$"
}


# Get common path of 2 paths
# e.g. get_common_path /home/user/my/first/path /home/user/my/second/path
# will return /home/user/my
# Usage: get_common_path PATH PATH
# Return: absolute path of the common directory
# Exit codes:
#   0: OK
#   1: usage error
#   2: error with paths
get_common_path() {

	# usage error
	[ $# -lt 2 ] && return 1

	# get path and convert them to avoid multiple slashes
	local path dir1=$(dirname "$1"/dummy) dir2=$(dirname "$2"/dummy)

	# get absolute paths
	[ "${dir1:0:1}" == / ] || dir1=$(lb_abspath "$dir1") || return 2
	[ "${dir2:0:1}" == / ] || dir2=$(lb_abspath "$dir2") || return 2

	# compare characters of paths one by one
	local -i i=0

	# if a character changes in the 2 paths,
	while [ "${dir1:i:1}" == "${dir2:i:1}" ] ; do
		i+=1
	done

	path=${dir1:0:i}

	# if it's a directory, return it
	if [ -d "$path" ] ; then
		# return path without the last /
		remove_end_slash "$path"
	else
		# if it's not a directory, return parent directory
		dirname "$path"
	fi
}


# Get relative path to reach second path from a first one
# e.g. get_relative_path /home/user/my/first/path /home/user/my/second/path
# will return ../../
# Usage: $(get_relative_path SOURCE_PATH DESTINATION_PATH)
# Return: relative path
# Exit codes:
#   0: OK
#   1: usage error
#   2: error with paths
#   3: unknown cd error (may be access rights issue)
get_relative_path() {

	# usage error
	[ $# -lt 2 ] && return 1

	# avoid comparison errors with double slashes or else
	local relative_path=./ dir1=$(dirname "$1"/dummy) dir2=$(dirname "$2"/dummy)

	# loop to find common path
	while [ "$dir1" != "$(dirname "$dir2")" ] && [ "$dir1" != "$dir2" ] ; do
		# go to upper directory
		dir1=$(dirname "$dir1")

		# append double dots to relative path
		relative_path+=../

		# avoid infinite loop for root directory
		[ "$dir1" == / ] && break
	done

	# print relative path
	echo $relative_path
}


# Get protocol for backups or destination
# Usage: get_protocol URL
# Return: protocol
get_protocol() {

	# get protocol
	local protocol
	protocol=$(echo $1 | cut -d: -f1)

	case $protocol in
		ssh)
			echo $protocol
			;;
		*)
			echo files
			;;
	esac
}


# Transform URLs to SSH hosts
# e.g. ssh://user@host/path/to/file -> user@host
# Usage: url2host URL
# Return: host
url2host() {
	echo "$1" | awk -F '/' '{print $3}'
}


# Transform URLs to SSH path
# e.g. ssh://user@host/path/to/file -> /path/to/file
# Usage: url2path URL
# Return: path
url2path() {

	# get ssh host
	local ssh_host=$(url2host "$1")

	# prepare prefix to ignore
	local ssh_prefix=ssh://$ssh_host

	# return path without prefix with bugfix for path with spaces
	echo "${1#$ssh_prefix}" | sed 's/ /\\ /g'
}


# Transform URLs to SSH complete
# e.g. ssh://user@host/path/to/file -> user@host:/path/to/file
# Usage: url2ssh URL
# Return: complete path
url2ssh() {
	# test URL
	if [ "${1:0:6}" == 'ssh://' ] ; then
		echo "$(url2host "$1"):$(url2path "$1")"
	else
		echo "$1"
	fi
}


# Transform a config file in Windows format
# Usage: file_for_windows PATH
# Exit codes:
#   0: OK
#   1: Usage error / Unknown error
file_for_windows() {

	# not on Windows: do nothing
	[ "$lb_current_os" != Windows ] && return 0

	# add end line character
	lb_edit 's/$/\r/g' "$*"
}


# Display a debug message
# Usage: debug TEXT
# Dependencies: $debug_mode
debug() {
	lb_istrue $debug_mode || return 0
	lb_debug "$*"
}


# Display a notification if enabled
# Usage: notify TEXT
# Dependencies: $notifications
notify() {
	lb_istrue $notifications && lbg_notify "$*" &
}


# Calculate space to be taken by folders
# Usage: folders_size PATH
# Return: size in bytes
# Exit codes:
#   0: OK
#   1: Usage error (path does not exists)
folders_size() {

	local nb_directories directory_size

	# get number of subfolders
	nb_directories=$(find "$*" -type d 2> /dev/null | wc -l)

	# get size of folders regarding FS type (in bytes)
	case $(lb_df_fstype "$*") in
		hfs|hfsplus)
			directory_size=68
			;;
		exfat)
			directory_size=131072
			;;
		*)
			# set default size to 4096 bytes (ext*, FAT32)
			directory_size=4096
			;;
	esac

	# return nb folders * size (in bytes)
	echo $(($nb_directories * $directory_size))
}


# Usage: set_verbose_log_levels
# Dependencies: $debug_mode, $force_verbose_level, $force_log_level, $verbose_level, $log_level
set_verbose_log_levels() {

	# debug mode: do nothing
	lb_istrue $debug_mode && return 0

	# overwritten levels
	[ -n "$force_log_level" ] && log_level=$force_log_level
	[ -n "$force_verbose_level" ] && verbose_level=$force_verbose_level

	# defines log level
	# if not set (unknown error), set to default level
	lb_set_log_level "$log_level" || lb_set_log_level INFO

	# defines verbose level
	# if not set (unknown error), set to default level
	lb_set_display_level "$verbose_level" || lb_set_display_level INFO
}


# Test if backup destination support hard links
# Usage: test_hardlinks PATH
# Exit codes:
#   0: destination supports hard links
#   1: cannot get filesystem type
#   2: destination does not support hard links
test_hardlinks() {

	# supported filesystems on Linux, macOS and Windows
	local supported_fstypes=(ext2 ext3 ext4 btrfs aufs \
		hfs hfsplus apfs \
		ntfs)

	# get destination filesystem
	local fstype
	fstype=$(lb_df_fstype "$*")

	# filesystem not found: quit
	[ -z "$fstype" ] && return 1

	# if destination filesystem does not support hard links, return error
	lb_in_array "$fstype" "${supported_fstypes[@]}" || return 2
}


# Test space available on disk
# Usage: test_space_available BACKUP_SIZE_IN_BYTES PATH
# Exit codes:
#   0: space ok for backup
#   1: not enough space
test_space_available() {

	# if 0, always OK
	[ "$1" == 0 ] && return 0

	local space_available=$(lb_df_space_left "$2")

	# if there was an unknown error, continue
	if ! lb_is_integer $space_available ; then
		lb_display --log "Cannot get available space. Trying to backup although."
		return 0
	fi

	# transform space size from KB to bytes
	space_available=$(($space_available * 1024))

	debug "Space available on disk (in bytes): $space_available"

	# if space is not enough, error
	if [ $space_available -lt $1 ] ; then
		debug "Not enough space on device! Needed (in bytes): $1/$space_available"
		return 1
	fi
}


# Get readable backup date
# Usage: get_backup_date [OPTIONS] YYYY-MM-DD-HHMMSS
# Options:
#   -t  Get timestamp instead of date
# Dependencies: $tr_readable_date
# Return: backup datetime (format YYYY-MM-DD HH:MM:SS)
# e.g. 2016-12-31-233059 -> 2016-12-31 23:30:59
# Exit codes:
#   0: OK
#   1: format error
get_backup_date() {

	local format=$tr_readable_date

	# get timestamp option
	if [ "$1" == '-t' ] ; then
		format='%s'
		shift
	fi

	# test backup format
	check_backup_date "$*" || return 1

	# get date details
	local byear=${1:0:4} bmonth=${1:5:2} bday=${1:8:2} \
	      bhour=${1:11:2} bmin=${1:13:2} bsec=${1:15:2}

	# return date formatted for languages
	case $lb_current_os in
		BSD|macOS)
			date -j -f "%Y-%m-%d %H:%M:%S" "$byear-$bmonth-$bday $bhour:$bmin:$bsec" +"$format"
			;;
		*)
			date -d "$byear-$bmonth-$bday $bhour:$bmin:$bsec" +"$format"
			;;
	esac
}


# Get backup history of a file
# Usage: get_backup_history [OPTIONS] PATH
# Options:
#   -a  get all versions (including same)
#   -l  get only last version
#   -n  get non-empty directories
#   -z  except latest backup
# Dependencies: $remote_destination, $destination
# Return: dates (YYYY-MM-DD-HHMMSS format)
# Exit codes:
#   0: OK
#   1: usage error
#   2: no backups found
#   3: cannot found backups (no absolute path, deleted parent directory)
get_backup_history() {

	# remote destination: do nothing
	lb_istrue $remote_destination && return 0

	# default options
	local all_versions=false last_version=false not_empty=false not_latest=false

	# get options
	while [ $# -gt 0 ] ; do
		case $1 in
			-a)
				all_versions=true
				;;
			-l)
				last_version=true
				;;
			-n)
				not_empty=true
				;;
			-z)
				not_latest=true
				;;
			*)
				break
				;;
		esac
		shift # load next argument
	done

	# usage error
	[ $# == 0 ] && return 1

	# get all backups
	local all_backups=($(get_backups))

	# no backups found
	[ ${#all_backups[@]} == 0 ] && return 2

	# get backup path
	local gbh_backup_path
	gbh_backup_path=$(get_backup_path "$*")
	[ -z "$gbh_backup_path" ] && return 3

	# subtility: path/to/symlink_dir/ is not detected as a link,
	# but so does path/to/symlink_dir
	# so we return path without the last /
	gbh_backup_path=$(remove_end_slash "$gbh_backup_path")

	# prepare for loop
	local inode last_inode symlink_target last_symlink_target gbh_date gbh_backup_file first=true
	local -i i nb_versions=0

	# try to find backup from latest to oldest
	for ((i=${#all_backups[@]}-1 ; i>=0 ; i--)) ; do

		gbh_date=${all_backups[i]}

		# check if file/directory exists
		gbh_backup_file=$destination/$gbh_date/$gbh_backup_path

		# if file/directory does not exists, continue
		[ -e "$gbh_backup_file" ] || continue

		# check if a backup is currently running

		# ignore current backup (if running, it could contain errors)
		[ "$(current_lock)" == "$gbh_date" ] && continue

		# if get only non empty directories
		if $not_empty && [ -d "$gbh_backup_file" ] ; then
			lb_is_dir_empty "$gbh_backup_file" && continue
		fi

		# except the latest
		if $not_latest && $first ; then
			first=false
			continue
		fi

		# if get only last version, print and exit
		if $last_version ; then
			echo $gbh_date
			return 0
		fi

		# if get all versions, do not compare files and continue
		if $all_versions ; then
			echo $gbh_date
			nb_versions+=1
			continue
		fi

		#  DIRECTORIES

		if [ -d "$gbh_backup_file" ] ; then
			# if it's not a symlink,
			if ! [ -L "$gbh_backup_file" ] ; then
				# TODO: DETECT DIRECTORY CHANGES with diff command
				# for now, just add it to list
				echo $gbh_date
				nb_versions+=1
				continue
			fi
		fi

		#  SYMLINKS

		if [ -L "$gbh_backup_file" ] ; then
			# detect if symlink target has changed
			# TODO: move this part to directory section and test target file inodes
			symlink_target=$(readlink "$gbh_backup_file")

			if [ "$symlink_target" != "$last_symlink_target" ] ; then
				echo $gbh_date
				nb_versions+=1

				# save target to compare to the next one
				last_symlink_target=$symlink_target
			fi

			continue
		fi

		#  REGULAR FILES

		# compare inodes to detect different versions
		case $lb_current_os in
			BSD|macOS)
				inode=$(stat -f %i "$gbh_backup_file")
				;;
			*)
				inode=$(stat --format %i "$gbh_backup_file")
				;;
		esac

		if [ "$inode" != "$last_inode" ] ; then
			echo $gbh_date
			nb_versions+=1

			# save last inode to compare to next
			last_inode=$inode
		fi
	done

	[ $nb_versions -gt 0 ] || return 2
}


# Get path of a file backup
# Usage: get_backup_path PATH
# Return: backup path (e.g. /home/user -> /files/home/user)
# Exit codes:
#   0: OK
#   1: cannot get original path (not absolute and parent directory does not exists)
get_backup_path() {

	local path=$*

	# if absolute path (first character is a /), return file path
	if [ "${path:0:1}" == / ] ; then
		echo "/files$path"
		return 0
	fi

	# get protocol
	local protocol
	protocol=$(get_protocol "$path")

	# if not absolute path, check protocols
	case $protocol in
		ssh)
			# transform ssh://user@hostname/path/to/file -> /ssh/hostname/path/to/file

			# get ssh user@host
			local ssh_host ssh_hostname
			ssh_host=$(url2host "$path")
			ssh_hostname=$(echo "$ssh_host" | cut -d@ -f2)

			# get ssh path
			local ssh_prefix=$protocol://$ssh_host
			local ssh_path=${path#$ssh_prefix}

			# return complete path
			echo "/$protocol/$ssh_hostname/$ssh_path"
			return 0
			;;
	esac

	# if file or directory (relative path)

	# if not exists (file moved or deleted), try to get parent directory path
	if [ -e "$path" ] ; then
		echo -n "/files/$(lb_abspath "$path")"

		# if it is a directory, add '/' at the end of the path
		[ -d "$path" ] && echo /
	else
		if [ -d "$(dirname "$path")" ] ; then
			echo "/files/$(lb_abspath "$path")"
		else
			# if not exists, I cannot guess original path
			lb_error "File does not exist."
			lb_error "If you want to restore a deleted file, please specify an absolute path."
			return 1
		fi
	fi
}


# Get all backup dates
# Usage: get_backups [PATH]
# Dependencies: $destination, $backup_date_format, $ssh_options
# Return: dates list (format YYYY-MM-DD-HHMMSS)
# Exit codes:
#   0: OK
#   1: error for the path
get_backups() {
	# default options
	local path=$destination

	# get specified path option
	[ -n "$1" ] && path=$*

	case $(get_protocol "$path") in
		ssh)
			ssh "${ssh_options[@]}" "$(url2host "$path")" "ls \"$(url2path "$path")\"" 2> /dev/null | grep -E "^$backup_date_format$"
			;;
		*)
			# return content of path (only the backup folders)
			ls "$path" 2> /dev/null | grep -E "^$backup_date_format$"
			;;
	esac

	# return error only if ls command failed
	return ${PIPESTATUS[0]}
}


# Delete a backup
# Usage: delete_backup DATE_REFERENCE
# Dependencies: $destination, $logfile, $logs_directory
# Exit codes:
#   0: delete OK
#   1: usage error
#   2: rm error
delete_backup() {

	# usage error
	[ -z "$1" ] && return 1

	# delete log file
	debug "Deleting log file time2backup_$1.log..."
	rm -f "$logs_directory/time2backup_$1.log" || \
		lb_display_error --log "Failed to delete $logs_directory/time2backup_$1.log. Please delete this file manually."

	# delete backup directory
	debug "Deleting $destination/$1..."
	rm -rf "$destination/$1"
	if [ $? != 0 ] ; then
		lb_display_error --log "Failed to delete backup $1! Please delete this folder manually."
		return 2
	fi
}


# Clean old backups
# Usage: rotate_backups [LIMIT]
# Dependencies: $clean_keep, $keep_limit, $tr_*
# Exit codes:
#   0: rotate OK
#   1: usage error
#   2: nothing rotated
#   3: delete error
rotate_backups() {

	local limit=$keep_limit

	# limit specified
	[ -n "$1" ] && limit=$1

	# if unlimited, do not rotate
	[ "$limit" == -1 ] && return 0

	# remote destination
	if lb_istrue $remote_destination ; then
		debug "Rotate on remote server..."
		"${t2bserver_cmd[@]}" rotate $1
		return $?
	fi

	# get all backups
	local all_backups=($(get_backups)) b to_rotate=()
	local nb_backups=${#all_backups[@]}

	# clean based on number of backups
	if lb_is_integer $limit ; then
		# always keep nb + 1 (do not delete latest backup)
		limit=$(($limit + 1))

		# if limit not reached, do nothing
		[ $nb_backups -le $limit ] && return 0

		debug "Clean to keep $limit backups on $nb_backups"

		# get old backups until max - nb to keep
		to_rotate=(${all_backups[@]:0:$(($nb_backups - $limit))})

	else
		# clean based on time periods
		local t time_limit=$(($current_timestamp - $(period2seconds $limit)))

		for b in "${all_backups[@]}" ; do
			# do not delete the only backup
			[ $nb_backups -le 1 ] && break

			# do not delete over clean_keep value
			[ $nb_backups -le $clean_keep ] && break

			# get timestamp of this backup
			t=$(get_backup_date -t $b)
			lb_is_integer $t || continue

			# time limit reached: stop iterate
			[ $t -ge $time_limit ] && break

			debug "Clean old backup $b because < $limit"

			# add backup to list to clean
			to_rotate+=("$b")

			# decrement nb of current backups
			nb_backups=$(($nb_backups - 1))
		done
	fi

	# nothing to clean: quit
	if [ ${#to_rotate[@]} == 0 ] ; then
		debug "Nothing to rotate"
		return 0
	fi

	lb_display --log "Cleaning old backups..."
	notify "$tr_notify_rotate_backup"

	# remove backups from older to newer
	local result=0
	for b in "${to_rotate[@]}" ; do
		delete_backup "$b" || result=3
	done

	return $result
}


# Print report of duration from start of script to now
# Usage: report_duration
# Dependencies: $current_timestamp, $tr_report_duration
# Return: complete report with elapsed time in HH:MM:SS
report_duration() {

	# calculate duration
	local duration=$(($(date +%s) - $current_timestamp))

	# print report
	echo "$tr_report_duration $(($duration/3600)):$(printf "%02d" $(($duration/60%60))):$(printf "%02d" $(($duration%60)))"
}


# Test if destination is reachable and mount it if needed
# Usage: prepare_destination
# Dependencies: $remote_destination, $destination, $smb_destination, $config_file,
#               $mount, $mounted, $backup_disk_mountpoint, $unmount_auto,
#               $recurrent_backup, $hard_links, $force_hard_links, $tr_*
# Exit codes:
#   0: destination is ready
#   1: destination not reachable
#   2: destination not writable
prepare_destination() {

	# remote destination: do nothing
	lb_istrue $remote_destination && return 0

	debug "Testing destination on: $destination..."

	# subdirectories removed since 1.3.0
	local new_destination=$destination/backups/$lb_current_hostname
	if [ -d "$new_destination" ] ; then
		debug "Migration destination path to: $new_destination"
		destination=$new_destination
		lb_set_config "$config_file" destination "$new_destination"
	fi

	local destok=false

	# test backup destination directory
	if [ -d "$destination" ] ; then
		destok=true

		# smb destination
		if [ -n "$smb_destination" ] ; then
			# compare mountpoint to avoid writing on an unmounted directory
			[ "$(lb_df_mountpoint "$destination")" != "$(dirname "$backup_disk_mountpoint"/dummy)" ] && \
				destok=false
		fi
	fi

	if $destok ; then
		debug "Destination mounted."
		mounted=true
	else
		debug "Destination NOT mounted."

		# if automount set and backup disk mountpoint is defined,
		# try to mount disk
		if lb_istrue $mount && [ -n "$backup_disk_mountpoint" ] ; then
			mount_destination && destok=true
		fi
	fi

	# error message if destination not ready
	if ! $destok ; then
		lb_display --log "Backup destination is not reachable.\nPlease verify if your media is plugged in and try again."
		return 1
	fi

	# auto unmount: unmount if it was NOT mounted
	if lb_istrue $unmount_auto && ! lb_istrue $mounted ; then
		unmount=true
	fi

	# create destination if not exists & test if is writable
	mkdir -p "$destination" &> /dev/null && [ -w "$destination" ]
	if [ $? != 0 ] ; then
		# if mkdir failed, exit
		if lb_istrue $recurrent_backup ; then
			# don't popup in recurrent mode
			lb_display_error "$tr_write_error_destination\n$tr_verify_access_rights"
		else
			lbg_error "$tr_write_error_destination\n$tr_verify_access_rights"
		fi
		return 2
	fi

	# check if destination supports hard links
	if lb_istrue $hard_links && ! lb_istrue $force_hard_links ; then
		if ! test_hardlinks "$destination" ; then
			# filesystem does not support hard links
			debug "Destination does not support hard links. Continue in trash mode."
			hard_links=false
		fi
	fi
}


# Test free space on disk and remove old backups until it's ready
# Usage: free_space SIZE
# Dependencies: $destination, $clean_old_backups, $clean_keep,
#               $last_clean_backup, $tr_*
# Exit codes:
#   0: OK
#   1: not OK
free_space() {

	local i all_backups=($(get_backups))
	local nb_backups=${#all_backups[@]}

	# test free space until it's ready
	for ((i=0; i<=$nb_backups; i++)) ; do

		# if space ok, quit loop to continue backup
		test_space_available $1 "$destination" && return 0

		# if no clean old backups option in config, continue to be stopped after
		lb_istrue $clean_old_backups || return 1

		# display clean notification
		# (just display the first notification, not for every clean)
		if [ $i == 0 ] ; then
			notify "$tr_notify_cleaning_space"
			lb_display --log "Not enough space on device. Clean old backups to free space..."
		fi

		# recheck all backups list (more safety)
		all_backups=($(get_backups))

		# do not remove the last backup, nor the current
		[ ${#all_backups[@]} -le 2 ] && return 1

		# always keep the current backup and respect the clean limit
		# (continue to be stopped after)
		if [ $clean_keep -gt 0 ] ; then
			[ ${#all_backups[@]} -le $clean_keep ] && return 1
		fi

		# do not delete the last clean backup that will be used for hard links
		[ "${all_backups[0]}" == "$last_clean_backup" ] && continue

		# clean oldest backup to free space
		delete_backup ${all_backups[0]}
	done

	# if all finished, error
	return 1
}


# Delete empty backup directory
# Usage: clean_empty_backup [OPTIONS] BACKUP_DATE [PATH]
# Options:
#   -i Delete infofile if exists
# Dependencies: $destination
# Exit codes:
#   0: cleaned
#   1: usage error or path is not a directory
clean_empty_backup() {

	# remote destination: do nothing
	lb_istrue $remote_destination && return 0

	local delete_infofile=false

	while [ $# -gt 0 ] ; do
		case $1 in
			-i)
				delete_infofile=true
				;;
			*)
				break
				;;
		esac
		shift
	done

	# backup date not defined: usage error
	[ -n "$1" ] || return 1

	# if backup does not exists, quit
	[ -d "$destination/$1" ] || return 0

	if [ -n "$2" ] ; then
		local d=$2
		# destination path does not exists: get parent
		[ -d "$destination/$1/$d" ] || d=$(dirname "$2")

		if lb_is_dir_empty "$destination/$1/$d" ; then
			debug "Clean empty backup: $1/$d"
			dummy=$(cd "$destination" &> /dev/null && rmdir -p "$1/$d" &> /dev/null)
		fi
	fi

	if $delete_infofile && \
	   [ "$(ls "$destination/$1" 2> /dev/null)" == backup.info ] ; then
		debug "Clean info file of backup $1"
		rm -f "$destination/$1/backup.info" &> /dev/null
	fi

	# if not empty, do nothing
	lb_is_dir_empty "$destination/$1" || return 0

	debug "Clean empty backup: $1"

	# delete and prevent loosing context
	dummy=$(cd "$destination" &> /dev/null && rmdir "$1" &> /dev/null)

	return 0
}


# Auto exclude the backup directory if it is inside destination
# Usage: auto_exclude PATH
# Dependencies: $destination
# Exit codes:
#   0: path excluded (or no result)
#   1: failed
auto_exclude() {

	# if destination not inside, quit
	[[ "$destination" != "$1"* ]] && return 0

	# get common path of the backup directory and source
	# e.g. /media
	local common_path
	common_path=$(get_common_path "$destination" "$1") || return 1

	# get relative exclude directory
	# e.g. /user/device/path/to/backups
	local exclude_path=${destination#$common_path}

	[ "${exclude_path:0:1}" != / ] && exclude_path=/$exclude_path

	# return path to exclude
	echo "$exclude_path"
}


# Run a command then retry in sudo if failed
# Usage: try_sudo COMMAND
# Exit codes:
#   0: command OK
#   1: command failed
try_sudo() {
	# run command
	"$@"
	local result=$?

	# if failed, retry in sudo
	if [ $result != 0 ] ; then
		# if sudo exists and not root
		if lb_command_exists sudo && [ "$lb_current_user" != root ] ; then
			debug "...Failed! Try with sudo..."
			sudo "$@"
			result=$?
		fi
	fi

	return $result
}


#
#  Config functions
#

# Create config file from template
# Usage: create_config_from_template FILE TEMPLATE
# Exit codes:
#   0: OK
#   1: error
create_config_from_template() {
	# test if file exists and not empty
	[ -f "$1" ] && [ -s "$1" ] && return 0

	# copy from template
	cp -f "$lb_current_script_directory"/config/${2}.example.conf "$1"
	if [ $? != 0 ] ; then
		lb_error "Cannot create $2 config file."
		return 1
	fi

	# transform to windows format, do not care of errors
	file_for_windows "$1"
	return 0
}


# Create configuration files in user config
# Usage: create_config
# Dependencies: $config_directory, $config_file, $config_excludes, $config_sources
# Exit codes:
#   0: OK
#   1: error
create_config() {

	# create config directory
	# default: ~/.config/time2backup
	mkdir -p "$config_directory" &> /dev/null
	if [ $? != 0 ] ; then
		lb_error "Cannot create config directory. Please verify your access rights or home path."
		return 1
	fi

	# create config files from templates if needed
	create_config_from_template "$config_excludes" excludes && \
	create_config_from_template "$config_sources" sources && \
	create_config_from_template "$config_file" time2backup
	[ $? != 0 ] && return 1

	# if user is different, try to give him ownership on config files
	if [ $user != $lb_current_user ] ; then
		chown -R $user "$config_directory" &> /dev/null
	fi

	return 0
}


# Upgrade configuration
# Usage: upgrade_config
# Dependencies: $version, $config_file, $version, $quiet_mode, $command, $tr_*
# Exit codes:
#   0: upgrade OK
#   1: compatibility error
#   2: write error
upgrade_config() {

	# get current config version
	local old_config_version
	old_config_version=$(grep "time2backup configuration file v" "$config_file" | grep -o "[0-9].[0-9].[0-9]")
	if [ -z "$old_config_version" ] ; then
		lb_display_error "Cannot get config version."
		return 1
	fi

	# if current version, OK
	[ "$old_config_version" == "$version" ] && return 0

	if ! lb_istrue $quiet_mode ; then
		case $command in
			""|backup|restore)
				echo
				lb_print "$tr_upgrade_config"
				;;
		esac
		debug "Upgrading config v$old_config_version -> v$version"
	fi

	# save old config file
	local new_config=$config_file.v$version

	cat "$lb_current_script_directory"/config/time2backup.example.conf > "$new_config"
	if [ $? != 0 ] ; then
		lb_display_error "$tr_error_upgrade_config"
		return 2
	fi

	# transform Windows file
	file_for_windows "$new_config"

	# upgrade config & install it
	# Note: we avoid to create new files every time
	lb_migrate_config "$config_file" "$new_config" && \
	cat "$new_config" > "$config_file" && \
	rm -f "$new_config"

	if [ $? != 0 ] ; then
		lb_display_error "$tr_error_upgrade_config"
		return 2
	fi
}


# Load configuration file
# Usage: load_config
# Dependencies: $config_sources, $config_directory, $config_file, $command, $quiet_mode,
#               $force_destination, $destination, $logs_directory, $keep_limit, $tr_*
# Exit codes:
#   0: OK
#   1: cannot open config
#   2: there are errors in config
load_config() {

	if ! lb_istrue $quiet_mode ; then
		case $command in
			""|backup|restore)
				echo -e "\n$tr_loading_config\n"
				;;
		esac
	fi

	# test if sources file exists
	if ! [ -f "$config_sources" ] ; then
		lb_error "No sources file found!"
		return 1
	fi

	# load config
	if ! lb_import_config "$config_file" ; then
		lb_display_error "$tr_error_read_config"
		return 1
	fi

	# if destination is overriden, set it
	[ -n "$force_destination" ] && destination=$force_destination

	# test if destination is defined
	if [ -z "$destination" ] ; then
		lb_error "Destination is not set!"
		return 2
	fi

	case $(get_protocol "$destination") in
		ssh)
			# remote destination
			remote_destination=true

			# get time2backup server command
			t2bserver_cmd=(ssh "${ssh_options[@]}" "$(url2host "$destination")")

			# server in sudo mode
			lb_istrue $remote_sudo && t2bserver_cmd+=(sudo)

			# server command path
			if [ -n "$t2bserver_path" ] ; then
				t2bserver_cmd+=("$t2bserver_path")
			else
				t2bserver_cmd+=(time2backup-server)
			fi

			# server password
			[ -n "$t2bserver_pwd" ] && t2bserver_cmd+=(-p "$t2bserver_pwd")

			# define the default logs path to the local config directory
			[ -z "$logs_directory" ] && logs_directory=$config_directory/logs

			# disable test destination
			test_destination=false
			;;

		*)
			# normal destination

			# samba shares
			if [ "${destination:0:2}" == // ] ; then
				# test mount point
				if [ -z "$backup_disk_mountpoint" ] ; then
					lb_error "Destination is a SMB share but has no disk mountpoint. Please add it in configuration."
					return 2
				fi

				# replace destination variable by mountpoint and save smb path
				smb_destination=$destination
				destination=$backup_disk_mountpoint
			fi

			# convert destination path for Windows systems
			if [ "$lb_current_os" == Windows ] ; then
				destination=$(cygpath "$destination")

				if [ $? != 0 ] ; then
					lb_error "Error in Windows destination path!"
					return 2
				fi
			fi

			# define the default logs path
			[ -z "$logs_directory" ] && logs_directory=$destination/logs
			;;
	esac

	# other specific tests

	if lb_is_integer $keep_limit ; then
		if [ $keep_limit -lt -1 ] ; then
			lb_error "keep_limit should be a positive integer, or -1 for unlimited"
			return 2
		fi
	else
		if ! test_period "$keep_limit" ; then
			lb_error "keep_limit should be an integer or a valid period"
			return 2
		fi
	fi

	if ! lb_is_integer $clean_keep || [ $clean_keep -lt 0 ] ; then
		lb_error "clean_keep should be a positive integer"
		return 2
	fi

	# init some variables

	# increment clean_keep to 1 to keep the current backup
	clean_keep=$(($clean_keep + 1))

	# set default rsync path if not defined or if custom commands not allowed
	if [ -z "$rsync_path" ] || lb_istrue $disable_custom_commands ; then
		rsync_path=$default_rsync_path
	fi

	# set default shutdown command or if custom commands not allowed
	if [ ${#shutdown_cmd[@]} == 0 ] || lb_istrue $disable_custom_commands ; then
		shutdown_cmd=("${default_shutdown_cmd[@]}")
	fi
}


# Enable/disable cron jobs
# Usage: crontab_config enable|disable
# Dependencies: $config_directory, $user
# Exit codes:
#   0: OK
#   1: usage error
#   2: cannot access to crontab
#   3: cannot install new crontab
#   4: cannot write into the temporary crontab file
crontab_config() {

	local crontab crontab_opts=() crontab_enable=false

	[ "$1" == enable ] && crontab_enable=true

	# prepare backup task in quiet mode
	local crontask="\"$lb_current_script\" -q -c \"$config_directory\" backup --recurrent"

	# if root, use crontab -u option
	# Note: macOS does supports -u option only if current user is root
	if [ "$lb_current_user" == root ] && [ "$user" != root ] ; then
		crontab_opts+=(-u $user)
	fi

	# check if crontab exists
	crontab=$(crontab "${crontab_opts[@]}" -l 2>&1)
	if [ $? != 0 ] ; then
		# special case for error when no crontab
		if echo "$crontab" | grep -q "no crontab for " ; then
			# if empty and disable mode: nothing to do
			$crontab_enable || return 0

			# reset crontab
			crontab=""
		else
			# if other error (cannot access to user crontab)

			# inform user to add cron job manually
			if $crontab_enable ; then
				lb_display --log "Failed! \nPlease edit crontab manually and add the following line:"
				lb_display --log "* * * * *	$crontask"
				return 2
			else
				# we don't care
				return 0
			fi
		fi
	fi

	# test if task exists (get line number)
	local line
	line=$(echo "$crontab" | grep -n "^\* \* \* \* \*\s*$crontask" | cut -d: -f1)
	if [ -n "$line" ] ; then
		if $crontab_enable ; then
			# do nothing
			return 0
		else
			# disable: delete crontab entry lines
			crontab=$(echo "$crontab" | sed "/^\# time2backup recurrent backups/d ; ${line}d") || return 4
		fi

	else
		# if cron task does not exists,
		# if old entry exists, rename it
		line=$(echo "$crontab" | grep -n "\* \* \* \* \*\s*\"$lb_current_script\" -q backup --recurrent" | cut -d: -f2)
		if [ -n "$line" ] ; then
			crontab=$(echo "$crontab" | sed "${line}s/.*/\* \* \* \* \*	$crontask/")
		fi

		if $crontab_enable ; then
			# append command to crontab
			crontab+=$(echo -e "\n# time2backup recurrent backups\n* * * * *\t$crontask")
		else
			# do nothing
			return 0
		fi
	fi

	# install new crontab
	echo "$crontab" | crontab "${crontab_opts[@]}" - || return 3
}


# Install configuration (recurrent tasks, ...)
# Usage: apply_config
# Dependencies: $enable_recurrent, $recurrent
# Exit codes:
#   0: OK
#   other: failed (exit code forwarded from crontab_config)
apply_config() {

	# if disabled, do not continue
	lb_istrue $enable_recurrent || return 0

	if lb_istrue $recurrent ; then
		echo "Enable recurrent backups..."
		crontab_config enable
	else
		echo "Disable recurrent backups..."
		crontab_config disable
	fi
}


# Edit configuration
# Usage: open_config [OPTIONS] CONFIG_FILE
# Options:
#   -e COMMAND  use a custom text editor
# Dependencies: $console_mode
# Exit codes:
#   0: OK
#   1: usage error
#   3: failed to open configuration
#   4: no editor found to open configuration file
open_config() {

	# default values
	local editors=(nano vim vi)
	local all_editors=()
	local custom_editor=false

	# get options
	while [ $# -gt 0 ] ; do
		case $1 in
			-e)
				[ -z "$2" ] && return 1
				editors=("$2")
				custom_editor=true
				shift
				;;
			*)
				break
				;;
		esac
		shift # load next argument
	done

	# usage error
	[ -z "$1" ] && return 1

	local edit_file=$*

	# test file
	if [ -e "$edit_file" ] ; then
		# if exists but is not a file, return error
		[ -f "$edit_file" ] || return 1
	else
		# create empty file if it does not exists (should be includes.conf)
		echo > "$edit_file"
	fi

	# if no custom editor, open file with graphical editor
	# check if we are using something else than a console
	if ! $custom_editor && ! lb_istrue $console_mode && [ "$(lbg_get_gui)" != console ] ; then
		case $lb_current_os in
			macOS)
				all_editors+=(open -t)
				;;
			Windows)
				all_editors+=(notepad)
				;;
			*)
				all_editors+=(xdg-open)
				;;
		esac
	fi

	# add console editors or chosen one
	all_editors+=("${editors[@]}")

	# select an editor
	for e in "${all_editors[@]}" ; do
		# test if editor exists
		if lb_command_exists "$e" ; then
			editor=$e
			break
		fi
	done

	# run text editor and wait for it to close
	if [ -n "$editor" ] ; then
		# Windows: transform to Windows path like c:\...\time2backup.conf
		if [ "$lb_current_os" == Windows ] ; then
			edit_file=$(cygpath -w "$edit_file")
		fi

		# open editor and wait until process ends (does not work with all editors)
		"$editor" "$edit_file" 2> /dev/null
		wait $! 2> /dev/null
	else
		if $custom_editor ; then
			lb_error "Editor '$editor' was not found on this system."
		else
			lb_error "No editor was found on this system."
			lb_error "Please edit $edit_file manually."
		fi

		return 4
	fi

	if [ $? != 0 ] ; then
		lb_error "Failed to open configuration."
		lb_error "Please edit $edit_file manually."
		return 3
	fi
}


#
#  Log functions
#

# Create log file
# Usage: create_logfile PATH
# Exit codes:
#   0: OK
#   1: failed to create log directory
#   2: failed to create log file
create_logfile() {
	# create logs directory
	mkdir -p "$(dirname "$*")"
	if [ $? != 0 ] ; then
		lb_display_error "Could not create logs directory. Please verify your access rights."
		return 1
	fi

	local opts=()

	# windows: write logs with good end of lines
	[ "$lb_current_os" == Windows ] && opts+=(--win-format)

	# create log file
	if ! lb_set_logfile "${opts[@]}" "$*" ; then
		lb_display_error "Cannot create log file $*. Please verify your access rights."
		return 2
	fi
}


# Delete log file
# Usage: delete_logfile
# Dependencies: $logfile, $logs_directory
# Exit codes:
#   0: logfile deleted
#   1: failed to delete
delete_logfile() {
	# delete log file (and quit if error)
	rm -f "$logfile" &> /dev/null || return 1

	# delete logs directory if empty
	rmdir "$logs_directory" &> /dev/null

	# always OK (rmdir failed is not an error)
	return 0
}


#
#  Infofile functions
#

# Create infofile
# Usage: create_infofile
# Dependencies: $remote_destination, $destination, $backup_date, $infofile
#               $version, $recurrent_backup, $backup_comment
# Exit codes:
#   0: infofile created
#   1: not created
create_infofile() {

	# remote destination: do nothing
	lb_istrue $remote_destination && return 0

	# create directory
	mkdir -p "$destination/$backup_date"
	if [ $? != 0 ] ; then
		lb_display_error --log "Could not prepare backup destination. Please verify your access rights."
		clean_exit 7
	fi

	infofile=$destination/$backup_date/backup.info

	# avoid erase existing infofile
	[ -f "$infofile" ] && return 0

	# create infofile
	touch "$infofile" && \
	echo "[time2backup]
version = $version
os = $lb_current_os
hostname = $lb_current_hostname
recurrent = $recurrent_backup
comment = $backup_comment

[destination]
path = \"$destination\"
date = $backup_date
hard_links = $hard_links" > "$infofile"
}


# Find section that matches a path in an infofile
# Usage: find_infofile_section INFO_FILE PATH
# Return: section name
# Exit codes:
#   0: section found
#   1: section not found
#   2: file does not exists
find_infofile_section() {

	# if file does not exists, quit
	[ -f "$1" ] || return 2

	local section path

	# search in sections, ignoring global sections
	for section in $(grep -Eo "^\[src.*\]" "$1" 2> /dev/null | tr -d '[]') ; do

		# get path of the backup
		path=$(lb_get_config -s "$section" "$1" path)

		if [ -n "$path" ] && [[ "$2" == "$path"* ]] ; then
			echo $section
			return 0
		fi
	done

	# not found
	return 1
}


# Get value from an infofile
# Usage: get_infofile_value INFO_FILE SOURCE_PATH PARAM
# Return: value
# Exit code:
#   0: OK
#   1: section not found
#   2: parameter not found
get_infofile_value() {
	# search section
	local infofile_section=$(find_infofile_section "$1" "$2")
	[ -z "$infofile_section" ] && return 1

	# get value
	lb_get_config -s "$infofile_section" "$1" "$3" || return 2
}


#
#  Mount functions
#

# Mount destination
# Usage: mount_destination
# Dependencies: $remote_destination, $backup_disk_uuid, $backup_disk_mountpoint,
#               $smb_destination
# Exit codes:
#   0: mount OK
#   1: mount error
#   2: disk not available
#   3: cannot create mount point
#   4: command not supported
#   5: no disk UUID set in config
#   6: cannot delete mount point
mount_destination() {

	# remote destination: do nothing
	lb_istrue $remote_destination && return 0

	lb_display --log "Trying to mount backup disk..."

	local mount_cmd=(mount)

	# samba shares
	if [ -n "$smb_destination" ] ; then
		# IMPORTANT: delete ACL or it will fail
		mount_cmd+=(-o noacl "$smb_destination")
	else
		# if UUID not set, return error
		[ -z "$backup_disk_uuid" ] && return 5

		# macOS and Windows are not supported
		# this is not supposed to happen because macOS and Windows always mount disks
		if [ "$lb_current_os" != Linux ] ; then
			lb_display_error --log "Mount: $lb_current_os not supported"
			return 4
		fi

		# test if UUID exists (disk plugged)
		ls /dev/disk/by-uuid/ 2> /dev/null | grep -q "$backup_disk_uuid"
		if [ $? != 0 ] ; then
			debug "Disk not available."
			return 2
		fi

		mount_cmd+=(-U "$backup_disk_uuid")
	fi

	# create mountpoint
	if ! [ -d "$backup_disk_mountpoint" ] ; then

		lb_display --log "Create disk mountpoint..."
		try_sudo mkdir -p "$backup_disk_mountpoint"

		if [ $? != 0 ] ; then
			lb_display --log "...Failed!"
			return 3
		fi
	fi

	# mount disk
	lb_display --log "Mount backup disk..."
	try_sudo "${mount_cmd[@]}" "$backup_disk_mountpoint"
	local result=$?

	# stupid Windows does not return error even if mount fails
	if [ $result == 0 ] && [ "$lb_current_os" == Windows ] ; then
		# test if mountpoint is writable; if not, unmount and return error
		if ! [ -w "$backup_disk_mountpoint" ] ; then
			umount "$backup_disk_mountpoint" &> /dev/null
			result=1
		fi
	fi

	if [ $result != 0 ] ; then
		lb_display --log "...Failed! Delete mountpoint..."

		try_sudo rmdir "$backup_disk_mountpoint"
		if [ $? != 0 ] ; then
			lb_display --log "...Failed!"
			return 6
		fi

		# mount failed
		return 1
	fi
}


# Unmount destination
# Usage: unmount_destination
# Dependencies: $destination, $remote_destination
# Exit codes:
#   0: OK
#   1: cannot get destination mountpoint
#   2: umount error
#   3: cannot delete mountpoint
unmount_destination() {

	# remote destination: do nothing
	lb_istrue $remote_destination && return 0

	# no unmount: do nothing
	lb_istrue $unmount || return 0

	lb_display --log "Unmount destination..."

	# get mount point
	local destination_mountpoint
	destination_mountpoint=$(lb_df_mountpoint "$destination")
	if [ $? != 0 ] ; then
		lb_display_error "Cannot get mountpoint of $destination"
		return 1
	fi

	# unmount
	try_sudo umount "$destination_mountpoint"
	if [ $? != 0 ] ; then
		lb_display --log "...Failed!"
		return 2
	fi

	debug "Delete mount point..."
	try_sudo rmdir "$destination_mountpoint"
	if [ $? != 0 ] ; then
		lb_display --log "...Failed!"
		return 3
	fi
}


#
#  Lock functions
#

# Return date of the current lock (if exists)
# Usage: current_lock [OPTION]
# Options:
#   -f  Get the lock file path
#   -p  Get the process PID instead of lock date
#   -q  Quiet mode
# Dependencies: $remote_destination, $destination
# Return: date of lock, empty if no lock
# Exit code:
#   0: lock exists
#   1: lock does not exists
current_lock() {

	# remote destination: do nothing (return no lock exists)
	lb_istrue $remote_destination && return 1

	# get lock file
	local current_lock_file=$(ls "$destination"/.lock_* 2> /dev/null)

	# no lock
	[ -z "$current_lock_file" ] && return 1

	case $1 in
		-f)
			# return lock file path
			echo "$current_lock_file"
			;;
		-p)
			# return PID
			lb_get_config "$current_lock_file" pid
			;;
		-q)
			# quiet mode
			;;
		*)
			# return date of lock
			basename "$current_lock_file" | sed 's/^.lock_//'
			;;
	esac

	# always return ok
	return 0
}


# Create lock
# Usage: create_lock
# Dependencies: $remote_destination, $destination, $backup_date
# Exit code:
#   0: lock ok
#   1: unknown error
create_lock() {

	# do not create lock if remote destination
	lb_istrue $remote_destination && return 0

	debug "Create lock..."

	# create lock file with process PID inside
	touch "$destination/.lock_$backup_date" && lb_set_config "$destination/.lock_$backup_date" pid $$
}


# Delete backup lock
# Usage: release_lock [OPTIONS]
# Options:
#   -f  Force unlock
# Dependencies: $remote_destination, $destination, $backup_date, $recurrent_backup, $tr_*
# Exit codes:
#   0: OK
#   1: could not delete lock
release_lock() {

	# remote destination: do nothing
	lb_istrue $remote_destination && return 0

	local lock=$destination/.lock_

	[ "$1" != "-f" ] && lock+=$backup_date

	debug "Deleting lock..."

	# if destination exists, but no lock, return 0
	if [ -d "$destination" ] ; then
		current_lock -q || return 0
	fi

	# test if destination still exists, then delete lock
	[ -d "$destination" ] && rm -f "$lock"* &> /dev/null
	if [ $? != 0 ] ; then
		lb_display_critical --log "$tr_error_unlock"
		# display error if not recurrent
		lb_istrue $recurrent_backup || lbg_error "$tr_error_unlock"
		return 1
	fi
}


#
#  rsync functions
#

# Prepare rsync command and arguments in the $rsync_cmd variable
# Usage: prepare_rsync COMMAND
# Dependencies: $rsync_cmd, $rsync_path, $quiet_mode, $files_progress, $preserve_permissions, $config_includes, $config_excludes, $rsync_options, $max_size
prepare_rsync() {

	# basic command
	rsync_cmd=("$rsync_path" -rltDH)

	# options depending on configuration

	if ! lb_istrue $quiet_mode ; then
		rsync_cmd+=(-v)
		lb_istrue $files_progress && rsync_cmd+=(--progress)
	fi

	# remote rsync path
	if lb_istrue $remote_source ; then
		local rsync_remote_command=$(get_rsync_remote_command)
		[ -n "$rsync_remote_command" ] && rsync_cmd+=(--rsync-path "$rsync_remote_command")
	fi

	case $1 in
		import|export)
			# force preserve permissions
			rsync_cmd+=(-pog)
			;;

		*)
			# preserve permissions
			lb_istrue $preserve_permissions && rsync_cmd+=(-pog)

			# includes & excludes
			[ -f "$config_includes" ] && rsync_cmd+=(--include-from "$config_includes")
			[ -f "$config_excludes" ] && rsync_cmd+=(--exclude-from "$config_excludes")

			# user defined options
			[ ${#rsync_options[@]} -gt 0 ] && rsync_cmd+=("${rsync_options[@]}")
			;;
	esac

	# command-specific options

	case $1 in
		backup)
			# delete newer files
			rsync_cmd+=(--delete)

			# add max size if specified
			[ -n "$max_size" ] && rsync_cmd+=(--max-size "$max_size")
			;;

		import|export)
			rsync_cmd+=(--delete)
			;;
	esac
}


# Generate rsync remote command
# Usage: get_rsync_remote_command
# Dependencies: $remote_destination, $rsync_remote_path, $remote_sudo,
#               $t2bserver_path, $t2bserver_token, $t2bserver_pwd
# Return: Remote command
get_rsync_remote_command() {

	# time2backup server path
	if lb_istrue $remote_destination ; then

		if [ -n "$t2bserver_path" ] ; then
			echo -n "$t2bserver_path"
		else
			echo -n time2backup-server
		fi

		if [ -n "$t2bserver_token" ] ; then
			echo " -t $t2bserver_token"
		else
			[ -n "$t2bserver_pwd" ] && echo " -p $t2bserver_pwd"
		fi
	else
		# rsync remote path
		if [ -n "$rsync_remote_path" ] ; then
			lb_istrue $remote_sudo && echo -n 'sudo '
			echo "$rsync_remote_path"
		else
			lb_istrue $remote_sudo && echo 'sudo rsync'
		fi
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


#
#  Remote backups
#

# Prepare remote destination
# Usage: prepare_remote_destination COMMAND [ARGS]
# Dependencies: $t2bserver_cmd, $t2bserver_token, $logfile,
#               $destination, $hard_links, $last_clean_backup
prepare_remote_destination() {

	local response

	debug "Connect to remote server..."

	# run distant command
	response=$("${t2bserver_cmd[@]}" prepare "$@" 2>> "$logfile")

	if [ $? != 0 ] ; then
		lb_display_error --log "Remote server not reachable or not ready. Read log for more details."
		return 1
	fi

	debug "Server response:"
	debug "$response"

	# get infos from server response

	t2bserver_token=$(read_remote_config token "$response")
	[ -z "$t2bserver_token" ] && return 1

	# get remote backup path
	local remote_backup_path=$(read_remote_config destination "$response")
	[ -z "$remote_backup_path" ] && return 1

	destination=$(remove_end_slash "$destination")$remote_backup_path

	hard_links=false
	lb_istrue $(read_remote_config hard_links "$response") && hard_links=true
	last_clean_backup=$(read_remote_config trash "$response")

	return 0
}


# Usage: read_remote_config PARAM FILE_CONTENT
read_remote_config() {
	local param=$1
	shift

	echo "$*" | grep -En "^\s*$param\s*=" | sed "s/.*$param[[:space:]]*=[[:space:]]*//; s/[[:space:]]*$//; s/^\"\(.*\)\"$/\1/; s/^'\(.*\)'$/\1/; s/\\\\\"/\"/g"

	return ${PIPESTATUS[1]}
}


#
#  Backup steps
#

# Test backup command
# rsync simulation and get total size of the files to transfer
# Usage: test_backup COMMAND [ARGS...]
# Dependencies: $rsync_path, $logfile, $total_size
# Exit codes:
#   0: OK
#   1: rsync test command failed
test_backup() {

	lb_display --log "\nTesting backup..."

	# we ignore the first argument (rsync command)
	shift

	# prepare rsync in test mode
	# (append options to rsync command with erase of rsync path)
	local test_cmd=("$rsync_path" --dry-run --stats "$@")

	# rsync test
	# option dry-run makes a simulation for rsync
	# then we get the last line with the total amount of bytes to be copied
	# which is in format 999,999,999 so then we delete the commas
	debug "Testing rsync in dry-run mode: ${test_cmd[*]}..."

	total_size=$("${test_cmd[@]}" 2> >(tee -a "$logfile" >&2) | grep "Total transferred file size" | awk '{ print $5 }' | sed 's/,//g')

	# if rsync command not ok, error
	if ! lb_is_integer $total_size ; then
		debug "rsync test failed"
		return 1
	fi

	# add the space to be taken by the folders!
	# could be important if you have many folders

	# get the source path from rsync command (array size - 2)
	local src_folder=${test_cmd[${#test_cmd[@]}-2]}

	# get size of folders
	local folders_size=$(folders_size "$src_folder")

	# add size of folders to total size
	lb_is_integer $folders_size && total_size=$(($total_size + $folders_size))

	# add a security margin of 1MB for logs and future backups
	total_size=$(($total_size + 1000000))

	# force exit code to 0
	return 0
}


# Return backup estimated duration
# Usage: estimate_backup_time PATH BACKUP_SIZE
# Dependencies: $destination, $last_clean_backup
# Return: estimated time (in seconds)
estimate_backup_time() {
	# get last backup infofile
	local old_infofile=$destination/$last_clean_backup/backup.info

	# get section from path
	local infofile_section=$(find_infofile_section "$old_infofile" "$1")
	[ -z "$infofile_section" ] && return 1

	# get last backup duration
	local last_duration=$(lb_get_config -s $infofile_section "$old_infofile" duration)
	lb_is_integer $last_duration || return 1

	# if no size specified, use the last duration time
	if ! lb_is_integer $2 ; then
		echo $last_duration
		return 0
	fi

	# get last backup size
	local last_size=$(lb_get_config -s $infofile_section "$old_infofile" size)

	# if failed to get last size, use the last duration
	if ! lb_is_integer $last_size ; then
		echo $last_duration
		return 0
	fi

	echo $(($last_duration * $2 / $last_size))
}


# Run before backup
# Usage: run_before
# Dependencies: $disable_custom_commands, $exec_before, $exec_before_block
run_before() {

	# nothing to do: quit
	[ ${#exec_before[@]} == 0 ] && return 0

	lb_display --log "Running before command..."

	local result

	# if disabled, inform user and exit
	if lb_istrue $disable_custom_commands ; then
		lb_display_error "Custom commands are disabled."
		false # bad command to go into the if $? != 0
	else
		# run command/script
		debug "Run ${exec_before[*]}"

		"${exec_before[@]}"
	fi

	result=$?
	[ $result == 0 ] && return 0

	report_details+="
Before script failed (exit code: $result)
"
	lb_exitcode=5

	# option exit if error
	if lb_istrue $exec_before_block ; then
		debug "Before script exited with error."
		clean_exit
	fi
}


# Run after backup
# Usage: run_after
# Dependencies: $disable_custom_commands, $exec_after, $exec_after_block
run_after() {

	# nothing to do: quit
	[ ${#exec_after[@]} == 0 ] && return 0

	lb_display --log "Running after command..."

	local result

	# if disabled, inform user and exit
	if lb_istrue $disable_custom_commands ; then
		lb_display_error "Custom commands are disabled."
		false # bad command to go into the if $? != 0
	else
		# run command/script
		debug "Run ${exec_after[*]}"

		"${exec_after[@]}"
	fi

	result=$?
	[ $result == 0 ] && return 0

	report_details+="
After script failed (exit code: $result)
"
	# if error, do not overwrite rsync exit code
	[ $lb_exitcode == 0 ] && lb_exitcode=16

	# option exit if error
	if lb_istrue $exec_after_block ; then
		debug "After script exited with error."
		clean_exit
	fi
}


# Move a backup folder to
# Usage: move_backup DATE NEW_DATE PATH
# Dependencies: $destination
# Exit codes:
#   0: OK
#   1: failed
move_backup() {

	local old=$destination/$1/$3 new=$(dirname "$destination/$2/$3")

	# create parent directory and move it
	[ -e "$old" ] && mkdir -p "$new" && mv "$old" "$new"
	[ $? != 0 ] && return 1

	# clean old backup directory; don't care of errors
	clean_empty_backup $1 "$(dirname "$3" 2> /dev/null)"
	return 0
}


# Create latest link
# Usage: create_latest_link
# Dependencies: $destination, $backup_date
create_latest_link() {

	# remote destination: do nothing
	lb_istrue $remote_destination && return 0

	debug "Create latest link..."

	# create a new link
	# in a sub-context to avoid confusion and do not care of output
	if [ "$lb_current_os" == Windows ] ; then
		dummy=$(cd "$destination" 2> /dev/null && rm -f latest 2> /dev/null && cmd /c mklink /j latest $backup_date 2> /dev/null)
	else
		dummy=$(cd "$destination" 2> /dev/null && ln -snf $backup_date latest 2> /dev/null)
	fi

	return 0
}


# Display notification at the end of the backup
# Usage: notify_backup_end MESSAGE
notify_backup_end() {
	# notifications disabled: do nothing
	lb_istrue $notifications || return 0

	# Windows: display dialogs instead of notifications
	if [ "$lb_current_os" == Windows ] ; then
		# do not popup dialog that would prevent PC from shutdown
		lb_istrue $shutdown || windows_ending_popup=$*
	else
		notify "$*"
	fi
}


#
#  Exit functions
#

# trap kill signals
# Usage: catch_kills [COMMAND]
catch_kills() {
	# reset traps
	uncatch_kills

	local cmd=clean_exit
	[ -n "$1" ] && cmd=$1

	trap $cmd SIGHUP SIGINT SIGTERM
}


# Delete trap for kill signals
# Usage: uncatch_kills
uncatch_kills() {
	trap - 1 2 3 15
	trap
}


# Clean things before exit
# Usage: clean_exit [EXIT_CODE]
# Dependencies: $path_dest, $unmount, $keep_logs, $logfile, $shutdown, $tr_*
clean_exit() {

	# clear all traps to avoid infinite loop if following commands takes some time
	uncatch_kills

	# set exit code if specified
	[ -n "$1" ] && lb_exitcode=$1

	debug "Clean exit"

	clean_empty_backup -i $backup_date "$path_dest"

	# delete backup lock
	release_lock

	# unmount destination
	if ! unmount_destination ; then
		lb_display_critical --log "$tr_error_unmount"
		lbg_critical "$tr_error_unmount"

		[ $lb_exitcode == 0 ] && lb_exitcode=18
	fi

	send_email_report

	# delete log file
	local delete_logs=true

	case $keep_logs in
		always)
			delete_logs=false
			;;
		on_error)
			[ $lb_exitcode != 0 ] && delete_logs=false
			;;
	esac

	# delete log file
	$delete_logs && delete_logfile

	# if shutdown after backup, execute it
	lb_istrue $shutdown && haltpc

	# Windows end backup notification popup
	[ ${#windows_ending_popup} -gt 0 ] && lbg_info "$windows_ending_popup"

	debug "Exited with code: $lb_exitcode"

	lb_exit
}


# Exit when cancel signal is caught
# Usage: cancel_exit
# Dependencies: $command, $tr_*
cancel_exit() {

	echo
	lb_info --log "Cancelled. Exiting..."

	# display notification and exit
	case $command in
		backup)
			notify "$(printf "$tr_backup_cancelled_at" "$(date +%H:%M:%S)")\n$(report_duration)"
			clean_exit 17
			;;
		restore)
			notify "$tr_restore_cancelled"
			exit 11
			;;
		*)
			lb_exit
			;;
	esac
}


# Send email report
# Usage: send_email_report
# Dependencies: $email_report, $email_recipient, $email_sender, $email_subject_prefix, $current_date, $report_details, $tr_*
# Exit codes:
#   0: email sent, not enabled or no error
#   1: email recipient not set
send_email_report() {

	case $email_report in
		always)
			# continue
			;;
		on_error)
			# if there was no error, do not send email
			[ $lb_exitcode == 0 ] && return 0
			;;
		*)
			# email report not enabled
			return 0
			;;
	esac

	# if email recipient is not set
	if [ -z "$email_recipient" ] ; then
		lb_display_error --log "Email recipient not set, cannot send email report."
		return 1
	fi

	# email options
	local email_opts=()
	[ -n "$email_sender" ] && email_opts+=(--sender "$email_sender")

	# prepare email content
	local email_subject email_content="$tr_email_report_greetings

"
	# prepare email subject
	[ -n "$email_subject_prefix" ] && email_subject="$email_subject_prefix "

	email_subject+="$tr_email_report_subject "

	if [ $lb_exitcode == 0 ] ; then
		email_subject+=$(printf "$tr_email_report_subject_success" $lb_current_hostname)
		email_content+=$(printf "$tr_email_report_success" $lb_current_hostname)
	else
		email_subject+=$(printf "$tr_email_report_subject_failed" $lb_current_hostname)
		email_content+=$(printf "$tr_email_report_failed" $lb_current_hostname $lb_exitcode)
	fi

	email_content+="

$(printf "$tr_email_report_details" "$current_date")
$(report_duration)

"
	# error report
	[ $lb_exitcode != 0 ] && email_content+="$report_details
"
	email_content+="$tr_see_logfile_for_details

$tr_email_report_regards
time2backup"

	debug "Sending email report..."

	# send email without managing errors and without blocking script
	lb_email "${email_opts[@]}" --subject "$email_subject" "$email_recipient" "$email_content" &
}


# Halt PC in 10 seconds
# Usage: haltpc
# Dependencies: $shutdown_cmd
# Exit codes:
#   0: OK (halted)
#   1: shutdown command does not exists
#   2: error in shutdown command
haltpc() {

	# test shutdown command
	if ! lb_command_exists "${shutdown_cmd[0]}" ; then
		lb_display_error --log "No shutdown command found. PC will not halt."
		return 1
	fi

	# countdown before halt
	echo -e "\nYour computer will halt in 10 seconds. Press Ctrl-C to cancel."
	local i
	for ((i=10; i>=0; i--)) ; do
		echo -n "$i "
		sleep 1
	done
	echo

	# run shutdown command
	if ! "${shutdown_cmd[@]}" ; then
		lb_display_error --log "Error with shutdown command. PC is still up."
		return 2
	fi
}


#
#  Wizards
#

# Choose an operation to execute (time2backup commands)
# Usage: choose_operation
# Dependencies: $console_mode, $command, $tr_*
choose_operation() {

	# prepare options
	local choices=("$tr_backup_files" "$tr_restore_file" "$tr_configure_time2backup")
	local commands=("" backup restore config)

	# explore command: only in GUI mode
	if ! lb_istrue $console_mode ; then
		choices+=("$tr_explore_backups")
		commands+=(explore)
	fi

	commands+=(exit)

	# display choice
	lbg_choose_option -d 1 -l "$tr_choose_an_operation" "${choices[@]}" "$tr_quit" || return 1

	command=${commands[lbg_choose_option]}
}


# Configuration wizard
# Usage: config_wizard
# Dependencies: many, $tr_*
# Exit codes:
#   0: OK
#   1: no destination chosen
#   3: there are errors in configuration file
config_wizard() {

	local start_path recurrent_enabled=false

	# set default destination directory
	if [ -d "$destination" ] ; then
		# current config
		start_path=$destination
	else
		# not defined: current path
		start_path=$lb_current_path
	fi

	# choose destination directory
	if lbg_choose_directory -t "$tr_choose_backup_destination" "$start_path" ; then

		debug "Chosen destination: $lbg_choose_directory"

		# get the real path of the chosen directory
		local chosen_directory=$(lb_realpath "$lbg_choose_directory")

		# if destination changed (or first run)
		if [ "$chosen_directory" != "$destination" ] ; then

			# update destination config
			lb_set_config "$config_file" destination "$chosen_directory"
			if [ $? == 0 ] ; then
				# reset destination variable
				destination=$chosen_directory
			else
				lbg_error "$tr_error_set_destination\n$tr_edit_config_manually"
			fi

			# detect changed hostname
			if [ -d "$destination/backups" ] ; then
				existing_hostname=($(ls "$destination/backups"))
				if [ ${#existing_hostname[@]} == 1 ] && [ "${existing_hostname[0]}" != "$lb_current_hostname" ] ; then
					if lbg_yesno "$(printf "$tr_change_hostname\n$tr_change_hostname_no" ${existing_hostname[0]})" ; then
						mv "$destination/backups/${existing_hostname[0]}" "$destination/backups/$lb_current_hostname"
					fi
				fi
			fi
		fi

		# set mountpoint in config file
		local mountpoint=$(lb_df_mountpoint "$chosen_directory")
		if [ -n "$mountpoint" ] ; then
			debug "Mount point: $mountpoint"

			# update disk mountpoint config
			if [ "$chosen_directory" != "$backup_disk_mountpoint" ] ; then
				lb_set_config "$config_file" backup_disk_mountpoint "$mountpoint" || \
					lb_warning "Cannot set config: backup_disk_mountpoint"
			fi
		else
			debug "Could not find mount point of destination."
		fi

		# set mountpoint in config file
		local disk_uuid=$(lb_df_uuid "$chosen_directory")
		if [ -n "$disk_uuid" ] ; then
			debug "Disk UUID: $disk_uuid"

			# update disk UUID config
			if [ "$chosen_directory" != "$backup_disk_uuid" ] ; then
				lb_set_config "$config_file" backup_disk_uuid "$disk_uuid" || \
					lb_warning "Cannot set config: backup_disk_uuid"
			fi
		else
			debug "Could not find disk UUID of destination."
		fi

		# test if destination supports hard links
		if lb_istrue $hard_links && lb_istrue $force_hard_links && ! test_hardlinks "$destination" ; then

			# ask user to keep or not the force mode
			if ! lbg_yesno "$tr_force_hard_links_confirm\n$tr_not_sure_say_no" ; then

				# set config
				lb_set_config "$config_file" force_hard_links false || \
					lb_warning "Cannot set config: force_hard_links"
			fi
		fi
	else
		debug "Error or cancel when choosing destination directory (result code: $?)."

		# if no destination set, return error
		if [ -z "$destination" ] ; then
			return 1
		else
			return 0
		fi
	fi

	# edit sources to backup
	if lbg_yesno "$tr_ask_edit_sources\n$tr_default_source" ; then

		local advanced_mode=false
		lb_istrue $console_mode && advanced_mode=true

		# check defined sources
		local sources=()
		lb_read_config "$config_sources" && sources=("${lb_read_config[@]}")
		[ ${#sources[@]} -gt 1 ] && advanced_mode=true

		# choose with folder selector
		if ! $advanced_mode && lbg_choose_directory -t "$tr_choose_backup_source" "$(lb_homepath)" ; then

			debug "Chosen source: $lbg_choose_directory"

			# get the real path of the chosen directory
			local chosen_directory=$(lb_realpath "$lbg_choose_directory")

			if [ -n "$chosen_directory" ] ; then
				# edit source file
				if [ ${#sources[@]} == 0 ] ; then
					echo "$chosen_directory" >> $config_sources
				else
					lb_edit "s|^${sources[0]}[[:space:]]*$|$chosen_directory|" "$config_sources"
				fi
				[ $? != 0 ] && advanced_mode=true
			else
				advanced_mode=true
			fi
		fi

		# edit config file
		if $advanced_mode ; then
			if open_config "$config_sources" ; then
				if [ "$lb_current_os" != Windows ] ; then
					# display window to wait until user has finished
					lb_istrue $console_mode || lbg_info "$tr_finished_edit"
				fi
			else
				lb_warning "Failed to edit sources config file"
			fi
		fi
	fi

	# activate recurrent backups
	if lb_istrue $enable_recurrent ; then
		if lbg_yesno "$tr_ask_activate_recurrent" ; then

			# default custom frequency
			case $frequency in
				hourly|1h|60m)
					default_frequency=1
					;;
				""|daily|1d|24h)
					default_frequency=2
					;;
				weekly|7d)
					default_frequency=3
					;;
				monthly|30d)
					default_frequency=4
					;;
				*)
					default_frequency=5
					;;
			esac

			# choose frequency
			if lbg_choose_option -l "$tr_choose_backup_frequency" -d $default_frequency "$tr_frequency_hourly" "$tr_frequency_daily" "$tr_frequency_weekly" "$tr_frequency_monthly" "$tr_frequency_custom"; then

				recurrent_enabled=true

				# set recurrence frequency
				case $lbg_choose_option in
					1)
						lb_set_config "$config_file" frequency hourly
						;;
					2)
						lb_set_config "$config_file" frequency daily
						;;
					3)
						lb_set_config "$config_file" frequency weekly
						;;
					4)
						lb_set_config "$config_file" frequency monthly
						;;
					5)
						# default custom frequency
						case $frequency in
							hourly)
								frequency=1h
								;;
							weekly)
								frequency=7d
								;;
							monthly)
								frequency=31d
								;;
							'')
								# default is 24h
								frequency=24h
								;;
						esac

						# display dialog to enter custom frequency
						if lbg_input_text -d "$frequency" "$tr_enter_frequency $tr_frequency_examples" ; then
							if test_period $lbg_input_text ; then
								lb_set_config "$config_file" frequency $lbg_input_text
							else
								lbg_error "$tr_frequency_syntax_error\n$tr_please_retry"
							fi
						fi
						;;
				esac

				[ $? != 0 ] && lb_warning "Cannot set config: frequency"
			fi
		fi
	fi

	# ask to edit config
	if lbg_yesno "$tr_ask_edit_config" ; then

		open_config "$config_file"
		if [ $? == 0 ] && [ "$lb_current_os" != Windows ] ; then
			# display window to wait until user has finished
			lb_istrue $console_mode || lbg_info "$tr_finished_edit"
		fi
	fi

	# enable/disable recurrence in config
	lb_set_config "$config_file" recurrent $recurrent_enabled || \
		lb_warning "Cannot set config: recurrent"

	# reload config
	if ! load_config ; then
		lbg_error "$tr_errors_in_config"
		return 3
	fi

	# apply configuration
	apply_config || lbg_warning "$tr_cannot_install_cronjobs"

	# ask for the first backup
	lbg_yesno -y "$tr_ask_backup_now" || return 0

	# run the first backup
	t2b_backup
}
