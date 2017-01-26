#!/bin/bash

########################################################
#                                                      #
#  time2backup                                         #
#                                                      #
#  It's time to backup your files!                     #
#                                                      #
#  Author: Jean Prunneaux (http://jean.prunneaux.com)  #
#                                                      #
########################################################

################################
#                              #
#  Version 1.0.0 (2017-01-25)  #
#                              #
################################


###########################
#  VARIABLES DECLARATION  #
###########################

version="1.0.0-beta.3"

user=""
sources=()
backup_destination=""
success=()
warnings=()
errors=()
report_details=""
default_verbose_level="INFO"
default_log_level="INFO"
backup_lock=""
current_timestamp=$(date +%s)
current_date=$(date '+%Y-%m-%d at %H:%M:%S')


############################
#  DEFAULT CONFIG OPTIONS  #
############################

consolemode=false
debugmode=false

mount=false
backup_disk_uuid=""

network_compression=false

recurrent=false
frequency="daily"

keep_limit=-1
clean_old_backups=true
clean_keep=0

logs_save=false
keep_logs_if_error=true
log_level="$default_log_level"

notifications=true
email_report=false
email_report_if_error=false

exec_before_block=false
exec_after_block=false

# shutdown after backup
shutdown=false
shutdown_cmd=(shutdown -h now)

# advanced options
hard_links=true
mirror_mode=false
rsync_options=()
cmd_alias="/usr/bin/time2backup"
verbose_level="$default_verbose_level"


####################
#  INITIALIZATION  #
####################

# get real path of the script
if [ "$(uname)" == "Darwin" ] ; then
	# macOS which does not support readlink -f option
	current_script="$(perl -e 'use Cwd "abs_path";print abs_path(shift)' "$0")"
else
	current_script="$(readlink -f "$0")"
fi

# get directory of the current script
script_directory="$(dirname "$current_script")"

# load libbash
source "$script_directory/libbash/libbash.sh"
if [ $? != 0 ] ; then
	echo >&2 "Error: cannot load libbash. Please add it to the '$script_directory/libbash' directory."
	exit 1
fi

# load libbash GUI
source "$script_directory/libbash/libbash_gui.sh"
if [ $? != 0 ] ; then
	echo >&2 "Error: cannot load libbash GUI. Please add it to the '$script_directory/libbash' directory."
	exit 1
fi

# change current script name
lb_current_script_name="time2backup"


###############
#  FUNCTIONS  #
###############

# Print help for users in console
# Usage: print_help [COMMAND] (if empty, print global help)
print_help() {
	lb_print "\nUsage: $lb_current_script_name [GLOBAL_OPTIONS] COMMAND [OPTIONS] [ARG...]"
	lb_print "\nGlobal options:"
	lb_print "  -C, --console              execute time2backup in console mode (no dialog windows)"
	lb_print "  -l, --log-level LEVEL      set a verbose and log level (ERROR|WARNING|INFO|DEBUG)"
	lb_print "  -v, --verbose-level LEVEL  set a verbose and log level (ERROR|WARNING|INFO|DEBUG)"
	lb_print "  -c, --config CONFIG_FILE   overwrite configuration with specific file"
	lb_print "  -D, --debug                run in debug mode (all messages printed and logged)"
	lb_print "  -V, --version              print version and quit"
	lb_print "  -h, --help                 print help \n"

	case $1 in
		backup)
			lb_print "Command usage: $1 [OPTIONS]"
			lb_print "\nPerform backup"
			lb_print "\nOptions:"
			lb_print "  -p, --planned  perform a planned backup (used in cron jobs)"
			lb_print "  -h, --help     print help"
			;;
		history)
			lb_print "Command usage: $1 [OPTIONS] PATH"
			lb_print "\nGet backup history of a file or directory"
			lb_print "Warning: This feature does not detect old renamed/moved files yet."
			lb_print "\nOptions:"
			lb_print "  -a, --all    print all versions, including duplicates"
			lb_print "  -q, --quiet  quiet mode; print only backup dates"
			lb_print "  -h, --help   print help"
			;;
		restore)
			lb_print "Command usage: $1 [OPTIONS] [PATH]"
			lb_print "\nRestore a file or directory"
			lb_print "Warning: This feature does not auto-detect renamed or moved files."
			lb_print "         To restore a moved/deleted file, ."
			lb_print "\nOptions:"
			lb_print "  -d, --date DATE  restore file at backup DATE (use format YYYY-MM-DD-HHMMSS)"
			lb_print "                   by default it restores the last available backup"
			lb_print "  --directory      path to restore is a directory (not necessary if path exists)"
			lb_print "                   If deleted or moved, indicate that the chosen path is a directory."
			lb_print "  --delete-new     delete newer files if exists for directories (restore exactly the same version)"
			lb_print "  -f, --force      force restore; do not display confirmation"
			lb_print "  -h, --help       print help"
			;;
		config)
			lb_print "Command usage: $1 [OPTIONS]"
			lb_print "\nEdit configuration"
			lb_print "\nOptions:"
			lb_print "  -s, --sources     edit sources file (sources to backup)"
			lb_print "  -x, --excludes    edit excludes file (patterns to ignore)"
			lb_print "  -l, --show        show configuration; do not edit"
			lb_print "                    display configuration without comments"
			lb_print "  -t, --test        test configuration; do not edit"
			lb_print "  -a, --apply       apply configuration; do not edit"
			lb_print "  -w, --wizard      display configuration wizard instead of edit"
			lb_print "  -e, --editor BIN  use specified editor (e.g. vim, nano, ...)"
			lb_print "  -h, --help        print help"
			;;
		install)
			lb_print "Command usage: $1 [OPTIONS]"
			lb_print "\nInstall time2backup"
			lb_print "\nOptions:"
			lb_print "  -r, --reset-config  reset configuration files to default"
			lb_print "  -h, --help          print help"
			;;
		*)
			lb_print "Commands:"
			lb_print "    backup     perform a backup (default)"
			lb_print "    restore    restore a backup of a file or directory"
			lb_print "    history    displays backup history of a file or directory"
			lb_print "    config     edit configuration"
			lb_print "    install    install time2backup"
			lb_print "\nRun '$lb_current_script_name COMMAND --help' for more information on a command."
			;;
	esac
}


# Get absolute path of a file/directory
# Usage: get_absolute_path PATH
get_absolute_path() {
	echo $(cd "$(dirname "$1")" && pwd)/"$(basename "$1")"
}


# Get relative path to reach second path from a first one
# e.g. get_relative_path /home/user/my/first/path /home/user/my/second/path
# will return ../../second/path
# Usage: get_relative_path SOURCE_PATH DESTINATION_PATH
get_relative_path() {

	local dir_src="$1"
	local dir_dest="$2"
	local abs_dir_src="$(get_absolute_path "$dir_src")"
	local abs_dir_dest="$(get_absolute_path "$dir_dest")"
	local abs_test_dir=""
	local abs_common_path=""
	local newpath="./"

	# particular case of 2 identical folders
	if [ "$abs_dir_src" == "$abs_dir_dest" ] ; then
		echo "./"

		# return to current directory and quit
		cd "$lb_current_path"
		return
	fi

	declare -i i=0
	while true ; do
		if [ "${abs_dir_src:0:$i}" != "${abs_dir_dest:0:$i}" ] ; then
			abs_common_path=$(dirname "${abs_dir_src:0:$i}")
			break
		fi
		i+=1
	done

	cd "$abs_dir_src/.."
	if [ $? != 0 ] ; then
		return 1
	fi

	while true ; do
		if [ "$(pwd)" == "$abs_common_path" ] ; then
			break
		fi

		cd ..
		if [ $? != 0 ] ; then
			return 1
		fi

		newpath+="../"
	done

	#echo "$newpath/${dir_dest:${#abs_common_path}}"
	echo "$newpath/"

	# return to current directory
	cd "$lb_current_path"
}


# Get backup type to check if a backup source is a file or a protocol like ssh, smb, ...
# Usage: get_backup_type SOURCE_URL
# Return: type of source (files/ssh)
get_backup_type() {

	url="$*"
	protocol=$(echo "$url" | cut -d: -f1)

	# get protocol
	case "$protocol" in
		ssh|fish)
			# double check protocol
			echo "$url" | grep -E "^$protocol://" &> /dev/null
			if [ $? == 0 ] ; then
				# special case of fish = ssh
				if [ "$protocol" == "fish" ] ; then
					echo "ssh"
				else
					echo "$protocol"
				fi
				return
			fi
			;;
	esac

	# if not found, it is regular file
	echo "files"
}


