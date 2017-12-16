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
#      get_backup_fulldate
#      get_backup_history
#      create_config
#      upgrade_config
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
#      open_config
#      current_lock
#      create_lock
#      release_lock
#      prepare_rsync
#      is_installed
#      prepare_remote
#   Backup steps
#      run_before
#      run_after
#   Exit functions
#      clean_exit
#      cancel_exit
#      email_report
#      haltpc
#   Wizards
#      choose_operation
#      config_wizard
#      first_run


######################
#  GLOBAL FUNCTIONS  #
######################

# Get readable backup date
# Usage: get_backup_fulldate YYYY-MM-DD-HHMMSS
# Return: backup datetime (format YYYY-MM-DD HH:MM:SS)
# e.g. 2016-12-31-233059 -> 2016-12-31 23:30:59
# Exit codes:
#   0: OK
#   1: format error
get_backup_fulldate() {

	# test backup format (YYYY-MM-DD-HHMMSS)
	if ! check_backup_date $1 ; then
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
#   -a  get all versions (including same)
#   -l  get only last version
#   -n  get non-empty directories
# Exit codes:
#   0: OK
#   1: usage error
#   2: no backups found
#   3: cannot found backups (no absolute path, deleted parent directory)
get_backup_history() {

	# default options and variables
	local gbh_all_versions=false
	local gbh_last_version=false
	local gbh_nonempty=false

	# get options
	while [ -n "$1" ] ; do
		case $1 in
			-a)
				gbh_all_versions=true
				;;
			-l)
				gbh_last_version=true
				;;
			-n)
				gbh_nonempty=true
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
	local gbh_backups=($(get_backups))
	if [ ${#gbh_backups[@]} == 0 ] ; then
		# no backups found
		return 2
	fi

	# get backup path
	local gbh_backup_path=$(get_backup_path "$*")
	if [ -z "$gbh_backup_path" ] ; then
		return 3
	fi

	# subtility: path/to/symlink_dir/ is not detected as a link, but so does path/to/symlink_dir
	if [ "${gbh_backup_path:${#gbh_backup_path}-1}" == "/" ] ; then
		# return path without the last /
		gbh_backup_path=${gbh_backup_path:0:${#gbh_backup_path}-1}
	fi

	# prepare for loop
	local gbh_last_inode=""
	local gbh_last_symlink_target=""
	declare -i gbh_versions=0

	# try to find backup from latest to oldest
	for ((gbh_i=${#gbh_backups[@]}-1 ; gbh_i>=0 ; gbh_i--)) ; do

		gbh_date=${gbh_backups[$gbh_i]}

		# check if file/directory exists
		gbh_backup_file="$backup_destination/$gbh_date/$gbh_backup_path"

		# if file/directory does not exists, continue
		if ! [ -e "$gbh_backup_file" ] ; then
			continue
		fi

		# check if a backup is currently running
		if [ "$(current_lock)" == "$gbh_date" ] ; then
			# ignore current backup (if running, it could contain errors)
			continue
		fi

		# if get only non empty directories
		if $gbh_nonempty ; then
			if [ -d "$gbh_backup_file" ] ; then
				if lb_dir_is_empty "$gbh_backup_file" ; then
					continue
				fi
			fi
		fi

		# if get only last version, print and exit
		if $gbh_last_version ; then
			echo $gbh_date
			return 0
		fi

		# if get all versions, do not compare files and continue
		if $gbh_all_versions ; then
			echo $gbh_date
			gbh_versions+=1
			continue
		fi

		#  DIRECTORIES

		if [ -d "$gbh_backup_file" ] ; then
			# if it's not a symlink,
			if ! [ -L "$gbh_backup_file" ] ; then
				# TODO: DETECT DIRECTORY CHANGES
				# for now, just add it to list
				echo $gbh_date
				gbh_versions+=1
				continue
			fi
		fi

		#  SYMLINKS

		if [ -L "$gbh_backup_file" ] ; then
			# detect if symlink target has changed
			# TODO: move this part to directory section and test target file inodes
			gbh_symlink_target=$(readlink "$gbh_backup_file")

			if [ "$gbh_symlink_target" != "$gbh_last_symlink_target" ] ; then
				echo $gbh_date
				gbh_versions+=1

				# save target to compare to the next one
				gbh_last_symlink_target=$gbh_symlink_target
			fi

			continue
		fi

		#  REGULAR FILES

		# compare inodes to detect different versions
		if [ "$lb_current_os" == macOS ] ; then
			gbh_inode=$(stat -f %i "$gbh_backup_file")
		else
			gbh_inode=$(stat --format %i "$gbh_backup_file")
		fi

		if [ "$gbh_inode" != "$gbh_last_inode" ] ; then
			echo $gbh_date
			gbh_versions+=1

			# save last inode to compare to next
			gbh_last_inode=$gbh_inode
		fi
	done

	if [ $gbh_versions == 0 ] ; then
		return 2
	fi
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
		# DO NOT transform this file to Windows format!
	fi

	if ! [ -f "$config_sources" ] ; then
		cp -f "$script_directory/config/sources.example.conf" "$config_sources"
		if [ $? == 0 ] ; then
			file_for_windows "$config_sources"
		else
			lb_error "Cannot create sources file."
			return 2
		fi
	fi

	if ! [ -f "$config_file" ] ; then
		cp -f "$script_directory/config/time2backup.example.conf" "$config_file"
		if [ $? == 0 ] ; then
			file_for_windows "$config_file"
		else
			lb_error "Cannot create config file."
			return 3
		fi
	fi

	# if user is different, try to give him ownership on config files
	if [ $user != $lb_current_user ] ; then
		chown -R $user:$user "$config_directory" &> /dev/null
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
	old_config_version=$(grep "time2backup configuration file v" "$config_file" | grep -o "[0-9].[0-9].[0-9]")
	if [ -z "$old_config_version" ] ; then
		lb_display_error "Cannot get config version."
		return 1
	fi

	# if current version, OK
	if [ "$old_config_version" == "$version" ] ; then
		return 0
	fi

	if ! $quiet_mode ; then
		echo
		lb_print "$tr_upgrade_config"
		lb_debug "Upgrading config v$old_config_version -> v$version"
	fi

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

	cp -p "$config_file" "$old_config"
	if [ $? != 0 ] ; then
		lb_display_error "Cannot save old config! Please check your access rights."
		return 2
	fi

	cat "$script_directory/config/time2backup.example.conf" > "$config_file"
	if [ $? != 0 ] ; then
		lb_display_error "$tr_error_upgrade_config"
		return 2
	fi

	# transform Windows file
	file_for_windows "$config_file"

	# read old config
	if ! lb_read_config "$old_config" ; then
		lb_display_error "$tr_error_upgrade_config"
		return 2
	fi

	for ((c=0; c<${#lb_read_config[@]}; c++)) ; do
		config_param=$(echo ${lb_read_config[$c]} | cut -d= -f1 | tr -d '[[:space:]]')
		config_line=$(echo "${lb_read_config[$c]}" | sed 's/\\/\\\\/g; s/\//\\\//g')

		if [ "$lb_current_os" == Windows ] ; then
			config_line+="\r"
		fi

		lb_debug "Upgrade $config_line..."

		sed -i~ "s/^#*$config_param[[:space:]]*=.*/$config_line/" "$config_file"
		if [ $? != 0 ] ; then
			lb_display_error "$tr_error_upgrade_config"
			return 2
		fi
	done

	# delete old config
	rm -f "$old_config" &> /dev/null

	# do not care of errors
	return 0
}


# Load configuration file
# Usage: load_config
# Exit codes:
#   0: OK
#   1: cannot open config
#   2: there are errors in config
load_config() {

	if ! $quiet_mode ; then
		echo -e "\n$tr_loading_config\n"
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
	if [ -n "$force_destination" ] ; then
		destination=$force_destination
	fi

	# test if destination is defined
	if [ -z "$destination" ] ; then
		lb_error "Destination is not set!"
		return 2
	fi

	# convert destination path for Windows systems
	if [ "$lb_current_os" == Windows ] ; then
		destination=$(cygpath "$destination")

		if [ $? != 0 ] ; then
			lb_error "Error in Windows destination path!"
			return 2
		fi
	fi

	# test config values

	# test boolean values
	test_boolean=(destination_subdirectories test_destination resume_cancelled resume_failed clean_old_backups recurrent mount exec_before_block unmount unmount_auto shutdown exec_after_block notifications console_mode network_compression hard_links force_hard_links)
	for v in ${test_boolean[@]} ; do
		if ! lb_is_boolean ${!v} ; then
			lb_error "$v must be a boolean!"
			return 2
		fi
	done

	# test integer values
	test_integer=(keep_limit clean_keep)
	for v in ${test_integer[@]} ; do
		if ! lb_is_integer ${!v} ; then
			lb_error "$v must be an integer!"
			return 2
		fi
	done

	# other specific tests

	if [ $clean_keep -lt 0 ] ; then
		lb_error "clean_keep must be a positive integer!"
		return 2
	fi

	# init some variables

	# set backup destination
	if $destination_subdirectories ; then
		# add subdirectories
		backup_destination="$destination/backups/$lb_current_hostname/"
	else
		backup_destination="$destination/"
	fi

	# if keep limit to 0, we are in a mirror mode
	if [ $keep_limit == 0 ] ; then
		mirror_mode=true
	fi

	# increment clean_keep to 1 to keep the current backup
	clean_keep=$(($clean_keep + 1))

	# set default rsync path if not defined or if custom commands not allowed
	if [ -z "$rsync_path" ] || $disable_custom_commands ; then
		rsync_path=$default_rsync_path
	fi

	# set default shutdown command or if custom commands not allowed
	if [ ${#shutdown_cmd[@]} == 0 ] || $disable_custom_commands ; then
		shutdown_cmd=("${default_shutdown_cmd[@]}")
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
	ls /dev/disk/by-uuid/ 2> /dev/null | grep -q "$backup_disk_uuid"
	if [ $? != 0 ] ; then
		lb_debug --log "Disk not available."
		return 2
	fi

	# create mountpoint
	if ! [ -d "$backup_disk_mountpoint" ] ; then

		lb_display --log "Create disk mountpoint..."
		mkdir -p "$backup_disk_mountpoint"

		# if failed, try in sudo mode
		if [ $? != 0 ] ; then
			lb_debug --log "...Failed! Try with sudo..."
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
		lb_debug --log "...Failed! Trying in sudo..."
		sudo mount "/dev/disk/by-uuid/$backup_disk_uuid" "$backup_disk_mountpoint"

		if [ $? != 0 ] ; then
			lb_display --log "...Failed! Delete mountpoint..."

			# delete mount point
			rmdir "$backup_disk_mountpoint" &> /dev/null
			# if failed, try in sudo mode
			if [ $? != 0 ] ; then
				lb_debug --log "...Failed! Trying in sudo..."
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
		lb_debug --log "...Failed! Try with sudo..."
		sudo umount "$destination_mountpoint" &> /dev/null

		if [ $? != 0 ] ; then
			lb_display --log "...Failed!"
			return 2
		fi
	fi

	lb_debug --log "Delete mount point..."
	rmdir "$destination_mountpoint" &> /dev/null

	# if failed, try in sudo mode
	if [ $? != 0 ] ; then
		lb_debug --log "...Failed! Trying in sudo..."
		sudo rmdir "$destination_mountpoint" &> /dev/null

		if [ $? != 0 ] ; then
			lb_display --log "...Failed!"
			return 3
		fi
	fi
}


# Get path of a file backup
# Usage: get_backup_path PATH
# Return: backup path (e.g. /home/user -> /files/home/user)
# Exit codes:
#   0: OK
#   1: cannot get original path (not absolute and parent directory does not exists)
get_backup_path() {

	local gbp_file=$*

	# if absolute path (first character is a /)
	if [ "${gbp_file:0:1}" == "/" ] ; then
		# return file path
		echo "/files$gbp_file"
		return 0
	fi

	local gbp_protocol=$(get_protocol "$gbp_file")

	# if not absolute path, check protocols
	case $gbp_protocol in
		ssh)
			# transform ssh://user@hostname/path/to/file -> /ssh/hostname/path/to/file

			# get ssh user@host
			ssh_host=$(echo "$gbp_file" | awk -F '/' '{print $3}')
			ssh_hostname=$(echo "$ssh_host" | cut -d@ -f2)

			# get ssh path
			ssh_prefix="$gbp_protocol://$ssh_host"
			ssh_path=${gbp_file#$ssh_prefix}

			# return complete path
			echo "/$gbp_protocol/$ssh_hostname/$ssh_path"
			return 0
			;;
	esac

	# if file or directory (relative path)

	# remove file:// prefix
	if [ "${gbp_file:0:7}" == "file://" ] ; then
		gbp_file=${gbp_file:7}
	fi

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
}


# Get all backup dates
# Usage: get_backups
# Return: dates list (format YYYY-MM-DD-HHMMSS)
get_backups() {
	ls "$backup_destination" 2> /dev/null | grep -E "^$backup_date_format$"
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

	lb_debug --log "Removing $backup_destination/$1..."

	# delete backup path
	rm -rf "$backup_destination/$1" 2> "$logfile"

	if [ $? != 0 ] ; then
		lb_display_error --log "Failed to clean backup $1! Please delete this folder manually."
		return 2
	fi

	# delete log file
	lb_debug --log "Removing log file time2backup_$1.log..."
	rm -f "$logs_directory/time2backup_$1.log" 2> "$logfile"

	# don't care of rm log errors
	return 0
}


# Clean old backups
# Usage: rotate_backups
# Exit codes:
#   0: rotate OK
#   1: rm error
rotate_backups() {

	# if unlimited, do not rotate
	if [ $keep_limit -lt 0 ] ; then
		return 0
	fi

	# always keep nb + 1 (do not delete current backup)
	local rb_keep=$(($keep_limit + 1))

	# get backups & number
	local rb_backups=($(get_backups))
	local rb_nb=${#rb_backups[@]}

	# if limit not reached, do nothing
	if [ $rb_nb -le $rb_keep ] ; then
		return 0
	fi

	lb_display --log "Cleaning old backups..."
	lb_debug --log "Clean to keep $rb_keep backups on $rb_nb"

	if $notifications ; then
		lbg_notify "$tr_notify_rotate_backup"
	fi

	local rb_clean=(${rb_backups[@]:0:$(($rb_nb - $rb_keep))})

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

	local crontab_opts=""
	local result_config=0

	case $1 in
		enable)
			crontab_enable=true
			;;
		disable)
			crontab_enable=false
			;;
		*)
			return 1
			;;
	esac

	# get crontab
	tmpcrontab="$config_directory/crontmp"

	# prepare backup task
	crontask="* * * * *	\"$current_script\" "

	if $custom_config ; then
		crontask+="-c \"$config_directory\" "
	fi

	crontask+="backup --recurrent"

	# if root, use crontab -u option
	# Note: macOS does supports -u option only if current user is root
	if [ "$lb_current_user" == root ] ; then
		crontab_opts="-u $user"
	fi

	# check if crontab exists
	crontab $crontab_opts -l > "$tmpcrontab" 2>&1
	if [ $? != 0 ] ; then
		# special case for error when no crontab
		grep -q "no crontab for " "$tmpcrontab"
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
	grep -q "$crontask" "$tmpcrontab"

	# cron task already exists
	if [ $? == 0 ] ; then
		# delete if option disabled
		if ! $crontab_enable ; then
			# avoid bugs in sed commands
			crontask=$(echo "$crontask" | sed 's/\//\\\//g')

			# delete line(s)
			sed -i~ "/^\# time2backup recurrent backups/d ; /$crontask/d" "$tmpcrontab"
			if [ $? != 0 ] ; then
				result_config=4
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
	crontab $crontab_opts "$tmpcrontab"
	if [ $? != 0 ] ; then
		result_config=3
	fi

	# delete temporary crontab
	rm -f "$tmpcrontab" &> /dev/null

	return $result_config
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
}


# Test if destination is reachable and mount it if needed
# Usage: prepare_destination
# Exit codes:
#   0: destination is ready
#   1: destination not reachable
#   2: destination not writable
prepare_destination() {

	local destok=false

	lb_debug "Testing destination on: $destination..."

	case $(get_protocol "$destination") in
		ssh|t2b)
			remote_destination=true
			# do not test if there is enough space on distant device
			test_destination=false

			# define the default logs path to the local config directory
			if [ -z "$logs_directory" ] ; then
				logs_directory="$config_directory/logs"
			fi

			# quit ok
			return 0
			;;
	esac

	# remove file:// prefix
	if [ "${destination:0:7}" == "file://" ] ; then
		destination=${destination:7}
	fi

	# test backup destination directory
	if [ -d "$destination" ] ; then
		lb_debug "Destination mounted."
		mounted=true
		destok=true
	else
		lb_debug "Destination NOT mounted."

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
			lbg_error "$tr_cannot_create_destination\n$tr_verify_access_rights"
		fi
		return 2
	fi

	# test if destination is writable
	# must keep this test because if directory exists, the previous mkdir -p command returns no error
	if ! [ -w "$backup_destination" ] ; then
		# do not return error if samba share: cannot determine rights in some cases
		if [ "$(lb_df_fstype "$backup_destination")" != smbfs ] ; then
			if $recurrent_backup ; then
				# don't popup in recurrent mode
				lb_display_error "$tr_write_error_destination\n$tr_verify_access_rights"
			else
				lbg_error "$tr_write_error_destination\n$tr_verify_access_rights"
			fi
			return 2
		fi
	fi

	# check if destination supports hard links
	if $hard_links ; then
		if ! $force_hard_links ; then
			if ! test_hardlinks "$destination" ; then
				lb_debug --log "Destination does not support hard links. Continue in trash mode."
				hard_links=false
			fi
		fi
	fi

	# create the info file if not exists (don't care of errors)
	touch "$destination/.time2backup" &> /dev/null
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
	lb_debug --log "Testing rsync in dry-run mode: ${test_cmd[@]}..."

	total_size=$("${test_cmd[@]}" 2> >(tee -a "$logfile" >&2) | grep "Total transferred file size" | awk '{ print $5 }' | sed 's/,//g')

	# if rsync command not ok, error
	if ! lb_is_integer $total_size ; then
		lb_debug --log "rsync test failed."
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

	lb_debug --log "Backup total size (in bytes): $total_size"

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

		lb_debug --log "Deleting empty directory: $d"

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
# Usage: open_config [OPTIONS] CONFIG_FILE
# Options:
#   -e COMMAND  use a custom text editor
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
	while [ -n "$1" ] ; do
		case $1 in
			-e)
				if [ -z "$2" ] ; then
					return 1
				fi
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

	# test arguments
	if [ -z "$1" ] ; then
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
		echo > "$edit_file"
	fi

	# if no custom editor,
	if ! $custom_editor ; then
		# open file with graphical editor
		if ! $console_mode ; then
			# check if we are using something else than a console
			if [ "$(lbg_get_gui)" != console ] ; then
				case $lb_current_os in
					macOS)
						all_editors+=(open)
						;;
					Windows)
						all_editors+=(notepad)
						;;
					*)
						all_editors+=(xdg-open)
						;;
				esac
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
		# Windows: transform to Windows path like c:\...\time2backup.conf
		if [ "$lb_current_os" == Windows ] ; then
			edit_file=$(cygpath -w "$edit_file")
		fi

		# open editor and wait until process ends (does not work with all editors)
		"$editor" "$edit_file" 2> /dev/null
		wait $!
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


# Return date of the current lock (if exists)
# Usage: current_lock [OPTIONS]
# Options:
#   -q  Quiet mode
# Return: date of lock, empty if no lock
# Exit code:
#   0: lock exists
#   1: lock does not exists
current_lock() {

	# do not check lock if remote destination
	if $remote_destination ; then
		return 1
	fi

	# get lock file
	local current_lock_file=$(ls "$backup_destination/.lock_"* 2> /dev/null)

	# if no lock, return 1
	if [ -z "$current_lock_file" ] ; then
		return 1
	fi

	# quiet mode
	if [ "$1" == "-q" ] ; then
		return 0
	fi

	# return date of lock
	basename "$current_lock_file" | sed 's/^.lock_//'
}


# Create lock
# Usage: create_lock
# Exit code:
#   0: lock ok
#   1: unknown error
create_lock() {

	# do not create lock if remote destination
	if $remote_destination ; then
		return 0
	fi

	lb_debug "Create lock..."

	touch "$backup_destination/.lock_$backup_date"
}


# Delete backup lock
# Usage: remove_lock
# Exit codes:
#   0: OK
#   1: could not delete lock
release_lock() {

	lb_debug "Deleting lock..."

	rm -f "$backup_destination/.lock_$backup_date" &> /dev/null
	if [ $? != 0 ] ; then
		lbg_critical --log "$tr_error_unlock"
		return 1
	fi
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


# Prepare the remote destination command
# Usage: prepare_remote
prepare_remote() {

	if $server_sudo ; then
		remote_cmd=(sudo)
	fi

	# extract from url t2b://user@hostname/path/for/backup :
	# 1. destination=user@hostname
	# 2. /path/for/backup

	# get t2b server user@host
	t2bs_host=$(echo "$destination" | awk -F '/' '{print $3}')
	t2bs_hostname=$(echo "$t2bs_host" | cut -d@ -f2)

	# get destination path
	t2bs_prefix="t2b://$t2bs_host"
	t2bs_path=${gbp_file#$ssh_prefix}

	# return complete path
	echo "/$gbp_protocol/$ssh_hostname/$ssh_path"

	# if server path is specified, use it
	if [ -n "$server_path" ] ; then
		remote_cmd+=("$server_path")
	else
		# or suppose it is a the destination of the remote path
		remote_cmd+=("$t2bs_path/time2backup-server/t2b-server.sh")
	fi

	# add remote destination path, date and backup path
	remote_cmd+=("$t2bs_path" $backup_date "$src")

	rsync_cmd+=(--rsync-path "${remote_cmd[@]}")

	# network compression
	if $network_compression ; then
		rsync_cmd+=(-z)
	fi

	if [ -n "$ssh_options" ] ; then
		cmd+=(-e "$ssh_options")
	else
		# if empty, defines ssh
		cmd+=(-e ssh)
	fi
}


# Run before backup
# Usage: run_before
run_before() {
	if [ ${#exec_before[@]} -gt 0 ] ; then

		# if disabled, inform user and exit
		if $disable_custom_commands ; then
			lb_display_error "Custom commands are disabled."
			false # bad command to go into the if $? != 0
		else
			# run command/script
			"${exec_before[@]}"
		fi

		if [ $? != 0 ] ; then
			lb_exitcode=5

			# option exit if error
			if $exec_before_block ; then
				lb_debug --log "Before script exited with error."
				clean_exit
			fi
		fi
	fi
}


# Run after backup
# Usage: run_after
run_after() {
	if [ ${#exec_after[@]} -gt 0 ] ; then

		# if disabled, inform user and exit
		if $disable_custom_commands ; then
			lb_display_error "Custom commands are disabled."
			false # bad command to go into the if $? != 0
		else
			# run command/script
			"${exec_after[@]}"
		fi

		if [ $? != 0 ] ; then
			# if error, do not overwrite rsync exit code
			if [ $lb_exitcode == 0 ] ; then
				lb_exitcode=16
			fi

			# option exit if error
			if $exec_after_block ; then
				lb_debug --log "After script exited with error."
				clean_exit
			fi
		fi
	fi
}


####################
#  EXIT FUNCTIONS  #
####################

# Clean things before exit
# Usage: clean_exit [EXIT_CODE]
clean_exit() {

	# set exit code if specified
	if [ -n "$1" ] ; then
		lb_exitcode=$1
	fi

	lb_debug --log "Clean exit"

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
			lbg_error --log "$tr_error_unmount"

			if [ $lb_exitcode == 0 ] ; then
				lb_exitcode=18
			fi
		fi
	fi

	send_email_report

	# delete log file
	local delete_logs=true

	case $keep_logs in
		always)
			delete_logs=false
			;;
		on_error)
			if [ $lb_exitcode != 0 ] ; then
				delete_logs=false
			fi
			;;
	esac

	if $delete_logs ; then

		rm -f "$logfile" &> /dev/null

		if [ $? != 0 ] ; then
			lb_debug --log "Failed to delete logfile"
		fi

		# delete logs directory if empty
		if lb_dir_is_empty "$logs_directory" ; then
			rmdir "$logs_directory" &> /dev/null

			if [ $? != 0 ] ; then
				lb_debug "Failed to delete logs directory"
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

	lb_debug "Exited with code: $lb_exitcode"

	lb_exit
}


# Exit when cancel signal is caught
# Usage: cancel_exit
cancel_exit() {

	echo
	lb_info --log "Cancelled. Exiting..."

	# display notification and exit
	case $command in
		backup)
			if $notifications ; then
				lbg_notify "$(printf "$tr_backup_cancelled_at" $(date +%H:%M:%S))\n$(report_duration)"
			fi
			clean_exit 17
			;;
		restore)
			if $notifications ; then
				lbg_notify "$tr_restore_cancelled"
			fi
			exit 11
			;;
		*)
			if $notifications ; then
				lbg_notify "Unkown operation cancelled."
			fi
			exit 255
			;;
	esac
}


# Send email report
# Usage: send_email_report
# Exit codes:
#   0: email sent, not enabled or no error
#   1: email recipient not set
#   2: failed to send email
send_email_report() {

	case $email_report in
		always)
			# continue
			;;
		on_error)
			# if there was no error, do not send email
			if [ $lb_exitcode == 0 ] ; then
				return 0
			fi
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
		email_subject+=$(printf "$tr_email_report_subject_success" $lb_current_hostname)
		email_content+=$(printf "$tr_email_report_success" $lb_current_hostname)
	else
		email_subject+=$(printf "$tr_email_report_subject_failed" $lb_current_hostname)
		email_content+=$(printf "$tr_email_report_failed" $lb_current_hostname $lb_exitcode)
	fi

	email_content+="\n\n$(printf "$tr_email_report_details" "$current_date")"
	email_content+="\n$(report_duration)\n\n"

	# error report
	if [ $lb_exitcode != 0 ] ; then
		email_content+="$report_details\n\n"
	fi

	email_content+="$tr_email_report_see_logs\n\n"
	email_content+="$tr_email_report_regards\ntime2backup"

	lb_debug --log "Sending email report..."

	# send email without managing errors and without blocking script
	lb_email "${email_opts[@]}" --subject "$email_subject" "$email_recipient" "$email_content"
	if [ $? != 0 ] ; then
		lb_debug --log "...Failed!"
		return 2
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
		lb_display_error --log "Error with shutdown command. PC is still up."
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

		lb_debug "Chosen destination: $lbg_choose_directory"

		# get the real path of the chosen directory
		chosen_directory=$(lb_realpath "$lbg_choose_directory")

		# if destination changed (or first run)
		if [ "$chosen_directory" != "$destination" ] ; then

			# fix case where user sets an old path and go into /backups/
			if [ -e "$chosen_directory/../.time2backup" ] ; then
				chosen_directory=$(dirname "$chosen_directory")
			fi

			# update destination config
			lb_set_config "$config_file" destination "\"$chosen_directory\""
			if [ $? == 0 ] ; then
				# reset destination variable
				destination=$chosen_directory
			else
				lbg_error "$tr_error_set_destination\n$tr_edit_config_manually"
			fi
		fi

		# set mountpoint in config file
		mountpoint=$(lb_df_mountpoint "$chosen_directory")
		if [ -n "$mountpoint" ] ; then
			lb_debug "Mount point: $mountpoint"

			# update disk mountpoint config
			if [ "$chosen_directory" != "$backup_disk_mountpoint" ] ; then

				lb_set_config "$config_file" backup_disk_mountpoint "\"$mountpoint\""

				res_edit=$?
				if [ $res_edit != 0 ] ; then
					lb_debug "Error in setting config parameter backup_disk_mountpoint (result code: $res_edit)"
				fi
			fi
		else
			lb_debug "Could not find mount point of destination."
		fi

		# set mountpoint in config file
		disk_uuid=$(lb_df_uuid "$chosen_directory")
		if [ -n "$disk_uuid" ] ; then
			lb_debug "Disk UUID: $disk_uuid"

			# update disk UUID config
			if [ "$chosen_directory" != "$backup_disk_uuid" ] ; then
				lb_set_config "$config_file" backup_disk_uuid "\"$disk_uuid\""

				res_edit=$?
				if [ $res_edit != 0 ] ; then
					lb_debug "Error in setting config parameter backup_disk_uuid (result code: $res_edit)"
				fi
			fi
		else
			lb_debug "Could not find disk UUID of destination."
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
						lb_set_config "$config_file" force_hard_links false

						res_edit=$?
						if [ $res_edit != 0 ] ; then
							lb_display_error "Error in setting config parameter force_hard_links (result code: $res_edit)"
						fi
					fi
				fi
			fi
		fi
	else
		lb_debug "Error or cancel when choosing destination directory (result code: $?)."

		# if no destination set, return error
		if [ -z "$destination" ] ; then
			return 1
		else
			return 0
		fi
	fi

	# edit sources to backup
	if lbg_yesno "$tr_ask_edit_sources\n$tr_default_source" ; then

		open_config "$config_sources"

		# manage result
		res_edit=$?
		if [ $res_edit == 0 ] ; then
			if [ "$lb_current_os" != Windows ] ; then
				# display window to wait until user has finished
				if ! $console_mode ; then
					lbg_info "$tr_finished_edit"
				fi
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
								lb_set_config "$config_file" frequency $lbg_input_text
							else
								lbg_error "$tr_frequency_syntax_error\n$tr_please_retry"
							fi
						fi
						;;
				esac

				res_edit=$?
				if [ $res_edit != 0 ] ; then
					lb_debug "Error in setting config parameter frequency (result code: $res_edit)"
				fi
			else
				lb_debug "Error or cancel when choosing recurrence frequency (result code: $?)."
			fi
		fi
	fi

	# ask to edit config
	if lbg_yesno "$tr_ask_edit_config" ; then

		open_config "$config_file"
		if [ $? == 0 ] ; then
			if [ "$lb_current_os" != Windows ] ; then
				# display window to wait until user has finished
				if ! $console_mode ; then
					lbg_info "$tr_finished_edit"
				fi
			fi
		fi
	fi

	# enable/disable recurrence in config
	lb_set_config "$config_file" recurrent $recurrent_enabled
	res_edit=$?
	if [ $res_edit != 0 ] ; then
		lb_debug "Error in setting config parameter recurrent (result code: $res_edit)"
	fi

	# reload config
	if ! load_config ; then
		lbg_error "$tr_errors_in_config"
		return 3
	fi

	# apply configuration
	if ! apply_config ; then
		lbg_warning "$tr_cannot_install_cronjobs"
	fi

	# ask for the first backup
	if lbg_yesno -y "$tr_ask_backup_now" ; then
		t2b_backup
		return $?
	fi

	# no backup: inform user time2backup is ready
	lbg_info "$tr_info_time2backup_ready"

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
