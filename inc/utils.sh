#
# time2backup utils functions
#
# This file is part of time2backup (https://time2backup.github.io)
#
# MIT License
# Copyright (c) 2017 Jean Prunneaux
#

# Index of functions
#
#   Global functions
#      timestamp2date
#      get_backup_fulldate
#      get_backup_history
#      create_config
#      upgrade_config
#      test_config
#      load_config
#      mount_destination
#      unmount_destination
#      get_backup_path
#      get_backups
#      delete_backup
#      rotate_backups
#      report_duration
#      crontab_config
#      apply_config
#      prepare_destination
#      create_logfile
#      test_backup
#      test_free_space
#      clean_empty_directories
#      edit_config
#      current_lock
#      release_lock
#      prepare_rsync
#      is_installed
#   Exit functions
#      clean_exit
#      cancel_exit
#      haltpc
#   Wizards
#      choose_operation
#      config_wizard
#      first_run


######################
#  GLOBAL FUNCTIONS  #
######################

# Convert timestamp to an user readable date
# Usage: timestamp2date TIMESTAMP
# Return: formatted date
timestamp2date() {
	# return date formatted in user language
	if [ "$lb_current_os" == macOS ] ; then
		date -j -f "%s" "$1" +"$tr_readable_date"
	else
		date -d "@$1" +"$tr_readable_date"
	fi
}