# Get readable backup date
# e.g. 2017-01-01-093000 -> 2017-01-01 09:30:00
# Usage: get_backup_fulldate YYYY-MM-DD-HHMMSS
get_backup_fulldate() {

	# test backup format (YYYY-MM-DD-HHMMSS)
	echo "$1" | grep -E "^[1-9][0-9]{3}-[0-1][0-9]-[0-3][0-9]-[0-2][0-9][0-5][0-9][0-5][0-9]$" &> /dev/null

	# if not good format, return error
	if [ $? != 0 ] ; then
		return 1
	fi

	# return date at format YYYY-MM-DD HH:MM:SS
	echo ${1:0:10} ${1:11:2}:${1:13:2}:${1:15:2}
}


# Get backup history of a file
# Usage: get_backup_history [OPTIONS] PATH
# Options:
#   -a, --all  return all versions (including same)
# Exit codes:
#   0: OK
#   1: usage error
#   2: no backups found
#   3: cannot found backups (no absolute path, deleted parent directory)
get_backup_history() {

	file_history=()
	allversions=false

	# get options
	while true ; do
		case $1 in
			-a|--all)
				allversions=true
				shift
				;;
			*)
				break
				;;
		esac
	done

	# usage error
	if [ $# == 0 ] ; then
		return 1
	fi

	# get all backups
	backups=($(get_backups))
	if [ ${#backups[@]} == 0 ] ; then
		return 2
	fi

	# get path
	file="$*"
	abs_file="$(get_backup_path "$file")"
	if [ -z "$abs_file" ] ; then
		return 3
	fi

	# try to find backup
	last_inode=""
	for ((h=${#backups[@]}-1; h>=0; h--)) ; do
		backup_file="$backup_destination/${backups[$h]}/$abs_file"
		if [ -e "$backup_file" ] ; then
			if $allversions ; then
				file_history+=("${backups[$h]}")
				continue
			fi

			# if no hardlinks, do not test inodes
			if ! test_hardlinks ; then
				file_history+=("${backups[$h]}")
				continue
			fi

			# check inodes for version detection
			if [ "$(lb_detect_os)" == "macOS" ] ; then
				inode=$(stat -f %i "$backup_file")
			else
				inode=$(stat --format %i "$backup_file")
			fi
			if [ "$inode" != "$last_inode" ] ; then
				file_history+=("${backups[$h]}")
				last_inode=$inode
			fi
		fi
	done

	# return file versions
	if [ ${#file_history[@]} -gt 0 ] ; then
		for b in ${file_history[@]} ; do
			echo $b
		done
	else
		return 2
	fi
}


# Create configuration files in user config
# Usage: create_config
# Exit codes: 0 if OK, 1 if cannot create config directory
create_config() {

	# create config directory
	# default: ~/.config/time2backup
	mkdir -p "$config_directory" &> /dev/null
	if [ $? != 0 ] ; then
		lb_error "Cannot create config directory. Please verify your access rights or home path."
		return 1
	fi

	# copy config samples from current directory
	cp -f "./config/excludes.example.conf" "$config_directory/excludes.conf"
	cp -f "./config/sources.example.conf" "$config_directory/sources.conf"
	cp -f "./config/time2backup.example.conf" "$config_directory/time2backup.conf"
}


# Load configuration file
# Usage: load_config
# Exit codes:
#   0: OK
#   1: cannot open config
#   2: there are errors in config
load_config() {

	configok=true

	# load global config
	source "$config_file" > /dev/null
	if [ $? != 0 ] ; then
		return 1
	fi

	# test if destination is defined
	if [ -z "$destination" ] ; then
		lb_error "Destination is not set!"
		configok=false
	fi

	# test if sources file exists
	if ! [ -f "$config_sources" ] ; then
		lb_error "No sources file found!"
		configok=false
	fi

	# test integer values
	if ! lb_is_integer $keep_limit ; then
		lb_error "keep_limit must be an integer!"
		configok=false
	fi
	if ! lb_is_integer $clean_keep ; then
		lb_error "clean_keep must be an integer!"
		configok=false
	fi

	# correct bad values
	if [ $clean_keep -lt 0 ] ; then
		clean_keep=0
	fi

	if ! $configok ; then
		lb_error "\nThere are errors in your configuration."
		lb_error "Please edit your configuration with 'config' command or manually."
		return 2
	fi

	# set backup destination
	backup_destination="$destination/backups/$(hostname)/"
}


# Mount destination
# Usage: mount_destination
# Exit codes:
#   0: mount OK
#   1: mount error
#   2: disk not available
#   3: cannot create mount point
#   4: command not supported
#   5: no disk UUID set in config
mount_destination() {

	# if UUID not set, return error
	if [ -z "$backup_disk_uuid" ] ; then
		return 5
	fi

	lb_display --log "Mount disk..."

	# macOS is not supported
	# this is not supposed to happen because macOS always mount disks
	if [ "$(lb_detect_os)" == "macOS" ] ; then
		lb_display_error --log "macOS not supported yet"
		return 4
	fi

	# test if UUID exists (disk plugged)
	ls /dev/disk/by-uuid/ | grep "$backup_disk_uuid" &> /dev/null
	if [ $? != 0 ] ; then
		lb_display_error --log "Disk not available."
		return 2
	fi

	# create mountpoint
	if ! [ -d "$destination" ] ; then

		mkdir "$destination" 2>> "$logfile"

		# if failed, try in sudo mode
		if [ $? != 0 ] ; then
			lb_display_debug --log "...Failed! Try with sudo..."
			sudo mkdir "$destination" 2>> "$logfile"

			if [ $? != 0 ] ; then
				lb_display --log "...Failed!"
				return 3
			fi
		fi
	fi

	# mount disk
	mount "/dev/disk/by-uuid/$backup_disk_uuid" "$destination" 2>> "$logfile"

	# if failed, try in sudo mode
	if [ $? != 0 ] ; then
		lb_display_debug --log "...Failed! Try with sudo..."
		sudo mount "/dev/disk/by-uuid/$backup_disk_uuid" "$destination" 2>> "$logfile"

		if [ $? != 0 ] ; then
			lb_display --log "...Failed!"
			return 1
		fi
	fi
}


# Unmount destination
# Usage: unmount_destination
# Exit codes:
#   0: OK
#   1: umount error
#   2: cannot delete mountpoint
unmount_destination() {

	lb_display --log "Unmount destination..."
	umount "$destination" &> /dev/null

	# if failed, try in sudo mode
	if [ $? != 0 ] ; then
		lb_display_debug --log "...Failed! Try with sudo..."
		sudo umount "$destination" &> /dev/null

		if [ $? != 0 ] ; then
			lb_display --log "...Failed!"
			return 1
		fi
	fi

	lb_display_debug --log "Delete mount point..."
	rmdir "$destination" &> /dev/null

	# if failed, try in sudo mode
	if [ $? != 0 ] ; then
		lb_display_debug --log "...Failed! Try with sudo..."
		sudo rmdir "$destination" &> /dev/null

		if [ $? != 0 ] ; then
			lb_display --log "...Failed!"
			return 2
		fi
	fi
}


# Get path of a file backup
# Usage: get_backup_path PATH
# Return: backup path
get_backup_path() {

	# get file
	f="$*"

	# if absolute path (first character is a /)
	if [ "${f:0:1}" == "/" ] ; then
		# return file path
		echo "/files$f"
		return
	fi

	# if not absolute path, check protocols
	case $(get_backup_type "$f") in
		ssh)
			# transform ssh://user@hostname:/path/to/file -> /ssh/user@hostname/path/to/file
			# command: split by colon to ssh/user@hostname/,
			# then print path with no loose of colons and delete the last colon
			echo "$f" | awk -F ':' '{printf $1 "/" $2 "/"; for(i=3;i<=NF;++i) printf $i ":"}' | sed 's/:$//'
			return
			;;
	esac

	# if file or directory

	# if not exists (file moved or deleted), try to get parent directory path
	if [ -e "$f" ] ; then
		echo "/files/$(get_absolute_path "$f")"
	else
		parent_dir="$(dirname "$f")"
		if [ -d "$parent_dir" ] ; then
			echo "/files/$(get_absolute_path "$parent_dir")/$(basename "$f")"
		else
			# if not exists, I cannot guess original path
			lb_error "File does not exist."
			lb_error "If you want to restore a deleted file, please specify an absolute path."
			return 1
		fi
	fi
}


# Test if backup destination support hard links
# Usage: test_hardlinks
# Exit codes:
#   0: destination supports hard links
#   1: cannot get filesystem type
#   2: destination does not support hard links
test_hardlinks() {

	# filesystems that does not support hard links
	filesystems=(vfat vboxsf)

	# get destination filesystem
	dest_fstype="$(lb_df_fstype "$destination")"
	if [ -z "$dest_fstype" ] ; then
		return 1
	fi

	# if destination filesystem does not support hard links, return error
	if lb_array_contains "$dest_fstype" "${filesystems[@]}" ; then
		return 2
	fi
}


# test if a line is a comment
is_comment() {
	# default character for comments
	char_comment="#"
	empty_lines_are_comments=false

	# get options
	while true ; do
		case $1 in
			-c)
				char_comment=("$2")
				custom_editor=true
				shift 2
				;;
			-n)
				empty_lines_are_comments=true
				shift
				;;
			*)
				break
				;;
		esac
	done

	# test if current line is not a comment
	# delete spaces and test first character
	trimtest=$(echo $* | tr -d '[:space:]')
	if [ -z "$trimtest" ] ; then
		if ! $empty_lines_are_comments ; then
			return 2
		fi
	else
		if [[ "$trimtest" != "$char_comment"* ]] ; then
			return 1
		fi
	fi
}


# Get list of sources to backup
get_sources() {
	# reset variable
	sources=()

	# read sources.conf file line by line
	while read line ; do
		if ! is_comment -n $line ; then
			sources+=("$line")
		fi
	done < "$config_sources"
}


# Get all backup dates list
get_backups() {
	echo $(ls "$backup_destination" | grep -E "^[1-9][0-9]{3}-[0-1][0-9]-[0-3][0-9]-[0-2][0-9][0-5][0-9][0-5][0-9]$" 2> /dev/null)
}


# Clean old backups if limit is reached or if space is not available
rotate_backups() {

	# get backups
	old_backups=($(get_backups))
	nbold=${#old_backups[@]}

	# avoid to delete current backup
	if [ $nbold -le 1 ] ; then
		lb_display_debug --log "Rotate backups: There is only one backup."
		return 0
	fi

	# if limit reached
	if [ $nbold -gt $keep_limit ] ; then
		lb_display --log "Cleaning old backups..."
		lb_display_debug "Clean to keep $keep_limit/$nbold"

		old_backups=(${old_backups[@]:0:$(($nbold - $keep_limit))})

		# remove backups from older to newer
		for ((r=0; r<${#old_backups[@]}; r++)) ; do
			lb_display_debug --log "Removing $backup_destination/${old_backups[$r]}..."

			rm -rf "$backup_destination/${old_backups[$r]}"
			lb_result -l DEBUG
		done
	fi
}


report_duration() {
	# calculate
	duration=$(($(date +%s) - $current_timestamp))

	echo "Elapsed time: $(($duration/3600)):$(printf "%02d" $(($duration/60%60))):$(printf "%02d" $(($duration%60)))"
}


install_config() {

	lb_print "Testing configuration..."

	# if config not ok, error
	if ! load_config ; then
		return 3
	fi

	# install cronjob
	if $recurrent ; then
		tmpcrontab="$config_directory/crontmp"
		crontask="* * * * *	\"$current_script\" backup --planned"

		lb_print "Install recurrent backup..."

		cmd_opt=""
		if [ -n "$user" ] ; then
			cmd_opt="-u $user"
		fi

		crontab -l $cmd_opt > "$tmpcrontab" 2>&1
		if [ $? != 0 ] ; then
			# special case for error when no crontab
			cat "$tmpcrontab" | grep "no crontab for " > /dev/null
			if [ $? == 0 ] ; then
				# reset crontab
				echo > "$tmpcrontab"
			else
				lb_display --log "Failed! \nPlease edit crontab manually and add the following line:"
				lb_display --log "$crontask"
				return 3
			fi
		fi

		cat "$tmpcrontab" | grep "$crontask" > /dev/null
		if [ $? != 0 ] ; then
			# append command to crontab
			echo -e "\n$crontask" >> "$tmpcrontab"

			cmd_opt=""
			if [ -n "$user" ] ; then
				cmd_opt="-u $user"
			fi

			crontab $cmd_opt "$tmpcrontab"
			res=$?
		fi

		rm -f "$tmpcrontab" &> /dev/null

		return $res
	fi
}


# Test if destination is reachable
test_destination() {

	destok=false

	# test backup destination directory
	if [ -d "$destination" ] ; then
		destok=true
	else
		# if automount
		if $mount ; then
			# mount disk
			if mount_destination ; then
				destok=true
				# if unmount not set, default behaviour
				if [ -z "$unmount" ] ; then
					unmount=true
				fi
			fi
		fi
	fi

	# error message if destination not ready
	if ! $destok ; then
		lb_display --log "Backup destination is not reachable."
		lb_display --log "Verify if your media is plugged in and try again."
		return 1
	fi
}


# Test backup command
# rsync simulation and get total size of the files to transfer
test_backup() {

	# prepare rsync in test mode
	test_cmd=(rsync --dry-run --no-human-readable --stats)

	# append rsync options without the first argument (=rsync)
	test_cmd+=("${cmd[@]:1}")

	# rsync test
	# option dry-run makes a simulation for rsync
	# then we get the last line with the total amount of bytes to be copied
	# which is in format 999,999,999 so then we delete the commas
	lb_display_debug --log "Testing rsync in dry-run mode: ${test_cmd[@]}..."

	total_size=$("${test_cmd[@]}" 2>> "$logfile" | grep "Total transferred file size" | awk '{ print $5 }' | sed 's/,//g')

	# if rsync command not ok, error
	if ! lb_is_integer $total_size ; then
		lb_display_debug --log "rsync test failed."
		return 1
	fi

	lb_display_debug --log "Backup total size (in bytes): $total_size"

	# if there was an unknown error, continue
	if ! lb_is_integer $total_size ; then
		lb_display_debug --log "Error: '$total_size' is not a valid size in bytes. Continue..."
		return 1
	fi
}


# Test space available on destination disk
test_space() {
	# get space available
	space_available=$(lb_df_space_left "$destination")

	lb_display_debug --log "Space available on disk (in bytes): $space_available"

	# if there was an unknown error, continue
	if ! lb_is_integer $space_available ; then
		lb_display --log "Cannot get available space. Trying to backup although."
		return
	fi

	# if space is not enough, error
	if [ $space_available -lt $total_size ] ; then
		lb_display --log "Not enough space on device!"
		lb_display_debug --log "Needed (in bytes): $total_size/$space_available"
		return 1
	fi
}


# Delete empty directories recursively
# Usage: clean_empty_directories PATH
clean_empty_directories() {

	# usage error
	if [ $# == 0 ] ; then
		return 1
	fi

	# get directory path
	d="$*"

	# delete empty directories recursively
	while true ; do
		# if is not a directory, error
		if ! [ -d "$d" ] ; then
			return 1
		fi

		# security check
		if [ "$d" == "/" ] ; then
			return 2
		fi

		# security check: do not delete destination path
		if [ "$(dirname "$d")" == "$(dirname "$destination")" ] ; then
			return
		fi

		# if directory is empty,
		if lb_dir_is_empty "$d" ; then

			lb_display_debug "Deleting empty backup: $d"

			# delete directory
			rmdir "$d" &> /dev/null
			if [ $? == 0 ] ; then
				# go to parent directory and continue loop
				d="$(dirname "$d")"
				continue
			fi
		fi

		# if not empty, quit loop
		return
	done
}


# config wizard
config_wizard() {

	# set default destination directory
	if [ -d "$destination" ] ; then
		start_path="$destination"
	else
		start_path="$lb_current_path"
	fi

	# get external disk
	if lbg_choose_directory -t "Choose a destination for backups" "$start_path" ; then

		lb_display_debug "Choosed directory: $lbg_choose_directory"

		# set destination in config file
		edit_config --set "destination=\"$lbg_choose_directory\"" "$config_file"

		# set mountpoint in config file
		mountpoint="$(lb_df_mountpoint "$lbg_choose_directory")"
		if [ $? == 0 ] ; then
			lb_display_debug "Mount point: $mountpoint"

			edit_config --set "backup_disk_mountpoint=\"$mountpoint\"" "$config_file"
		else
			lb_error "Could not find mount point of destination."
		fi

		# set mountpoint in config file
		disk_uuid="$(lb_df_uuid "$lbg_choose_directory")"
		if [ $? == 0 ] ; then
			lb_display_debug "Disk UUID: $disk_uuid"

			edit_config --set "backup_disk_uuid=\"$disk_uuid\"" "$config_file"
		else
			lb_error "Could not find disk UUID of destination."
		fi
	else
		lb_display_debug "Error or cancel in choose directory (exit code: $?)."
	fi

	# activate recurrent backups
	if lbg_yesno "Do you want to activate recurrent backups?" ; then

		# choose frequency
		if lbg_choose_option -l "Choose backup frequency:" -d 1 "daily" "weekly" "monthly" "hourly (use with care)" ; then
			case "$lbg_choose_option" in
				1)
					edit_config --set "recurrent=true" "$config_file"
					edit_config --set "frequency=\"daily\"" "$config_file"
					;;
				2)
					edit_config --set "recurrent=true" "$config_file"
					edit_config --set "frequency=\"weekly\"" "$config_file"
					;;
				3)
					edit_config --set "recurrent=true" "$config_file"
					edit_config --set "frequency=\"monthly\"" "$config_file"
					;;
				4)
					edit_config --set "recurrent=true" "$config_file"
					edit_config --set "frequency=\"hourly\"" "$config_file"
					;;
			esac
		fi
	fi

	firstconfig_ok=true

	# install configuration
	if ! install_config ; then
		firstconfig_ok=false
		lbg_display_error "There are errors in your configuration. Please correct it in configuration files."
	fi
}


# First run wizard
first_run() {
	# confirm install
	if ! lbg_yesno -y "Do you want to install time2backup?\nChoose no if you want to install manually." ; then
		return
	fi

	# create configuration
	if ! create_config ; then
		return 3
	fi

	# load configuration; don't care of errors
	load_config &> /dev/null

	# install time2backup (create links)
	t2b_install

	# config wizard
	config_wizard

	# edit config
	if lbg_yesno "Do you want to edit the configuration files?" ; then
		t2b_config
		t2b_config -s
	else
		if ! $firstconfig_ok ; then
			return 2
		fi
	fi

	# recheck config
	if ! install_config ; then
		lbg_display_error "There are errors in your configuration. Please check it and retry later."
		return 2
	fi

	if lbg_yesno -y "Do you want to perform your first backup now?" ; then
		t2b_backup
	else
		lbg_display_info "time2backup is ready!"
	fi
}


# Edit configuration
# Usage: edit_config [OPTIONS] CONFIG_FILE
# Options:
#   -e, --editor COMMAND  set editor
#   --set "param=value"   set a config parameter in headless mode (no editor)
# Exit codes:
#   0: OK
#   1: usage error
#   2: failed to open/save configuration
#   3: no editor found to open configuration file
edit_config() {

	# default values
	editors=(nano vim vi)
	custom_editor=false
	set_config=""

	# get options
	while true ; do
		case "$1" in
			-e|--editor)
				if lb_test_arguments -eq 0 $2 ; then
					return 1
				fi
				editors=("$2")
				custom_editor=true
				shift 2
				;;
			--set)
				if lb_test_arguments -eq 0 $2 ; then
					return 1
				fi
				set_config="$2"
				shift 2
				;;
			*)
				break
				;;
		esac
	done

	# test config file
	if lb_test_arguments -eq 0 $* ; then
		return 1
	fi

	edit_file="$*"

	# headless mode
	if [ -n "$set_config" ] ; then

		# get parameter + value
		conf_param="$(echo "$set_config" | cut -d= -f1)"
		conf_value="$(echo "$set_config" | sed 's/\//\\\//g')"

		# get config line
		config_line=$(cat "$edit_file" | grep -n "^[# ]*$conf_param=" | cut -d: -f1)

		# if found, change line
		if [ -n "$config_line" ] ; then
			sed -i'~' "${config_line}s/.*/$conf_value/" "$edit_file"
		else
			# if not found, append to file
			echo "$conf_value" >> "$edit_file"
		fi
	else
		# config editor mode
		all_editors=()

		# if no custom editor,
		if ! $custom_editor ; then

			# open file with graphical editor
			if ! $consolemode ; then
				if [ "$(lbg_get_gui)" != "console" ] ; then
					if [ "$(lb_detect_os)" == "macOS" ] ; then
						all_editors+=(open)
					else
						all_editors+=(xdg-open)
					fi
				fi
			fi

			# add console editors
			all_editors+=("${editors[@]}")
		fi

		# select a console editor
		for e in ${all_editors[@]} ; do
			if [ -n "$editor" ] ; then
				break
			fi
			# test if editor exists
			if lb_command_exists "$e" ; then
				editor="$e"
				break
			fi
		done

		if [ -n "$editor" ] ; then
			"$editor" "$edit_file" 2> /dev/null
			wait $!
		else
			if $custom_editor ; then
				lb_print "Editor '$editors' was not found on this system."
			else
				lb_print "No editor was found on this system."
				lb_print "Please edit $edit_file manually."
			fi

			return 3
		fi
	fi

	if [ $? != 0 ] ; then
		lb_error "Failed to open/save configuration."
		lb_error "Please edit $edit_file manually."
		return 2
	fi
}


# Exit on cancel
cancel_exit() {

	lb_display --log
	lb_display_info --log "Cancelled. Exiting..."

	# display notification
	if $notifications ; then
		lbg_notify "Backup cancelled at $(date +%H:%M:%S)\n$(report_duration)"
	fi

	# exit with cancel code
	clean_exit 11
}


# Delete backup lock
# Usage: remove_lock
release_lock() {

	lb_display_debug "Deleting lock..."

	rm -f "$backup_lock" &> /dev/null
	if [ $? != 0 ] ; then
		lbg_display_critical --log "Could not remove lock. Please delete it manually or further backups will fail!"
		return 1
	fi
}


# Clean things before exit
# Usage: clean_exit [EXIT_CODE]
clean_exit() {

	# set exit code if specified
	if [ -n "$1" ] ; then
		lb_exitcode=$1
	fi

	lb_display_debug --log "Clean exit."

	# delete backup lock
	release_lock

	# unmount destination
	if [ -n "$unmount" ] ; then
		if $unmount ; then
			if ! unmount_destination ; then
				lbg_display_error --log "Can not unmount destination!"
			fi
		fi
	fi

	if $email_report ; then
		email_report_if_error=true
	fi

	# send email report
	if $email_report_if_error ; then

		# if email recipient is set
		if [ -n "$email_recipient" ] ; then

			# if report or error, send email
			if $email_report || [ $lb_exitcode != 0 ] ; then

				# email options
				email_opts=()
				if [ -n "$email_sender" ] ; then
					email_opts+=(--sender "$email_sender")
				fi

				# prepare email content
				email_subject="time2backup - "
				email_content="Dear user,\n\n"

				if [ $lb_exitcode == 0 ] ; then
					email_subject+="Backup succeeded on $(hostname)"
					email_content+="A backup succeeded on $(hostname)."
				else
					email_subject+="Backup failed on $(hostname)"
					email_content+="A backup failed on $(hostname) (exit code: $lb_exitcode)"
				fi

				email_content+="\n\nBackup started on $current_date\n$(report_duration)\n\n"

				# error report
				if [ $lb_exitcode != 0 ] ; then
					report_user="$user"
					if [ -z "$report_user"] ; then
						report_user="$(whoami)"
					fi

					email_content+="User: $report_user\n$report_details\n\n"
				fi

				# if logs are kept,
				email_logs=false
				if $logs_save ; then
					email_logs=true
				else
					if $keep_logs_if_error && [ $lb_exitcode != 0 ] ; then
						email_logs=true
					fi
				fi

				if $email_logs ; then
					email_content+="See the log file for more details.\n\n"
				fi

				email_content+="Regards,\ntime2backup"

				# send email
				if ! lb_email "${email_opts[@]}"-s "$email_subject" "$email_recipient" "$email_report_content" ; then
					lb_log_error "Email could not be sent."
				fi
			fi
		else
			# email not sent
			lb_log_error "Email recipient not set, do not send email report."
		fi
	fi

	# delete log file
	if ! $logs_save ; then

		delete_logs=false

		if [ $lb_exitcode == 0 ] ; then
			delete_logs=true
		else
			if ! $keep_logs_if_error ; then
				delete_logs=true
			fi
		fi

		if $delete_logs ; then
			lb_display_debug "Deleting log file..."

			# delete file
			rm -f "$logfile" &> /dev/null

			# if failed
			if [ $? != 0 ] ; then
				lb_display_debug "...Failed!"
			fi

			# delete logs directory if empty
			if lb_dir_is_empty "$logs_directory" ; then
				lb_display_debug "Deleting log directory..."

				rmdir "$logs_directory" &> /dev/null

				# if failed
				if [ $? != 0 ] ; then
					lb_display_debug "...Failed!"
				fi
			fi
		fi
	fi

	# if shutdown after backup, execute it
	if $shutdown ; then
		haltpc
	fi

	if $debugmode ; then
		echo
		lb_display_debug "Exited with code: $lb_exitcode"
	fi

	lb_exit
}


# Halt PC
haltpc() {

	# clear all traps to allow user to cancel countdown
	trap - 1 2 3 15
	trap

	# test shutdown command
	if ! lb_command_exists "${shutdown_cmd[0]}" ; then
		lb_display_error --log "No shutdown command found. PC will not halt."
		return 1
	fi

	# countdown before halt
	lb_print "\nYour computer will halt in 10 seconds. Press Ctrl-C to cancel."
	for ((i=10; i>=0; i--)) ; do
		echo -n "$i "
		sleep 1
	done

	# shutdown
	"${shutdown_cmd[@]}"
	if [ $? != 0 ] ; then
		lb_display_error --log "Error with shutdown command. PC is still up."
		return 1
	fi
}


# Choose an operation to execute (time2backup commands)
choose_operation() {

	# display choice
	if ! lbg_choose_option -d 1 -l "Choose an operation:" "Backup files" "Restore a file" "Configure time2backup" ; then
		return 1
	fi

	# run command
	case $lbg_choose_option in
		1)
			t2b_backup
			;;
		2)
			t2b_restore
			;;
		3)
			t2b_config
			;;
		*)
			# bad choice
			return 1
			;;
	esac
}


#######################
#  COMMAND FUNCTIONS  #
#######################

# Perform backup
# Usage: t2b_backup [OPTIONS]
t2b_backup() {

	# default values and options
	planned_backup=false
	source_ssh=false
	source_network=false

	# get options
	while true ; do
		case $1 in
			-p|--planned)
				planned_backup=true
				shift
				;;
			-h|--help)
				print_help backup
				return
				;;
			-*)
				print_help backup
				return 1
				;;
			*)
				break
				;;
		esac
	done

	# load and test configuration
	if ! load_config ; then
		return 2
	fi

	# get current date
	current_timestamp=$(date +%s)
	current_date=$(date '+%Y-%m-%d at %H:%M:%S')

	# set backup directory with current date (format: YYYY-MM-DD-HHMMSS)
	backup_date=$(date +%Y-%m-%d-%H%M%S)

	# get sources to backup
	get_sources

	# get number of sources to backup
	nbsrc=${#sources[@]}

	# is no sources, exit
	if [ $nbsrc == 0 ] ; then
		lb_display_warning "Nothing to backup!"
		return 3
	fi

	# test if destination exists
	if ! test_destination ; then
		return 4
	fi

	# create destination if not exists
	mkdir -p "$backup_destination" &> /dev/null
	if [ $? != 0 ] ; then
		lb_display_error "Could not create destination at $backup_destination. Please verify your access rights."
		return 4
	fi

	# test if destination is writable
	# must keep this test because if directory exists, the previous mkdir -p command returns no error
	if ! [ -w "$backup_destination" ] ; then
		lb_display_error "You have no write access on $backup_destination directory. Please verify your access rights."
		return 4
	fi

	# test if a backup is running
	ls "$backup_destination/.lock_"* &> /dev/null
	if [ $? == 0 ] ; then
		lb_error "A backup is already running. Abording."

		# delete backup lock
		release_lock

		# exit
		return 10
	fi

	# create lock to avoid duplicates
	backup_lock="$backup_destination/.lock_$backup_date"
	touch "$backup_lock"

	# catch term signals
	trap cancel_exit SIGHUP SIGINT SIGTERM

	# get old backups
	backups=($(get_backups))

	# if planned, check frequency
	if $planned_backup ; then

		# get last backup date
		last_backup_date=$(get_backup_fulldate ${backups[-1]})

		# if not found, continue; if found, check frequency
		if [ -n "$last_backup_date" ] ; then

			# get last backup timestamp
			# TODO: add macOS support (date -d is not same option)
			last_backup_timestamp=$(date -d "$last_backup_date" +%s)

			if [ -z "$last_backup_timestamp" ] ; then
				lb_display_error "Error in last backup timestamp."
				lb_display_debug "Continue backup..."
			else
				# convert frequency in seconds
				case "$frequency" in
					hourly)
						seconds_offset=3600
						;;
					weekly)
						seconds_offset=604800
						;;
					monthly)
						seconds_offset=18144000
						;;
					*) # daily (default)
						seconds_offset=86400
						;;
				esac

				# test if delay is passed
				test_timestamp=$(($current_timestamp - $last_backup_timestamp))

				if [ $test_timestamp -gt 0 ] ; then
					if [ $test_timestamp -le $seconds_offset ] ; then
						lb_display_debug "Last backup was done at $last_backup_date"
						lb_display_info "Planned backup: no need to backup."
						clean_exit
					fi
				else
					lb_display_critical "Last backup is more recent than today. Are you a time traveller?"
				fi
			fi
		fi
	fi

	# set log file path
	if [ -z "$logs_directory" ] ; then
		logs_directory="$backup_destination/logs"
	fi
	logfile="$logs_directory/time2backup_$backup_date.log"

	# create logs directory
	mkdir -p "$logs_directory"
	if [ $? != 0 ] ; then
		lb_error "Could not create logs directory. Please verify your access rights."
		clean_exit 4
	fi

	# create log file
	if ! lb_set_logfile "$logfile" ; then
		lb_error "Cannot create log file $logfile. Please verify your access rights."
		clean_exit 4
	fi

	lb_display --log "time2backup\n"
	lb_display --log "Backup started on $current_date\n"


	# execute before backup command/script
	if [ ${#exec_before[@]} -gt 0 ] ; then
		# test command/script
		if lb_command_exists "${exec_before[0]}" ; then
			"${exec_before[@]}"
			# if error
			if [ $? != 0 ] ; then
				lb_exitcode=8
				if $exec_before_block ; then
					lb_display_debug --log "Before script exited with error."
					clean_exit
				fi
			fi
		else
			lb_error "Error: cannot run command $exec_before"
			lb_exitcode=8
			if $exec_before_block ; then
				clean_exit
			fi
		fi
	fi

	# if keep limit to 0, we are in mirror mode
	if [ $keep_limit == 0 ] ; then
		mirror_mode=true
	fi

	# clean old backup if needed
	if [ $keep_limit -ge 0 ] ; then
		rotate_backups
	fi

	# get last backup
	last_backup=$(ls "$backup_destination" | grep -E "^[1-9][0-9]{3}-[0-1][0-9]-[0-3][0-9]-[0-2][0-9][0-5][0-9][0-5][0-9]$" | tail -n 1)

	# set new backup directory
	dest="$backup_destination/$backup_date"

	lb_display --log "Prepare backup..."

	# if mirror mode and there is an old backup, move last backup to current directory
	if $mirror_mode && [ -e "$backup_destination/$last_backup" ] ; then
		mv "$backup_destination/$last_backup" "$dest"
	else
		# create destination
		mkdir "$dest"
	fi

	# if failed to move or to create
	if [ $? != 0 ] ; then
		lb_display --log "Could not prepare backup destination. Please verify your access rights."
		clean_exit 4
	fi

	# check if destination supports hard links
	if $hard_links ; then
		if ! test_hardlinks ; then
			lb_display_debug --log "Destination does not support hard links. Continue in trash mode."
			hard_links=false
		fi
	fi

	# basic rsync command
	rsync_cmd=(rsync -aHv --delete --progress --human-readable)

	# of course, we exclude the backup destination itself (..../backups)
	rsync_cmd+=(--exclude "$(dirname "$backup_destination")")

	# get config for exclusions
	if [ -f "$config_excludes" ] ; then
		rsync_cmd+=(--exclude-from "$config_excludes")
	fi

	# get additionnal exclude file
	if [ -f "$exclude_file" ] ; then
		rsync_cmd+=(--exclude-from "$exclude_file")
	fi

	# add max size if specified
	if [ -n "$max_size" ] ; then
		rsync_cmd+=(--max-size "$max_size")
	fi

	# add user defined options
	if [ ${#rsync_options[@]} -gt 0 ] ; then
		rsync_cmd+=("${rsync_options[@]}")
	fi

	# execute backup for each source
	# do a loop like this to prevent errors with spaces in strings
	# do not use for ... in ... syntax
	for ((s=0; s < $nbsrc; s++)) ; do

		src="${sources[$s]}"

		total_size=""

		lb_display --log "\n********************************************\n"
		lb_display --log "Backup $src... ($(($s + 1))/$nbsrc)\n"

		case $(get_backup_type "$src") in
			ssh)
				source_ssh=true
				source_network=true
				# do not include protocol
				abs_src="${src:6}"
				path_dest="$(get_backup_path "$src")"
				;;
			*)
				# file or directory
				# replace ~ by user home directory
				if [ "${src:0:1}" == "~" ] ; then
					homealias="$(echo "$src" | awk -F '/' '{ print $1 }')"
					if [ "$homealias" == "~" ] ; then
						homedir="$(lb_homepath $user)"
						if [ $? != 0 ] ; then
							lb_display_error --log "Cannot get user homepath.\nPlease use absolute paths instead of ~ aliases in your sources.conf file."
							errors+=("$src (does not exists)")
							lb_exitcode=5

							# continue to next source
							continue
						fi
					else
						homedir="$(lb_homepath "${homealias:1}")"
					fi
					src="$homedir/$(echo "$src" | sed 's/^[^/]*\///')"
				fi

				# get absolute path for source
				abs_src="$(get_absolute_path "$src")"

				# test if source exists
				if ! [ -e "$abs_src" ] ; then
					lb_error "Source $src does not exists!"
					errors+=("$src (does not exists)")
					lb_exitcode=5

					# continue to next source
					continue
				fi

				path_dest="$(get_backup_path "$abs_src")"
				;;
		esac

		# set final destination with is a representation of system tree
		# e.g. /path/to/my/backups/mypc/2016-12-31-2359/files/home/user/tobackup
		finaldest=$(dirname "$dest/$path_dest")

		# create destination folder
		mkdir -p "$finaldest"
		prepare_dest=$?

		# find the last backup of this source
		# starting at last but not current (array length - 2)
		lastcleanbackup=""

		if [ -n "$last_backup" ] ; then
			# find the last successfull backup
			old_backups=($(get_backups))
			for ((b=${#old_backups[@]}-2; b>=0; b--)) ; do
				old_backup_path="$backup_destination/${old_backups[$b]}/$path_dest"

				if [ -d "$old_backup_path" ] ; then
					if ! lb_dir_is_empty "$old_backup_path" ; then
						lastcleanbackup="${old_backups[$b]}"

						lb_display_debug --log "Last backup found: $lastcleanbackup for $backup_destination/${old_backups[$b]}/$path_dest"
						break
					fi
				fi
			done
		fi

		if ! $hard_links ; then
			# move old backup as current backup, if exists
			if [ -n "$lastcleanbackup" ] ; then
				mv "$backup_destination/$lastcleanbackup/$path_dest" "$finaldest"
				prepare_dest=$?
			fi
		fi

		if [ $prepare_dest != 0 ] ; then
			lb_display --log "Could not prepare backup destination for source $src. Please verify your access rights."

			# prepare report and save exit code
			errors+=("$src (code: 4)")
			if [ $lb_exitcode == 0 ] ; then
				lb_exitcode=4
			fi

			clean_empty_directories "$finaldest"

			# continue to next source
			continue
		fi

		# define rsync command
		cmd=("${rsync_cmd[@]}")

		if ! $mirror_mode ; then
			# if first backup, no need to add incremental options
			if [ -n "$lastcleanbackup" ] ; then
				# if destination supports hard links, use incremental with hard links system
				if $hard_links ; then
					# revision folder
					linkdest="$(get_relative_path "$finaldest" "$backup_destination")"
					if [ -e "$linkdest" ] ; then
						cmd+=(--link-dest="$(dirname "$linkdest/$lastcleanbackup/$path_dest")")
					fi
				else
					# backups with a "trash" folder that contains older revisions
					# be careful that trash must be set to parent directory
					# or it will create something like dest/src/src
					trash="$(dirname "$backup_destination/$lastcleanbackup/$path_dest")"

					# create trash
					mkdir -p "$trash"

					# move last destination
					cmd+=(-b --backup-dir "$trash")
				fi
			fi
		fi

		# search in source if exclude conf file is set
		if [ -f "$abs_src/.rsyncignore" ] ; then
			cmd+=(--exclude-from="$abs_src/.rsyncignore")
		fi

		# add ssh options
		if $source_ssh ; then
			cmd+=(-e "ssh $ssh_options")
		fi

		# enable network compression
		if $network_compression ; then
			cmd+=(-z)
		fi

		# add source and destination
		cmd+=("$abs_src" "$finaldest")

		lb_display --log "Testing rsync..."

		# test rsync and space available for backup
		if ! test_backup ; then
			lb_display --log "Error in your rsync syntax."

			# prepare report and save exit code
			errors+=("$src (code: 1)")
			if [ $lb_exitcode == 0 ] ; then
				lb_exitcode=1
			fi

			clean_empty_directories "$finaldest"

			# continue to next source
			continue
		fi

		space_ok=false

		# test free space until it's ready
		while true ; do
			# if space ok, continue
			if test_space $total_size ; then
				space_ok=true
				break
			fi

			# if clean old backups authorized in config,
			if $clean_old_backups ; then

				# get all backups list
				old_backups=($(get_backups))
				# avoid infinite loop and always keep one current backup
				if [ ${#old_backups[@]} -le 1 ] ; then
					break
				fi

				# set keep limit to
				keep_limit=$((${#old_backups[@]} - 1 - $clean_keep))

				if [ $keep_limit -le 1 ] ; then
					break
				fi

				rotate_backups
			else
				# if no cleanup, continue to be stopped after
				break
			fi
		done

		# if not enough space on disk to backup, cancel
		if ! $space_ok ; then
			lb_display_error --log "Not enough space on device to backup. Abording."

			# prepare report and save exit code
			errors+=("$src (code: 4)")
			if [ $lb_exitcode == 0 ] ; then
				lb_exitcode=4
			fi

			clean_empty_directories "$finaldest"

			# continue to next source
			continue
		fi

		lb_display_debug --log "Executing: ${cmd[@]}\n"

		if $notifications ; then
			if [ $s == 0 ] ; then
				lbg_notify "Backup started at $(date '+%H:%M:%S')"
			fi
		fi

		# execute rsync command, print into terminal and logfile
		"${cmd[@]}" 2> >(tee -a "$logfile" >&2)

		# get backup result and prepare report
		res=${PIPESTATUS[0]}
		case $res in
			0|24)
				# ignoring vanished files in transfer
				success+=("$src")
				;;
			1|2|3|4|5|6)
				# critical errors that caused backup to fail
				errors+=("$src (backup failed; code: $res)")
				lb_exitcode=6
				;;
			*)
				# considering any other rsync error as not critical
				# (some files were not backuped)
				warnings+=("$src (some files were not backuped; code: $res)")
				lb_exitcode=7
				;;
		esac

		# clean empty trash directories
		if ! $hard_links ; then
			clean_empty_directories "$trash"
		fi

		# clean empty backup if error
		clean_empty_directories "$finaldest"
	done

	# final report
	lb_display --log "\n********************************************"
	lb_display --log "\nBackup ended on $(date '+%Y-%m-%d at %H:%M:%S')"

	lb_display --log "$(report_duration)\n"

	if [ $lb_exitcode == 0 ] ; then
		lb_display --log "Backup finished successfully."

		if $notifications ; then
			lbg_notify "Backup finished successfully.\n$(report_duration)"
		fi
	else
		lb_display --log "Backup finished with some errors. Check report below and check log files for more details.\n"

		if [ ${#success[@]} -gt 0 ] ; then
			report_details+="Success: (${#success[@]}/$nbsrc)\n"
			for ((i=0; i<${#success[@]}; i++)) ; do
				report_details+="   - ${success[$i]}\n"
			done
		fi
		if [ ${#warnings[@]} -gt 0 ] ; then
			report_details+="Warnings: (${#warnings[@]}/$nbsrc)\n"
			for ((i=0; i<${#warnings[@]}; i++)) ; do
				report_details+="   - ${warnings[$i]}\n"
			done

			if $notifications ; then
				lbg_notify "Backup finished successfully, but some files may not be transferred.\n$(report_duration)"
			fi
		fi
		if [ ${#errors[@]} -gt 0 ] ; then
			report_details+="Errors: (${#errors[@]}/$nbsrc)\n"
			for ((i=0; i<${#errors[@]}; i++)) ; do
				report_details+="   - ${errors[$i]}\n"
			done

			if $notifications ; then
				lbg_notify "Backup finished with some errors. Check report and check log files for more details.\n$(report_duration)"
			fi
		fi

		lb_display --log "$report_details"
	fi

	# execute custom after backup script
	if [ ${#exec_after[@]} -gt 0 ] ; then
		# test command/script
		if lb_command_exists "${exec_after[0]}" ; then
			"${exec_after[@]}"
			# if error, do not overwrite rsync exit code
			if [ $? != 0 ] ; then
				if [ $lb_exitcode != 0 ] ; then
					lb_exitcode=9
				fi
				if $exec_after_block ; then
					clean_exit
				fi
			fi
		else
			lb_display --log "Error: cannot run command $exec_after"
			# if error, do not overwrite rsync exit code
			if [ $lb_exitcode != 0 ] ; then
				lb_exitcode=9
			fi
			if $exec_after_block ; then
				 clean_exit
			fi
		fi
	fi

	clean_exit
}


# Get history/versions of a file
# Usage: t2b_history [OPTIONS] PATH
# Options:
#   -a, --all    print all versions (including duplicates)
#   -q, --quiet  quiet mode: print only backup dates
#   -h, --help   print help
# Exit codes:
#   0: history printed
#   1: usage error
#   2: config error
#   3: no backup found for path
#   4: backup device not reachable
t2b_history() {

	# default options and variables
	file_history=()
	quietmode=false

	# get options
	while true ; do
		case $1 in
			-a|--all)
				opts="-a "
				shift
				;;
			-q|--quiet)
				quietmode=true
				shift
				;;
			-h|--help)
				print_help history
				return
				;;
			-*)
				print_help history
				return 1
				;;
			*)
				break
				;;
		esac
	done

	# usage errors
	if [ $# == 0 ] ; then
		print_help history
		return 1
	fi

	# load and test configuration
	if ! load_config ; then
		return 2
	fi

	# test backup destination
	if ! test_destination ; then
		return 4
	fi

	# get file
	file="$*"

	# get backup versions of this file
	backup_history=$(get_backup_history $opts"$file")

	if [ -z "$backup_history" ] ; then
		lb_error "No backup found for '$file'!"
		return 3
	fi

	if ! $quietmode ; then
		lb_print "$file: ${#file_history[@]} backups"
	fi

	# print backup versions
	for b in ${backup_history[@]} ; do
		lb_print $b
	done
}


# Restore a file
# Usage: t2b_restore [OPTIONS] [PATH]
t2b_restore() {

	# default options
	backup_date="latest"
	file_history=()
	forcemode=false
	choose_file=false
	interactive=true
	directorymode=false
	restore_moved=false
	delete_newer_files=false

	# get options
	while true ; do
		case $1 in
			-d|--date)
				backup_date="$2"
				interactive=false
				shift 2
				;;
			--directory)
				directorymode=true
				shift
				;;
			--delete-new)
				delete_newer_files=true
				shift
				;;
			-f|--force)
				forcemode=true
				shift
				;;
			-h|--help)
				print_help restore
				return
				;;
			-*)
				print_help restore
				return 1
				;;
			*)
				break
				;;
		esac
	done

	# load and test configuration
	if ! load_config ; then
		return 2
	fi

	# test backup destination
	if ! test_destination ; then
		return 4
	fi

	if ! test_hardlinks ; then
		hard_links=false
	fi

	# if no file specified, go to interactive mode
	if [ $# == 0 ] ; then

		restore_opts=("An existing file" "A renamed/moved/deleted file")

		if $hard_links ; then
			restore_opts+=("An existing directory" "A renamed/moved/deleted directory")
		fi

		# choose type of file to restore (file/directory)
		lbg_choose_option -d 1 -l "What do you want to restore?" "${restore_opts[@]}"
		case $? in
			0)
				# continue
				:
				;;
			2)
				# cancelled
				return
				;;
			*)
				# error
				return 1
				;;
		esac

		# directory mode
		case "$lbg_choose_option" in
			1)
				# restore a file
				:
				;;
			2)
				# restore a moved file
				starting_path="$backup_destination"
				restore_moved=true
				;;
			3)
				# restore a directory
				directorymode=true
				;;
			4)
				# restore a moved directory
				starting_path="$backup_destination"
				directorymode=true
				restore_moved=true
				;;
			*)
				return 1
				;;
		esac

		# choose a directory
		if $directorymode ; then
			lbg_choose_directory -t "Choose a directory to restore" "$starting_path"
			case $? in
				0)
					# continue
					:
					;;
				2)
					# cancelled
					return
					;;
				*)
					# error
					return 1
					;;
			esac

			# get path to restore
			file="$lbg_choose_directory"
		else
			# choose a file
			lbg_choose_file -t "Choose a file to restore" "$starting_path"
			case $? in
				0)
					# continue
					:
					;;
				2)
					# cancelled
					return
					;;
				*)
					# error
					return 1
					;;
			esac

			# get path to restore
			file="$lbg_choose_file"
		fi

		# restore a moved file
		if $restore_moved ; then

			# test if path to restore is stored in the backup directory
			if [[ "$file" != "$backup_destination"* ]] ; then
				lb_error "Path is not a backup! Cancel."
				return 1
			fi

			# save path as source
			src="$file"

			# remove destination path prefix
			file="${file#$backup_destination}"
			# remove slashes
			if [ "${file:0:1}" == "/" ] ; then
				file="${file:1}"
			fi

			# get backup date
			backup_date="$(echo "$file" | grep -oE "^[1-9][0-9]{3}-[0-1][0-9]-[0-3][0-9]-[0-2][0-9][0-5][0-9][0-5][0-9]" 2> /dev/null)"
			if [ -z "$backup_date" ] ; then
				lb_error "Path is not correct"
				return 1
			fi

			interactive=false

			# remove backup date path prefix
			file="${file#$backup_date}"

			# check if it is a file backup
			# TODO: add SSH/network support
			if [ "$(echo ${file:0:7})" != "/files/" ] ; then
				lb_error "Restoring ssh/network files is not supported yet."
				return 6
			fi

			# absolute path of destination
			file="${file:6}"
		fi
	else
		# get specified path
		file="$*"
	fi

	if [ -n "$src" ] ; then
		symlink_test="$src"
	else
		symlink_test="$file"
	fi

	# case of symbolic links
	if [ -L "$symlink_test" ] ; then
		lbg_display_error "You cannot restore symbolic links!"
		return 6
	fi

	lb_display_debug "File to restore: $file"

	# get backup full path
	backup_file_path="$(get_backup_path "$file")"

	# if error, exit
	if [ -z "$backup_file_path" ] ; then
		return 1
	fi

	# get all backups
	backups=($(get_backups))
	if [ ${#backups[@]} == 0 ] ; then
		lbg_display_error "No backups on destination."
		return 3
	fi

	# find last backup of the file
	for ((j=${#backups[@]}-1; j>=0; j--)) ; do
		backup="${backups[$j]}"
		backup_file="$backup_destination/$backup/$backup_file_path"

		# if backup found,
		if [ -e "$backup_file" ] ; then
			# add backup to the list of backups
			file_history+=("${backups[$j]}")
			lb_display_debug "Found backup: ${backups[$j]}"
		else
			# if no backup at this date,
			if [ "$backup_date" != "latest" ] ; then
				# if date was specified, error
				if [ "$backup_date" == "$backup" ] ; then
					lbg_display_error "No backups available for this file at this date!\nRun the following command to show available backup for this file: $lb_current_script history $file"
					return 3
				fi
			fi
		fi
	done

	# if no backup found
	if [ ${#file_history[@]} == 0 ] ; then
		lbg_display_error "No backups available for this file."
		return 3
	fi

	# if interactive mode, prompt user to choose a backup date
	if $interactive ; then
		lbg_choose_option -d 1 -l "Choose a backup date:" "${file_history[@]}"
		case $? in
			0)
				# continue
				:
				;;
			2)
				# cancelled
				return
				;;
			*)
				# error
				return 1
				;;
		esac

		backup_date=${file_history[$(($lbg_choose_option - 1))]}
	fi

	# if no backup date specified, use most recent
	if [ "$backup_date" == "latest" ] ; then
		backup_date=${file_history[0]}
	fi

	src="$backup_destination/$backup_date/$backup_file_path"

	# if source is a directory
	if [ -d "$src" ] ; then
		directorymode=true
	fi

	# trash mode: cannot restore directories
	if $directorymode ; then

		# trash mode: cannot restore directories
		if ! $hard_links ; then
			lb_error "You cannot restore directories in trash mode!"
			return 6
		fi

		# destination is the parent directory with a '/' at the end of the path (IMPORTANT)
		dest="$(dirname "$file")/"
	else
		dest="$file"
	fi

	# prepare rsync command
	rsync_cmd=(rsync -aHv --exclude-from "$config_excludes" )

	# test newer files
	if ! $delete_newer_files ; then
		if $directorymode ; then
			# prepare test command
			cmd=("${rsync_cmd[@]}")
			cmd+=(--delete --dry-run "$src" "$dest")

			lb_print "Testing restore..."

			# test to check newer files
			"${cmd[@]}" | grep "^deleting "

			if [ $? == 0 ] ; then
				if ! lbg_yesno "There are newer files in $dest. Do you want to keep them?\nPress Yes to keep new files, No to restore backup exactly as before." ; then
					delete_newer_files=true
				fi
			fi
		else
			# if restore a file, always delete new
			delete_newer_files=true
		fi
	fi

	# confirm restore
	if ! $forcemode ; then
		if ! lbg_yesno "You will restore the path '$file' to backup $(get_backup_fulldate $backup_date).\nAre your sure?" ; then
			# cancelled
			return
		fi
	fi

	# prepare rsync restore command
	cmd=("${rsync_cmd[@]}")

	if $delete_newer_files ; then
		cmd+=(--delete)
	fi

	cmd+=(--progress --human-readable "$src" "$dest")

	lb_print "Restore file from backup $backup_date..."
	lb_display_debug "Executing: ${cmd[@]}"

	# execute rsync command
	"${cmd[@]}"
	lb_result

	# rsync results
	case $? in
		0)
			# file restored
			restore_notification="File restored: $file"
			lb_display_info "$restore_notification"
			;;
		*)
			# rsync error
			restore_notification="Restore file failed for $file"
			lb_display_error "$restore_notification"
			lb_exitcode=5
			;;
	esac

	# display notification
	if $notifications ; then
		lbg_notify "$restore_notification"
	fi

	return $lb_exitcode
}


# Configure time2backup
# Usage: t2b_config [OPTIONS]
t2b_config() {

	# default values
	file="$config_file"
	op_config="edit"
	show_sources=false

	# get options
	# following other options to edit_config() function
	while true ; do
		case $1 in
			-x|--excludes)
				file="$config_excludes"
				shift
				;;
			-s|--sources)
				file="$config_sources"
				show_sources=true
				shift
				;;
			-l|--show)
				op_config="show"
				shift
				;;
			-t|--test)
				op_config="test"
				shift
				;;
			-a|--apply)
				op_config="apply"
				shift
				;;
			-w|--wizard)
				op_config="wizard"
				shift
				;;
			-h|--help)
				print_help config
				return
				;;
			-*)
				print_help config
				return 1
				;;
			*)
				break
				;;
		esac
	done

	# special operations: show and test
	case "$op_config" in
		wizard)
			load_config

			# run config wizard
			if config_wizard ; then
				install_config
			fi
			;;
		show)
			# get sources is a special case to print list without comments
			# read sources.conf file line by line
			while read line ; do
				if ! is_comment -n $line ; then
					echo "$line"
				fi
			done < "$file"
			;;
		test)
			# load and test configuration
			lb_print "Testing configuration..."
			load_config
			lb_result
			;;
		apply)
			# apply configuration
			install_config
			;;
		*)
			# edit configuration
			lb_print "Opening configuration file..."
			if edit_config $* "$file" ; then
				install_config
			fi
			;;
	esac

	return $?
}