# Get readable backup date
# Usage: get_backup_fulldate YYYY-MM-DD-HHMMSS
# Return: backup datetime (format YYYY-MM-DD HH:MM:SS)
# e.g. 2016-12-31-233059 -> 2016-12-31 23:30:59
# Exit codes:
#   0: OK
#   1: format error
get_backup_fulldate() {

	# test backup format (YYYY-MM-DD-HHMMSS)
	echo "$1" | grep -E "^[1-9][0-9]{3}-[0-1][0-9]-[0-3][0-9]-[0-2][0-9][0-5][0-9][0-5][0-9]$" &> /dev/null

	# if not good format, return error
	if [ $? != 0 ] ; then
		return 1
	fi

	# get date details
	byear=${1:0:4}
	bmonth=${1:5:2}
	bday=${1:8:2}
	bhour=${1:11:2}
	bmin=${1:13:2}
	bsec=${1:15:2}

	# return date formatted for languages
	if [ "$lb_current_os" == macOS ] ; then
		date -j -f "%Y-%m-%d %H:%M:%S" "$byear-$bmonth-$bday $bhour:$bmin:$bsec" +"$tr_readable_date"
	else
		date -d "$byear-$bmonth-$bday $bhour:$bmin:$bsec" +"$tr_readable_date"
	fi
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
	while [ -n "$1" ] ; do
		case $1 in
			-a|--all)
				allversions=true
				;;
			*)
				break
				;;
		esac
		shift # load next argument
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
	file=$*

	# get backup path
	abs_file=$(get_backup_path "$file")
	if [ -z "$abs_file" ] ; then
		return 3
	fi

	# try to find backup
	last_inode=""
	last_symlink_target=""
	for ((h=${#backups[@]}-1; h>=0; h--)) ; do

		backup_date=${backups[$h]}

		# check if file/directory exists
		backup_file="$backup_destination/$backup_date/$abs_file"

		# if file/directory exists,
		if [ -e "$backup_file" ] ; then

			# check if a backup is currently running
			if [ "$(current_lock)" == "$backup_date" ] ; then
				# ignore current backup (if running, it could contain errors)
				continue
			fi

			# if all versions, do not compare files and quit
			if $allversions ; then
				file_history+=("$backup_date")
				continue
			fi

			#  DIRECTORIES

			if [ -d "$backup_file" ] ; then

				# subtility: path/to/symlink_dir/ is not detected as a link, but so does path/to/symlink_dir
				if [ "${backup_file:${#backup_file}-1}" == "/" ] ; then
					# return path without the last /
					backup_dir=${backup_file:0:${#backup_file}-1}
				else
					backup_dir=$backup_file
				fi

				backup_file=$backup_dir

				# if it is really a directory and not a symlink,
				if ! [ -L "$backup_file" ] ; then
					# NEW FEATURE TO COME: DETECT DIRECTORY CHANGES
					# for now, just add it to list
					file_history+=("$backup_date")
					continue
				fi
			fi

			#  SYMLINKS

			# detect symlinks changes
			if [ -L "$backup_file" ] ; then
				symlink_target=$(readlink "$backup_file")

				if [ "$symlink_target" != "$last_symlink_target" ] ; then
					file_history+=("$backup_date")

					# save last target to compare to next one
					last_symlink_target=$symlink_target
				fi

				continue
			fi

			#  REGULAR FILES

			# if no hardlinks, no need to test inodes
			if ! test_hardlinks "$destination" ; then
				file_history+=("$backup_date")
				continue
			fi

			# compare inodes to detect different versions
			if [ "$lb_current_os" == macOS ] ; then
				inode=$(stat -f %i "$backup_file")
			else
				inode=$(stat --format %i "$backup_file")
			fi

			if [ "$inode" != "$last_inode" ] ; then
				file_history+=("$backup_date")

				# save last inode to compare to next
				last_inode=$inode
			fi
		fi
	done

	# return file versions
	if [ ${#file_history[@]} -gt 0 ] ; then
		for h in ${file_history[@]} ; do
			echo "$h"
		done
	else
		# no backups
		return 2
	fi

	return 0
}


# Create configuration files in user config
# Usage: create_config
# Exit codes:
#   0: OK
#   1: could not create config directory
#   2: could not copy sources config file
#   3: could not copy global config file
create_config() {

	# create config directory
	# default: ~/.config/time2backup
	mkdir -p "$config_directory" &> /dev/null
	if [ $? != 0 ] ; then
		lb_error "Cannot create config directory. Please verify your access rights or home path."
		return 1
	fi

	# copy config samples from current directory
	if ! [ -f "$config_excludes" ] ; then
		cp -f "$script_directory/config/excludes.example.conf" "$config_excludes"
	fi

	if ! [ -f "$config_sources" ] ; then
		cp -f "$script_directory/config/sources.example.conf" "$config_sources"
		if [ $? != 0 ] ; then
			lb_error "Cannot create sources file."
			return 2
		fi
	fi

	if ! [ -f "$config_file" ] ; then
		cp -f "$script_directory/config/time2backup.example.conf" "$config_file"
		if [ $? != 0 ] ; then
			lb_error "Cannot create config file."
			return 3
		fi
	fi
}


# Upgrade configuration
# Usage: upgrade_config CURRENT_VERSION
# Exit codes:
#   0: upgrade OK
#   1: compatibility error
#   2: write error
upgrade_config() {

	# get config version
	old_config_version=$(grep "time2backup configuration file v" "$config_file" | grep -o "[0-9].[0-9].[0-9][^\ ]*")
	if [ -z "$old_config_version" ] ; then
		lb_display_error "Cannot get config version."
		return 1
	fi

	# if current version, OK
	if [ "$old_config_version" == "$version" ] ; then
		return 0
	fi

	echo
	lb_print "$tr_upgrade_config"
	lb_display_debug "Upgrading config v$old_config_version -> v$version"

	# specific changes per version

	# e.g. a parameter that needs to be renamed
	# (nothing for now)
	#case $old_config_version in
	#	1.0.*)
	#		sed -i~ "s/^old_param=/new_param=/" "$config_file"
	#		;;
	#esac
	#
	#if [ $? != 0 ] ; then
	#	lb_display_error "Your configuration file is not compatible with this version. Please reconfigure manually."
	#	return 1
	#fi

	# replace config by new one

	# save old config file
	old_config="$config_file.v$old_config_version"

	lb_display_debug "Save old config..."
	cp -p "$config_file" "$old_config"
	if [ $? != 0 ] ; then
		lb_display_error "Cannot save old config! Please check your access rights."
		return 2
	fi

	lb_display_debug "Replace by new config..."
	cat "$script_directory/config/time2backup.example.conf" > "$config_file"
	if [ $? != 0 ] ; then
		lb_display_error "$tr_error_upgrade_config"
		return 2
	fi

	# read old config
	while read -r config_line ; do
		config_param=$(echo $config_line | cut -d= -f1 | tr -d '[[:space:]]')
		config_line=$(echo "$config_line" | sed 's/\\/\\\\/g; s/\//\\\//g')

		lb_display_debug "Upgrade $config_line..."

		sed -i~ "s/^#*$config_param[[:space:]]*=.*/$config_line/" "$config_file"
		if [ $? != 0 ] ; then
			lb_display_error "$tr_error_upgrade_config"
			return 2
		fi
	done < <(cat "$old_config" | grep -Ev '^$' | grep -Ev '^\s*#')

	# delete old config
	rm -f "$old_config" &> /dev/null

	echo

	# do not care of errors
	return 0
}


# Test configuration
# Usage: test_config
# Exit codes:
#   0: OK
#   1: there are errors in config
test_config() {

	# test if destination is defined
	if [ -z "$destination" ] ; then
		lb_error "Destination is not set!"
		return 1
	fi

	# convert destination for windows systems
	if [ "$lb_current_os" == Windows ] ; then
		destination=$(lb_realpath "$destination")

		if [ $? != 0 ] ; then
			lb_error "Error in Windows destination path!"
			return 1
		fi
	fi

	# test if sources file exists
	if ! [ -f "$config_sources" ] ; then
		lb_error "No sources file found!"
		return 1
	fi

	# test config values

	# test boolean values
	test_boolean=(destination_subdirectories test_destination resume_cancelled resume_failed clean_old_backups recurrent mount exec_before_block unmount unmount_auto shutdown exec_after_block notifications console_mode network_compression hard_links force_hard_links)
	for v in ${test_boolean[@]} ; do
		if ! lb_is_boolean ${!v} ; then
			lb_error "$v must be a boolean!"
			return 1
		fi
	done

	# test integer values
	test_integer=(keep_limit clean_keep)
	for v in ${test_integer[@]} ; do
		if ! lb_is_integer ${!v} ; then
			lb_error "$v must be an integer!"
			return 1
		fi
	done

	# other specific tests
	if [ $clean_keep -lt 0 ] ; then
		lb_error "clean_keep must be a positive integer!"
		return 1
	fi
}


# Load configuration file
# Usage: load_config
# Exit codes:
#   0: OK
#   1: cannot open config
#   2: there are errors in config
load_config() {

	echo -e "\n$tr_loading_config"

	# load config
	if ! lb_import_config "$config_file" ; then
		lb_display_error "$tr_error_read_config"
		return 1
	fi

	# if destination is overriden, set it
	if [ -n "$force_destination" ] ; then
		destination=$force_destination
	fi

	# increment clean_keep to 1 to keep the current backup
	clean_keep=$(($clean_keep + 1))

	# set backup destination
	if $destination_subdirectories ; then
		# add subdirectories
		backup_destination="$destination/backups/$(hostname)/"
	else
		backup_destination="$destination/"
	fi
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
#   6: cannot delete mount point
mount_destination() {

	# if UUID not set, return error
	if [ -z "$backup_disk_uuid" ] ; then
		return 5
	fi

	lb_display --log "Trying to mount backup disk..."

	# macOS and Windows are not supported
	# this is not supposed to happen because macOS and Windows always mount disks
	if [ "$lb_current_os" != Linux ] ; then
		lb_display_error --log "Mount: $lb_current_os not supported"
		return 4
	fi

	# test if UUID exists (disk plugged)
	ls /dev/disk/by-uuid/ | grep "$backup_disk_uuid" &> /dev/null
	if [ $? != 0 ] ; then
		lb_display_debug --log "Disk not available."
		return 2
	fi

	# create mountpoint
	if ! [ -d "$backup_disk_mountpoint" ] ; then

		lb_display --log "Create disk mountpoint..."
		mkdir -p "$backup_disk_mountpoint"

		# if failed, try in sudo mode
		if [ $? != 0 ] ; then
			lb_display_debug --log "...Failed! Try with sudo..."
			sudo mkdir -p "$backup_disk_mountpoint"

			if [ $? != 0 ] ; then
				lb_display --log "...Failed!"
				# failed to create mount point
				return 3
			fi
		fi
	fi

	# mount disk
	lb_display --log "Mount backup disk..."
	mount "/dev/disk/by-uuid/$backup_disk_uuid" "$backup_disk_mountpoint"

	# if failed, try in sudo mode
	if [ $? != 0 ] ; then
		lb_display_debug --log "...Failed! Trying in sudo..."
		sudo mount "/dev/disk/by-uuid/$backup_disk_uuid" "$backup_disk_mountpoint"

		if [ $? != 0 ] ; then
			lb_display --log "...Failed! Delete mountpoint..."

			# delete mount point
			rmdir "$backup_disk_mountpoint" &> /dev/null
			# if failed, try in sudo mode
			if [ $? != 0 ] ; then
				lb_display_debug --log "...Failed! Trying in sudo..."
				sudo rmdir "$backup_disk_mountpoint" &> /dev/null
				if [ $? != 0 ] ; then
					lb_display --log "...Failed!"
					# failed to remove mount directory
					return 6
				fi
			fi

			# mount failed
			return 1
		fi
	fi

	return 0
}


# Unmount destination
# Usage: unmount_destination
# Exit codes:
#   0: OK
#   1: cannot get destination mountpoint
#   2: umount error
#   3: cannot delete mountpoint
unmount_destination() {

	lb_display --log "Unmount destination..."

	# get mount point
	destination_mountpoint=$(lb_df_mountpoint "$destination")
	if [ $? != 0 ] ; then
		lb_display_error "Cannot get mountpoint of $destination"
		return 1
	fi

	# unmount
	umount "$destination_mountpoint" &> /dev/null

	# if failed, try in sudo mode
	if [ $? != 0 ] ; then
		lb_display_debug --log "...Failed! Try with sudo..."
		sudo umount "$destination_mountpoint" &> /dev/null

		if [ $? != 0 ] ; then
			lb_display --log "...Failed!"
			return 2
		fi
	fi

	lb_display_debug --log "Delete mount point..."
	rmdir "$destination_mountpoint" &> /dev/null

	# if failed, try in sudo mode
	if [ $? != 0 ] ; then
		lb_display_debug --log "...Failed! Trying in sudo..."
		sudo rmdir "$destination_mountpoint" &> /dev/null

		if [ $? != 0 ] ; then
			lb_display --log "...Failed!"
			return 3
		fi
	fi

	return 0
}


# Get path of a file backup
# Usage: get_backup_path PATH
# Return: backup path (e.g. /home/user -> /files/home/user)
# Exit codes:
#   0: OK
#   1: cannot get original path (not absolute and parent directory does not exists)
get_backup_path() {

	# get file
	gbp_file=$*

	# if absolute path (first character is a /)
	if [ "${gbp_file:0:1}" == "/" ] ; then
		# return file path
		echo "/files$gbp_file"
		return 0
	fi

	gbp_protocol=$(get_protocol "$gbp_file")

	# if not absolute path, check protocols
	case $gbp_protocol in
		ssh|t2b)
			# transform ssh://user@hostname/path/to/file -> /ssh/hostname/path/to/file

			# get ssh user@host
			ssh_host=$(echo "$src" | awk -F '/' '{print $3}')
			ssh_hostname=$(echo "$ssh_host" | cut -d@ -f2)

			# get ssh path
			ssh_prefix="$gbp_protocol://$ssh_host"
			ssh_path=${src#$ssh_prefix}

			# return complete path
			echo "/$gbp_protocol/$ssh_hostname/$ssh_path"
			return 0
			;;
	esac

	# if file or directory

	# if not exists (file moved or deleted), try to get parent directory path
	if [ -e "$gbp_file" ] ; then
		echo -n "/files/$(lb_abspath "$gbp_file")"

		# if it is a directory, add '/' at the end of the path
		if [ -d "$gbp_file" ] ; then
			echo /
		fi
	else
		if [ -d "$(dirname "$gbp_file")" ] ; then
			echo "/files/$(lb_abspath "$gbp_file")"
		else
			# if not exists, I cannot guess original path
			lb_error "File does not exist."
			lb_error "If you want to restore a deleted file, please specify an absolute path."
			return 1
		fi
	fi

	return 0
}


# Get all backup dates
# Usage: get_backups
# Return: dates list (format YYYY-MM-DD-HHMMSS)
get_backups() {
	ls "$backup_destination" 2> /dev/null | grep -E "^[1-9][0-9]{3}-[0-1][0-9]-[0-3][0-9]-[0-2][0-9][0-5][0-9][0-5][0-9]$"
}


# Delete a backup
# Usage: delete_backup DATE_REFERENCE
# Exit codes:
#   0: delete OK
#   1: usage error
#   2: rm error
delete_backup() {

	if [ -z "$1" ] ; then
		return 1
	fi

	lb_display_debug --log "Removing $backup_destination/$1..."

	# delete backup path
	rm -rf "$backup_destination/$1" 2> "$logfile"

	if [ $? != 0 ] ; then
		lb_display_debug --log "... Failed!"
		return 2
	fi

	# delete log file
	lb_display_debug --log "Removing log file time2backup_$1.log..."
	rm -f "$logs_directory/time2backup_$1.log" 2> "$logfile"

	# don't care of rm log errors
	return 0
}


# Clean old backups if limit is reached or if space is not available
# Usage: rotate_backups NB_TO_KEEP
# Exit codes:
#   0: rotate OK
#   1: usage error
#   2: rm error
rotate_backups() {

	if ! lb_is_integer $1 ; then
		lb_display_error "rotate_backups: $1 is not a number"
		return 1
	fi

	# if unlimited, do not rotate
	if [ $1 -lt 0 ] ; then
		return 0
	fi

	# always keep nb + 1 (do not delete current backup)
	rb_keep=$(($1 + 1))

	# get backups
	rb_backups=($(get_backups))
	rb_nb=${#rb_backups[@]}

	# if limit not reached, do nothing
	if [ $rb_nb -le $rb_keep ] ; then
		return 0
	fi

	lb_display --log "Cleaning old backups..."
	lb_display_debug --log "Clean to keep $rb_keep/$rb_nb"

	rb_clean=(${rb_backups[@]:0:$(($rb_nb - $rb_keep))})

	# remove backups from older to newer
	for ((rb_i=0; rb_i<${#rb_clean[@]}; rb_i++)) ; do
		if ! delete_backup ${rb_clean[$rb_i]} ; then
			lb_display_error "$tr_error_clean_backups"
		fi
	done

	lb_display --log "" # line jump

	# don't care of other errors
	return 0
}


# Print report of duration from start of script to now
# Usage: report_duration
# Return: complete report with elapsed time in HH:MM:SS
report_duration() {

	# calculate
	duration=$(($(date +%s) - $current_timestamp))

	# print report
	echo "$tr_report_duration $(($duration/3600)):$(printf "%02d" $(($duration/60%60))):$(printf "%02d" $(($duration%60)))"
}


# Enable/disable cron jobs
# Usage: crontab_config enable|disable
# Exit codes:
#   0: OK
#   1: usage error
#   2: cannot access to crontab
#   3: cannot install new crontab
#   4: cannot write into the temporary crontab file
crontab_config() {

	local crontab_enable=false

	if [ $# == 0 ] ; then
		return 1
	fi

	if [ "$1" == enable ] ; then
		crontab_enable=true
	fi

	# get crontab
	tmpcrontab="$config_directory/crontmp"

	# prepare backup task
	crontask="* * * * *	\"$current_script\" "

	if $custom_config ; then
		crontask+="-c \"$config_directory\" "
	fi

	crontask+="backup --recurrent"

	# check if crontab exists
	crontab -u $user -l > "$tmpcrontab" 2>&1
	if [ $? != 0 ] ; then
		# special case for error when no crontab
		grep "no crontab for " "$tmpcrontab" > /dev/null
		if [ $? == 0 ] ; then
			# disable mode: nothing to do
			if ! $crontab_enable ; then
				# delete temporary crontab and exit
				rm -f "$tmpcrontab" &> /dev/null
				return 0
			fi

			# reset crontab
			echo > "$tmpcrontab"

			# if error, delete temporary crontab and exit
			if [ $? != 0 ] ; then
				rm -f "$tmpcrontab" &> /dev/null
				return 2
			fi
		else
			# cannot access to user crontab

			# inform user to add cron job manually
			if $crontab_enable ; then
				lb_display --log "Failed! \nPlease edit crontab manually and add the following line:"
				lb_display --log "$crontask"
			fi

			# delete temporary crontab and exit
			rm -f "$tmpcrontab" &> /dev/null
			return 2
		fi
	fi

	# test if line exists
	grep "$crontask" "$tmpcrontab" > /dev/null

	# cron task already exists
	if [ $? == 0 ] ; then
		# delete if option disabled
		if ! $crontab_enable ; then
			# avoid bugs in sed commands
			crontask=$(echo "$crontask" | sed 's/\//\\\//g')

			# delete line(s)
			sed -i~ "/^\# time2backup recurrent backups/d ; /$crontask/d" "$tmpcrontab"
			if [ $? != 0 ] ; then
				res_install=4
			fi

			rm -f "$tmpcrontab~"
		fi

	else
		# cron task does not exists
		if $crontab_enable ; then
			# append command to crontab
			echo -e "\n# time2backup recurrent backups\n$crontask" >> "$tmpcrontab"
		fi
	fi

	# install new crontab
	crontab -u $user "$tmpcrontab"
	if [ $? != 0 ] ; then
		res_install=3
	fi

	# delete temporary crontab
	rm -f "$tmpcrontab" &> /dev/null

	return $res_install
}


# Install configuration (recurrent tasks, ...)
# Usage: apply_config
# Exit codes:
#   0: OK
#   other: failed (exit code forwarded from crontab_config)
apply_config() {

	# if disabled, do not continue
	if ! $enable_recurrent ; then
		return 0
	fi

	if $recurrent ; then
		echo "Enable recurrent backups..."
		crontab_config enable
	else
		echo "Disable recurrent backups..."
		crontab_config disable
	fi

	return $?
}


# Test if destination is reachable and mount it if needed
# Usage: prepare_destination
# Exit codes:
#   0: destination is ready
#   1: destination not reachable
#   2: destination not writable
prepare_destination() {

	destok=false

	lb_display_debug "Testing destination on: $destination..."

	case $(get_protocol "$destination") in
		ssh|t2b)
			destination_ssh=true
			# for now, we do not test if there is enough space on distant device
			test_destination=false

			# define the default logs path to the local config directory
			if [ -z "$logs_directory" ] ; then
				logs_directory="$config_directory/logs"
			fi

			# quit ok
			return 0
			;;
	esac

	# test backup destination directory
	if [ -d "$destination" ] ; then
		lb_display_debug "Destination mounted."
		mounted=true
		destok=true
	else
		lb_display_debug "Destination NOT mounted."

		# if backup disk mountpoint is defined,
		if [ -n "$backup_disk_mountpoint" ] ; then
			# and if automount set,
			if $mount ; then
				# try to mount disk
				if mount_destination ; then
					destok=true
				fi
			fi
		fi
	fi

	# error message if destination not ready
	if ! $destok ; then
		lb_display --log "Backup destination is not reachable.\nPlease verify if your media is plugged in and try again."
		return 1
	fi

	# auto unmount: unmount if it was not mounted
	if $unmount_auto ; then
		if ! $mounted ; then
			unmount=true
		fi
	fi

	# create destination if not exists
	mkdir -p "$backup_destination" &> /dev/null
	if [ $? != 0 ] ; then
		# if mkdir failed, exit
		if $recurrent_backup ; then
			# don't popup in recurrent mode
			lb_display_error "$tr_cannot_create_destination\n$tr_verify_access_rights"
		else
			lbg_display_error "$tr_cannot_create_destination\n$tr_verify_access_rights"
		fi
		return 2
	fi

	# test if destination is writable
	# must keep this test because if directory exists, the previous mkdir -p command returns no error
	if ! [ -w "$backup_destination" ] ; then
		if $recurrent_backup ; then
			# don't popup in recurrent mode
			lb_display_error "$tr_write_error_destination\n$tr_verify_access_rights"
		else
			lbg_display_error "$tr_write_error_destination\n$tr_verify_access_rights"
		fi
		return 2
	fi

	return 0
}


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

	# create log file
	if ! lb_set_logfile "$*" ; then
		lb_display_error "Cannot create log file $*. Please verify your access rights."
		return 2
	fi
}


# Test backup command
# rsync simulation and get total size of the files to transfer
# Usage: test_backup
# Return: size of the backup (in bytes)
# Exit codes:
#   0: OK
#   1: rsync test command failed
test_backup() {

	lb_display --log "Testing backup..."

	# prepare rsync in test mode
	test_cmd=(rsync --dry-run --stats)

	# append rsync options without the first argument (rsync)
	test_cmd+=("${cmd[@]:1}")

	# rsync test
	# option dry-run makes a simulation for rsync
	# then we get the last line with the total amount of bytes to be copied
	# which is in format 999,999,999 so then we delete the commas
	lb_display_debug --log "Testing rsync in dry-run mode: ${test_cmd[@]}..."

	total_size=$("${test_cmd[@]}" 2> >(tee -a "$logfile" >&2) | grep "Total transferred file size" | awk '{ print $5 }' | sed 's/,//g')

	# if rsync command not ok, error
	if ! lb_is_integer $total_size ; then
		lb_display_debug --log "rsync test failed."
		return 1
	fi

	# add the space to be taken by the folders!
	# could be important if you have many folders; not necessary in mirror mode
	if ! $mirror_mode ; then

		# get the source path from rsync command (array size - 2)
		src_folder=${test_cmd[${#test_cmd[@]}-2]}

		# get size of folders
		folders_size=$(folders_size "$src_folder")

		# add size of folders
		if lb_is_integer $folders_size ; then
			total_size=$(($total_size + $folders_size))
		fi
	fi

	# add a security margin of 1MB for logs and future backups
	total_size=$(($total_size + 1000000))

	lb_display_debug --log "Backup total size (in bytes): $total_size"

	return 0
}


# Test free space on disk to run backups
# Usage: test_free_space
# Exit codes:
#   0: ok
#   1: not OK
test_free_space() {

	# get all backups list
	all_backups=($(get_backups))
	nb_backups=${#all_backups[@]}

	# test free space until it's ready
	for ((i=0; i<=$nb_backups; i++)) ; do

		# if space ok, quit loop to continue backup
		if test_space_available $total_size "$destination" ; then
			return 0
		fi

		# if no clean old backups option in config, continue to be stopped after
		if ! $clean_old_backups ; then
			return 1
		fi

		# display clean notification
		# (just display the first notification, not for every clean)
		if [ $i == 0 ] ; then
			lb_display --log "Not enough space on device. Clean old backups to free space..."

			if $notifications ; then
				lbg_notify "$tr_notify_cleaning_space"
			fi
		fi

		# recheck all backups list (more safety)
		all_backups=($(get_backups))

		# do not remove the last backup, nor the current
		if [ ${#all_backups[@]} -le 2 ] ; then
			return 1
		fi

		# always keep the current backup and respect the clean limit
		# (continue to be stopped after)
		if [ $clean_keep -gt 0 ] ; then
			if [ ${#all_backups[@]} -le $clean_keep ] ; then
				return 1
			fi
		fi

		# do not delete the last clean backup that will be used for hard links
		if [ "${all_backups[0]}" == "$lastcleanbackup" ] ; then
			continue
		fi

		# clean oldest backup to free space
		delete_backup ${all_backups[0]}
	done

	# if all finished, error
	return 1
}


# Delete empty directories recursively
# Usage: clean_empty_directories PATH
# Exit codes:
#   0: cleaned
#   1: usage error or path is not a directory
clean_empty_directories() {

	# get directory path
	d=$*

	# delete empty directories recursively
	while true ; do

		# if is not a directory, this is an usage error
		if ! [ -d "$d" ] ; then
			return 1
		fi

		# security check: do not delete destination path
		if [ "$(dirname "$d")" == "$(dirname "$destination")" ] ; then
			return 0
		fi

		# if directory is not empty, quit loop
		if ! lb_dir_is_empty "$d" ; then
			return 0
		fi

		lb_display_debug --log "Deleting empty directory: $d"

		# delete directory
		rmdir "$d" &> /dev/null
		if [ $? != 0 ] ; then
			# if command failed, quit
			return 0
		fi

		# go to parent directory and continue loop
		d=$(dirname "$d")
	done
}


# Edit configuration
# Usage: edit_config [OPTIONS] CONFIG_FILE
# Options:
#   -e, --editor COMMAND  set editor
#   --set "param=value"   set a config parameter in headless mode (no editor)
# Exit codes:
#   0: OK
#   1: usage error
#   3: failed to open/save configuration
#   4: no editor found to open configuration file
edit_config() {

	# default values
	editors=(nano vim vi)
	custom_editor=false
	set_config=""

	# get options
	while [ -n "$1" ] ; do
		case $1 in
			-e|--editor)
				if [ -z "$2" ] ; then
					return 1
				fi
				editors=("$2")
				custom_editor=true
				shift
				;;
			--set)
				if [ -z "$2" ] ; then
					return 1
				fi
				set_config=$2
				shift
				;;
			*)
				break
				;;
		esac
		shift # load next argument
	done

	# test config file
	if lb_test_arguments -eq 0 $* ; then
		return 1
	fi

	edit_file=$*

	# test file
	if [ -e "$edit_file" ] ; then
		# if exists but is not a file, return error
		if ! [ -f "$edit_file" ] ; then
			return 1
		fi
	else
		# create empty file if it does not exists (should be includes.conf)
		echo -e "\n" > "$edit_file"
	fi

	# headless mode
	if [ -n "$set_config" ] ; then

		# get parameter + value
		conf_param=$(echo $set_config | cut -d= -f1 | tr -d '[[:space:]]')
		conf_value=$(echo "$set_config" | sed 's/\//\\\//g')

		# get config line
		config_line=$(cat "$edit_file" | grep -n "^[# ]*$conf_param[[:space:]]*=" | cut -d: -f1)

		# if found, change line
		if [ -n "$config_line" ] ; then
			sed -i~ "${config_line}s/.*/$conf_value/" "$edit_file"
		else
			# if not found, append to file
			echo "$set_config" >> "$edit_file"
		fi

	else
		# config editor mode
		all_editors=()

		# if no custom editor,
		if ! $custom_editor ; then
			# open file with graphical editor
			if ! $console_mode ; then
				# check if we are using something else than a console
				if [ "$(lbg_get_gui)" != console ] ; then
					if [ "$lb_current_os" == macOS ] ; then
						all_editors+=(open)
					else
						all_editors+=(xdg-open)
					fi
				fi
			fi
		fi

		# add console editors or chosen one
		all_editors+=("${editors[@]}")

		# select a console editor
		for e in ${all_editors[@]} ; do
			# test if editor exists
			if lb_command_exists "$e" ; then
				editor=$e
				break
			fi
		done

		# run text editor and wait for it to close
		if [ -n "$editor" ] ; then
			"$editor" "$edit_file" 2> /dev/null
			wait $!
		else
			if $custom_editor ; then
				lb_error "Editor '$editors' was not found on this system."
			else
				lb_error "No editor was found on this system."
				lb_error "Please edit $edit_file manually."
			fi

			return 4
		fi
	fi

	if [ $? != 0 ] ; then
		lb_error "Failed to open/save configuration."
		lb_error "Please edit $edit_file manually."
		return 3
	fi

	return 0
}


# Return date of the current lock (if exists)
# Usage: current_lock
# Return: date of lock, empty if no lock
# Exit code:
#   0: lock exists
#   1: lock does not exists
#   2: unknown error
current_lock() {

	# get lock file
	blf=$(ls "$backup_destination/.lock_"* 2> /dev/null)
	if [ $? != 0 ] ; then
		return 1
	fi

	# print date of lock
	basename "$blf" | sed 's/^.lock_//'
	if [ $? != 0 ] ; then
		return 2
	fi

	return 0
}


# Delete backup lock
# Usage: remove_lock
# Exit codes:
#   0: OK
#   1: could not delete lock
release_lock() {

	lb_display_debug "Deleting lock..."

	rm -f "$backup_lock" &> /dev/null
	if [ $? != 0 ] ; then
		lbg_display_critical --log "$tr_error_unlock"
		return 1
	fi

	return 0
}


# Prepare rsync command and arguments in the $rsync_cmd variable
# Usage: prepare_rsync backup|restore
prepare_rsync() {

	# basic command
	rsync_cmd=("$rsync_path" -aHv --progress)

	# get config for inclusions
	if [ -f "$config_includes" ] ; then
		rsync_cmd+=(--include-from "$config_includes")
	fi

	# get config for exclusions
	if [ -f "$config_excludes" ] ; then
		rsync_cmd+=(--exclude-from "$config_excludes")
	fi

	# add user defined options
	if [ ${#rsync_options[@]} -gt 0 ] ; then
		rsync_cmd+=("${rsync_options[@]}")
	fi

	# command-specific options
	if [ "$1" == backup ] ; then
		# delete newer files
		rsync_cmd+=(--delete)

		# add max size if specified
		if [ -n "$max_size" ] ; then
			rsync_cmd+=(--max-size "$max_size")
		fi
	fi
}


# Test if time2backup is installed
# Usage: is_installed
# Exit codes:
#   0: installed
#   1: not installed
is_installed() {
	[ -f "$script_directory/config/.install" ]
}


####################
#  EXIT FUNCTIONS  #
####################

# Clean things before exit
# Usage: clean_exit [OPTIONS] [EXIT_CODE]
# Options:
#   --no-unmount   Do not unmount
#   --no-email     Do not send email report
#   --no-rmlog     Do not delete logfile
#   --no-shutdown  Do not halt PC
clean_exit() {

	delete_logs=true

	# get options
	while [ -n "$1" ] ; do
		case $1 in
			--no-unmount)
				if ! $force_unmount ; then
					unmount=false
				fi
				;;
			--no-email)
				email_report=none
				;;
			--no-rmlog)
				delete_logs=false
				;;
			--no-shutdown)
				if ! $force_shutdown ; then
					shutdown=false
				fi
				;;
			*)
				break
				;;
		esac
		shift # load next argument
	done

	# set exit code if specified
	if [ -n "$1" ] ; then
		lb_exitcode=$1
	fi

	# prevent from deleting logs
	if $delete_logs ; then
		if [ "$keep_logs" == "always" ] ; then
			delete_logs=false
		elif [ "$keep_logs" == "on_error" ] && [ $lb_exitcode != 0 ] ; then
			delete_logs=false
		fi
	fi

	lb_display_debug --log "Clean exit."

	# cleanup backup directory if empty
	clean_empty_directories "$dest"
	# if previous failed (not empty, try to clean last backup directory)
	clean_empty_directories "$finaldest"

	# delete backup lock
	release_lock

	# clear all traps to avoid infinite loop if following commands takes some time
	trap - 1 2 3 15
	trap

	# unmount destination
	if $unmount ; then
		if ! unmount_destination ; then
			lbg_display_error --log "$tr_error_unmount"

			if [ $lb_exitcode == 0 ] ; then
				lb_exitcode=18
			fi
		fi
	fi

	# send email report
	if [ "$email_report" == "on_error" ] || [ "$email_report" == "always" ] ; then

		# if email recipient is set,
		if [ -n "$email_recipient" ] ; then

			# if report is set or there was an error
			if [ "$email_report" == "always" ] || [ $lb_exitcode != 0 ] ; then

				# email options
				email_opts=()
				if [ -n "$email_sender" ] ; then
					email_opts+=(--sender "$email_sender")
				fi

				# prepare email content
				email_subject="$email_subject_prefix"

				if [ -n "$email_subject_prefix" ] ; then
					email_subject+=" "
				fi

				email_subject+="$tr_email_report_subject "
				email_content="$tr_email_report_greetings\n\n"

				if [ $lb_exitcode == 0 ] ; then
					email_subject+=$(printf "$tr_email_report_subject_success" $(hostname))
					email_content+=$(printf "$tr_email_report_success" $(hostname))
				else
					email_subject+=$(printf "$tr_email_report_subject_failed" $(hostname))
					email_content+=$(printf "$tr_email_report_failed" $(hostname) $lb_exitcode)
				fi

				email_content+="\n\n$(printf "$tr_email_report_details" "$current_date")"
				email_content+="\n$(report_duration)\n\n"

				# error report
				if [ $lb_exitcode != 0 ] ; then
					email_content+="$report_details\n\n"
				fi

				# if logs are kept,
				if ! $delete_logs ; then
					email_content+="$tr_email_report_see_logs\n\n"
				fi

				email_content+="$tr_email_report_regards\ntime2backup"

				# send email without managing errors and without blocking script
				lb_email "${email_opts[@]}" --subject "$email_subject" "$email_recipient" "$email_content" &
			fi
		else
			# email not sent
			lb_display_error --log "Email recipient not set, do not send email report."
		fi
	fi

	# delete log file
	if $delete_logs ; then

		lb_display_debug --log "Deleting log file..."

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

	# if shutdown after backup, execute it
	if $shutdown ; then
		if ! haltpc ; then
			if [ $lb_exitcode == 0 ] ; then
				lb_exitcode=19
			fi
		fi
	fi

	if $debug_mode ; then
		echo
		lb_display_debug "Exited with code: $lb_exitcode"
	fi

	lb_exit
}


# Exit when cancel signal is caught
# Usage: cancel_exit
cancel_exit() {

	lb_display --log
	lb_display_info --log "Cancelled. Exiting..."

	# display notification
	if $notifications ; then
		if [ "$command" == backup ] ; then
			lbg_notify "$(printf "$tr_backup_cancelled_at" $(date +%H:%M:%S))\n$(report_duration)"
		else
			lbg_notify "$tr_restore_cancelled"
		fi
	fi

	# backup mode
	if [ "$command" == backup ] ; then
		# exit with cancel code without shutdown
		clean_exit --no-shutdown 17
	else
		# restore mode: just exit
		exit 11
	fi
}


# Halt PC in 10 seconds
# Usage: haltpc
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
	for ((i=10; i>=0; i--)) ; do
		echo -n "$i "
		sleep 1
	done

	# just do a line return
	echo

	# run shutdown command
	"${shutdown_cmd[@]}"
	if [ $? != 0 ] ; then
		lb_display_error "Error with shutdown command. PC is still up."
		return 2
	fi
}


#############
#  WIZARDS  #
#############

# Choose an operation to execute (time2backup commands)
# Usage: choose_operation
choose_operation() {

	# display choice
	if ! lbg_choose_option -d 1 -l "$tr_choose_an_operation" "$tr_backup_files" "$tr_restore_file" "$tr_configure_time2backup" ; then
		exit
	fi

	# run command
	case $lbg_choose_option in
		1)
			command=backup
			;;
		2)
			command=restore
			;;
		3)
			command=config
			;;
		*)
			# bad choice
			print_help global
			exit 1
			;;
	esac
}


# Configuration wizard
# Usage: config_wizard
# Exit codes:
#   0: OK
#   1: no destination chosen
#   3: there are errors in configuration file
config_wizard() {

	local recurrent_enabled=false

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

		lb_display_debug "Chosen destination: $lbg_choose_directory"

		# get absolute path of the chosen directory
		chosen_directory=$(lb_realpath "$lbg_choose_directory")

		# update destination config
		if [ "$chosen_directory" != "$destination" ] ; then
			edit_config --set "destination = \"$chosen_directory\"" "$config_file"
			if [ $? == 0 ] ; then
				# reset destination variable
				destination=$chosen_directory
			else
				lbg_display_error "$tr_error_set_destination\n$tr_edit_config_manually"
			fi
		fi

		# set mountpoint in config file
		mountpoint=$(lb_df_mountpoint "$chosen_directory")
		if [ -n "$mountpoint" ] ; then
			lb_display_debug "Mount point: $mountpoint"

			# update disk mountpoint config
			if [ "$chosen_directory" != "$backup_disk_mountpoint" ] ; then

				edit_config --set "backup_disk_mountpoint = \"$mountpoint\"" "$config_file"

				res_edit=$?
				if [ $res_edit != 0 ] ; then
					lb_display_debug "Error in setting config parameter backup_disk_mountpoint (result code: $res_edit)"
				fi
			fi
		else
			lb_display_debug "Could not find mount point of destination."
		fi

		# set mountpoint in config file
		disk_uuid=$(lb_df_uuid "$chosen_directory")
		if [ -n "$disk_uuid" ] ; then
			lb_display_debug "Disk UUID: $disk_uuid"

			# update disk UUID config
			if [ "$chosen_directory" != "$backup_disk_uuid" ] ; then
				edit_config --set "backup_disk_uuid = \"$disk_uuid\"" "$config_file"

				res_edit=$?
				if [ $res_edit != 0 ] ; then
					lb_display_debug "Error in setting config parameter backup_disk_uuid (result code: $res_edit)"
				fi
			fi
		else
			lb_display_debug "Could not find disk UUID of destination."
		fi

		# hard links support
		if $hard_links ; then
			# if hard links not supported by destination,
			if ! test_hardlinks "$destination" ; then

				# if forced hard links in config
				if $force_hard_links ; then
					# ask user to keep or not the force mode
					if ! lbg_yesno "$tr_force_hard_links_confirm\n$tr_not_sure_say_no" ; then

						# set config
						edit_config --set "force_hard_links = false" "$config_file"

						res_edit=$?
						if [ $res_edit != 0 ] ; then
							lb_display_debug "Error in setting config parameter force_hard_links (result code: $res_edit)"
						fi
					fi
				fi
			fi
		fi
	else
		lb_display_debug "Error or cancel when choosing destination directory (result code: $?)."

		# if no destination set, return error
		if [ -z "$destination" ] ; then
			return 1
		else
			return 0
		fi
	fi

	# edit sources to backup
	if lbg_yesno "$tr_ask_edit_sources\n$tr_default_source" ; then

		edit_config "$config_sources"

		# manage result
		res_edit=$?
		if [ $res_edit == 0 ] ; then
			# display window to wait until user has finished
			if ! $console_mode ; then
				lbg_display_info "$tr_finished_edit"
			fi
		else
			lb_error "Error in editing sources config file (result code: $res_edit)"
		fi
	fi

	# activate recurrent backups
	if $enable_recurrent ; then
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
						edit_config --set "frequency = hourly" "$config_file"
						;;
					2)
						edit_config --set "frequency = daily" "$config_file"
						;;
					3)
						edit_config --set "frequency = weekly" "$config_file"
						;;
					4)
						edit_config --set "frequency = monthly" "$config_file"
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
								frequency=30d
								;;
							"")
								# default is 24h
								frequency=24h
								;;
						esac

						# display dialog to enter custom frequency
						if lbg_input_text -d "$frequency" "$tr_enter_frequency $tr_frequency_examples" ; then
							echo $lbg_input_text | grep -q -E "^[1-9][0-9]*(m|h|d)"
							if [ $? == 0 ] ; then
								edit_config --set "frequency = $lbg_input_text" "$config_file"
							else
								lbg_display_error "$tr_frequency_syntax_error\n$tr_please_retry"
							fi
						fi
						;;
				esac

				res_edit=$?
				if [ $res_edit != 0 ] ; then
					lb_display_debug "Error in setting config parameter frequency (result code: $res_edit)"
				fi
			else
				lb_display_debug "Error or cancel when choosing recurrence frequency (result code: $?)."
			fi
		fi
	fi

	# ask to edit config
	if lbg_yesno "$tr_ask_edit_config" ; then

		edit_config "$config_file"
		if [ $? == 0 ] ; then
			# display window to wait until user has finished
			if ! $console_mode ; then
				lbg_display_info "$tr_finished_edit"
			fi
		fi
	fi

	# enable/disable recurrence in config
	edit_config --set "recurrent = $recurrent_enabled" "$config_file"
	res_edit=$?
	if [ $res_edit != 0 ] ; then
		lb_display_debug "Error in setting config parameter recurrent (result code: $res_edit)"
	fi

	# reload config
	if ! load_config || ! test_config ; then
		lbg_display_error "$tr_errors_in_config"
		return 3
	fi

	# apply configuration
	if ! apply_config ; then
		lbg_display_warning "$tr_cannot_install_cronjobs"
	fi

	# ask for the first backup
	if lbg_yesno -y "$tr_ask_backup_now" ; then
		t2b_backup
		return $?
	fi

	# no backup: inform user time2backup is ready
	lbg_display_info "$tr_info_time2backup_ready"

	return 0
}


# First run wizard
# Usage: first_run
# Exit codes: forwarded from config_wizard
first_run() {

	install_result=0

	# ask to install
	if $ask_to_install ; then
		if ! is_installed ; then
			# confirm install
			if lbg_yesno "$tr_confirm_install_1\n$tr_confirm_install_2" ; then
				# install time2backup (create links)
				t2b_install
				install_result=$?
			fi
		fi
	fi

	# confirm config
	if ! lbg_yesno "$tr_ask_first_config" ; then
		# if not continuing, return install result
		return $install_result
	fi

	# run config wizard
	config_wizard
}