# Install time2backup
# Create a link to execute time2backup easely and create default configuration
# Usage: t2b_install [OPTIONS]
t2b_install() {
	reset_config=false

	# get options
	while true ; do
		case $1 in
			-r|--reset-config)
				reset_config=true
				shift
				;;
			-h|--help)
				print_help install
				return
				;;
			-*)
				print_help install
				return 1
				;;
			*)
				break
				;;
		esac
	done

	lb_print "Install time2backup..."

	# reset configuration
	if $reset_config ; then
		rm -f "$config_directory/time2backup.conf"

		if ! create_config ; then
			return 2
		fi
	fi

	if [ -e "$cmd_alias" ] ; then
		if [ "$(lb_realpath "$cmd_alias")" == "$current_script" ] ; then
			lb_print "Already installed."
			return
		fi
	fi

	if ! [ -w "$(dirname "$cmd_alias")" ] ; then
		lb_print "Error: cannot create link to executable. Try the following command:"
		lb_print "sudo ln -s \"$current_script\" \"$cmd_alias\""
		return 3
	fi

	# delete old link if exists
	rm -f "$cmd_alias"

	# create link
	ln -s "$current_script" "$cmd_alias" &> /dev/null
	if [ $? != 0 ] ; then
		lb_print "Failed to create the link. You may try to run with superuser."
		lb_print "Try: sudo ln -s \"$current_script\" \"$cmd_alias\""
		return 3
	fi
}


##################
#  MAIN PROGRAM  #
##################

# get global options
while true ; do
	case "$1" in
		-C|--console)
			consolemode=true
			shift
			;;
		-c|--config)
			if lb_test_arguments -eq 0 $2 ; then
				print_help
				exit 1
			fi
			config_file="$2"
			# test if file exists
			if ! [ -f "$config_file" ] ; then
				lb_print "Configuration file $config_file does not exists!"
				exit 1
			fi
			shift 2
			;;
		-u|--user)
			if lb_test_arguments -eq 0 $2 ; then
				print_help
				exit 1
			fi
			user="$2"
			shift 2
			;;
		-l|--log-level)
			if lb_test_arguments -eq 0 $2 ; then
				print_help
				exit 1
			fi
			log_level="$2"
			shift 2
			;;
		-v|--verbose-level)
			if lb_test_arguments -eq 0 $2 ; then
				print_help
				exit 1
			fi
			verbose_level="$2"
			shift 2
			;;
		-D|--debug)
			debugmode=true
			shift
			;;
		-V|--version)
			echo $version
			exit
			;;
		-h|--help)
			print_help
			exit
			;;
		-*)
			print_help
			exit 1
			;;
		*)
			break
			;;
	esac
done

# disable dialogs if console mode
if $consolemode ; then
	lbg_set_gui console
fi

# test if rsync command is available
if ! lb_command_exists rsync ; then
	lbg_display_critical "rsync is not installed. time2backup will not work.\nPlease install it and retry."
	exit 1
fi

# go into current directory to avoid relative path confusion
cd "$lb_current_script_directory"

# set default configuration file and path
if [ -z "$config_file" ] ; then
	config_directory="$(lb_homepath $user)/.config/time2backup/"
	if [ $? != 0 ] ; then
		lbg_display_error "Cannot get user homepath. Please install your config file manually."
		exit 2
	fi
	config_file="$config_directory/time2backup.conf"
else
	# parent directory of specified configuration file
	config_directory="$(dirname "$config_file")"
fi

# default sources and excludes files
config_sources="$config_directory/sources.conf"
config_excludes="$config_directory/excludes.conf"

# if debug mode, log and display everything (no level limit)
if $debugmode ; then
	lb_display_debug "Running in DEBUG mode...\n"
else
	# defines log level
	# if not set (unknown error), set to default level
	if ! lb_set_loglevel "$log_level" ; then
		lb_set_loglevel "$default_log_level"
	fi

	# defines verbose level
	# if not set (unknown error), set to default level
	# TODO: implement lb_set_displaylevel
	if ! lb_set_loglevel "$verbose_level" ; then
		lb_set_loglevel "$default_verbose_level"
	fi
fi

# if configuration file does not exists, execute first run wizard then exit
if ! [ -f "$config_file" ] ; then
	first_run
	exit $?
fi

# command operations
case "$1" in
	backup)
		shift
		t2b_backup $*
		;;
	history)
		shift
		t2b_history $*
		;;
	restore)
		shift
		t2b_restore $*
		;;
	config)
		shift
		t2b_config $*
		;;
	install)
		shift
		t2b_install $*
		;;
	"")
		choose_operation
		;;
	*)
		print_help
		exit 1
		;;
esac

lb_exitcode=$?

if $debugmode ; then
	lb_print
	lb_display_debug "Exited with code: $lb_exitcode"
fi

lb_exit
