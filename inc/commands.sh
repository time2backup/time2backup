#
# time2backup commands
#
# This file is part of time2backup (https://github.com/pruje/time2backup)
#
# MIT License
# Copyright (c) 2017 Jean Prunneaux
#

###########
#  USAGE  #
###########

# Print help for users in console
# Usage: print_help [COMMAND] (if empty, print global help)
print_help() {
	lb_print "\nUsage: $lb_current_script_name [GLOBAL_OPTIONS] COMMAND [OPTIONS] [ARG...]"
	lb_print "\nGlobal options:"
	lb_print "  -C, --console              execute time2backup in console mode (no dialog windows)"
	lb_print "  -p, --portable             execute time2backup in a portable mode"
	lb_print "                             (no install, use local config files, meant to run from removable devices)"
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
			lb_print "  -u, --unmount    unmount destination after backup (overrides configuration)"
			lb_print "  -s, --shutdown   shutdown after backup (overrides configuration)"
			lb_print "  -r, --recurrent  perform a recurrent backup (used in cron jobs, not available in portable mode)"
			lb_print "  -h, --help       print help"
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
			lb_print "  -g, --general     edit general configuration"
			lb_print "  -s, --sources     edit sources file (sources to backup)"
			lb_print "  -x, --excludes    edit excludes file (patterns to ignore)"
			lb_print "  -i, --includes    edit includes file (patterns to include)"
			lb_print "  -l, --show        show configuration; do not edit"
			lb_print "                    display configuration without comments"
			lb_print "  -t, --test        test configuration; do not edit"
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


#############
#  WIZARDS  #
#############

# Configuration wizard
# Usage: config_wizard
# Exit codes:
#   0: OK
#   1: no destination chosen
config_wizard() {

	# set default destination directory
	if [ -d "$destination" ] ; then
		start_path="$destination"
	else
		start_path="$lb_current_path"
	fi

	# get external disk
	if lbg_choose_directory -t "$tr_choose_backup_destination" "$start_path" ; then

		lb_display_debug "Chosen destination: $lbg_choose_directory"

		# get absolute path of the chosen directory
		chosen_directory="$(lb_realpath "$lbg_choose_directory")"

		# if chosen directory is named backups, get parent directory
		if [ "$(basename "$chosen_directory")" == "backups" ] ; then
			chosen_directory="$(dirname "$chosen_directory")"
		fi

		# update destination config
		if [ "$chosen_directory" != "$destination" ] ; then
			edit_config --set "destination=\"$chosen_directory\"" "$config_file"
			if [ $? == 0 ] ; then
				# reset destination variable
				destination="$chosen_directory"
			else
				lbg_display_error "$tr_error_set_destination\n$tr_edit_config_manually"
			fi
		fi

		# set mountpoint in config file
		mountpoint="$(lb_df_mountpoint "$chosen_directory")"
		if [ -n "$mountpoint" ] ; then
			lb_display_debug "Mount point: $mountpoint"

			# update disk mountpoint config
			if [ "$chosen_directory" != "$backup_disk_mountpoint" ] ; then

				edit_config --set "backup_disk_mountpoint=\"$mountpoint\"" "$config_file"

				res_edit=$?
				if [ $res_edit != 0 ] ; then
					lb_error "Error in setting config parameter backup_disk_mountpoint (result code: $res_edit)"
				fi
			fi
		else
			lb_error "Could not find mount point of destination."
		fi

		# set mountpoint in config file
		disk_uuid="$(lb_df_uuid "$chosen_directory")"
		if [ -n "$disk_uuid" ] ; then
			lb_display_debug "Disk UUID: $disk_uuid"

			# update disk UUID config
			if [ "$chosen_directory" != "$backup_disk_uuid" ] ; then
				edit_config --set "backup_disk_uuid=\"$disk_uuid\"" "$config_file"

				res_edit=$?
				if [ $res_edit != 0 ] ; then
					lb_error "Error in setting config parameter backup_disk_uuid (result code: $res_edit)"
				fi
			fi
		else
			lb_error "Could not find disk UUID of destination."
		fi

		# hard links support
		if $hard_links ; then
			# test hard links support
			if ! test_hardlinks ; then

				# NTFS/exFAT case
				if [ "$(lb_df_fstype "$destination")" == "fuseblk" ] ; then

					fhl="false"

					# ask user disk format
					if lbg_yesno "$tr_ntfs_or_exfat\n$tr_not_sure_say_no" ; then
						fhl="true"
					fi

					# set config
					edit_config --set "force_hard_links=$fhl" "$config_file"

					res_edit=$?
					if [ $res_edit != 0 ] ; then
						lb_error "Error in setting config parameter force_hard_links (result code: $res_edit)"
					fi

				else
					# if forced hard links in older config
					if $force_hard_links ; then
						# ask user to keep or not the force mode
						if ! lbg_yesno "$tr_force_hard_links_confirm\n$tr_not_sure_say_no" ; then

							# set config
							edit_config --set "force_hard_links=false" "$config_file"

							res_edit=$?
							if [ $res_edit != 0 ] ; then
								lb_error "Error in setting config parameter force_hard_links (result code: $res_edit)"
							fi
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
			if ! $consolemode ; then
				lbg_display_info "$tr_finished_edit"
			fi
		else
			lb_error "Error in editing sources config file (result code: $res_edit)"
		fi
	fi

	# activate recurrent backups
	if ! $portable_mode ; then
		if lbg_yesno "$tr_ask_activate_recurrent" ; then

			# default custom frequency
			case "$frequency" in
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

				# enable recurrence in config
				edit_config --set "recurrent=true" "$config_file"
				res_edit=$?
				if [ $res_edit != 0 ] ; then
					lb_error "Error in setting config parameter recurrent (result code: $res_edit)"
				fi

				# set recurrence frequency
				case "$lbg_choose_option" in
					1)
						edit_config --set "frequency=\"hourly\"" "$config_file"
						;;
					2)
						edit_config --set "frequency=\"daily\"" "$config_file"
						;;
					3)
						edit_config --set "frequency=\"weekly\"" "$config_file"
						;;
					4)
						edit_config --set "frequency=\"monthly\"" "$config_file"
						;;
					5)
						# default custom frequency
						case "$frequency" in
							hourly)
								frequency="1h"
								;;
							weekly)
								frequency="7d"
								;;
							monthly)
								frequency="30d"
								;;
							"")
								# default is 24h
								frequency="24h"
								;;
						esac

						# display dialog to enter custom frequency
						if lbg_input_text -d "$frequency" "$tr_enter_frequency $tr_frequency_examples" ; then
							echo $lbg_input_text | grep -q -E "^[1-9][0-9]*(m|h|d)"
							if [ $? == 0 ] ; then
								edit_config --set "frequency=\"$lbg_input_text\"" "$config_file"
							else
								lbg_display_error "$tr_frequency_syntax_error\n$tr_please_retry"
							fi
						fi
						;;
				esac

				res_edit=$?
				if [ $res_edit != 0 ] ; then
					lb_error "Error in setting config parameter frequency (result code: $res_edit)"
				fi
			else
				lb_display_debug "Error or cancel when choosing recurrence frequency (result code: $?)."
			fi
		else
			# disable recurrence in config
			edit_config --set "recurrent=false" "$config_file"
			res_edit=$?
			if [ $res_edit != 0 ] ; then
				lb_error "Error in setting config parameter recurrent (result code: $res_edit)"
			fi
		fi
	fi
}


# First run wizard
# Usage: first_run
first_run() {

	if $portable_mode ; then
		create_appicon -p
	else
		# confirm install
		if ! lbg_yesno "$tr_confirm_install_1\n$tr_confirm_install_2" ; then
			return 0
		fi

		# load configuration; don't care of errors
		load_config &> /dev/null

		# install time2backup (create links)
		t2b_install
	fi

	# config wizard
	config_wizard

	# ask to edit config
	if lbg_yesno "$tr_ask_edit_config" ; then

		edit_config "$config_file"
		if [ $? == 0 ] ; then
			# display window to wait until user has finished
			if ! $consolemode ; then
				lbg_display_info "$tr_finished_edit"
			fi
		fi
	fi

	# recheck config
	if ! install_config ; then
		lbg_display_error "$tr_errors_in_config"
		return 3
	fi

	# ask to first backup
	if lbg_yesno -y "$tr_ask_first_backup" ; then
		t2b_backup
		return $?
	else
		lbg_display_info "$tr_info_time2backup_ready"
	fi

	return 0
}


# Choose an operation to execute (time2backup commands)
# Usage: choose_operation
choose_operation() {

	# display choice
	if ! lbg_choose_option -d 1 -l "$tr_choose_an_operation" "$tr_backup_files" "$tr_restore_file" "$tr_configure_time2backup" ; then
		# cancelled
		return 0
	fi

	# run command
	case $lbg_choose_option in
		1)
			mode="backup"
			t2b_backup
			;;
		2)
			mode="restore"
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

	# return command result
	return $?
}


###################
#  MAIN COMMANDS  #
###################

# Perform backup
# Usage: t2b_backup [OPTIONS] [PATH]
# Options:
#   -u, --unmount   unmount after backup (overrides configuration)
#   -s, --shutdown  shutdown after backup (overrides configuration)
#   -r, --recurrent   perform a recurrent backup
#   -h, --help      print help
# Exit codes:
#   0: backup OK
#   1: usage error
#   3: config error
#   4: no source to backup
#   5: before script failed
#   6: backup device not reachable
#   7: backup destination not writable
#   8: backup is already running
#   9: cannot write logs
#   10: source does not exists
#   11: cannot exclude directory backup from itself
#   12: rsync test error
#   13: not enough space for backup
#   14: critical error (rsync failed)
#   15: warnings in backup
#   16: after script failed
#   17: cancelled
#   18: error while unmount destination backup
#   19: shutdown error
#   20: recurrent backups disabled
#   21: recurrent backups: cannot get/save last backup timestamp
t2b_backup() {

	# default values and options
	recurrent_backup=false
	source_ssh=false
	source_network=false

	# get current date
	current_timestamp=$(date +%s)
	current_date=$(date '+%Y-%m-%d at %H:%M:%S')

	# set backup directory with current date (format: YYYY-MM-DD-HHMMSS)
	backup_date=$(date +%Y-%m-%d-%H%M%S)

	# get options
	while true ; do
		case "$1" in
			-u|--unmount)
				force_unmount=true
				unmount=true
				shift
				;;
			-s|--shutdown)
				force_shutdown=true
				shutdown=true
				shift
				;;
			-r|--recurrent)
				recurrent_backup=true
				shift
				;;
			-h|--help)
				print_help backup
				return 0
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

	# specified source
	if [ $# -gt 0 ] ; then
		sources=("$*")
	fi

	# load and test configuration
	if ! load_config ; then
		return 3
	fi

	lb_display "time2backup\n"

	# if not specified, get sources to backup
	if [ ${#sources[@]} == 0 ] ; then
		get_sources
	fi

	# get number of sources to backup
	nbsrc=${#sources[@]}

	# if no sources to backup, exit
	if [ $nbsrc == 0 ] ; then
		lbg_display_warning "$tr_nothing_to_backup\n$tr_please_configure_sources"
		return 4
	fi

	# get last backup file
	last_backup_file="$config_directory/.lastbackup"

	# if file does not exist, create it
	touch "$last_backup_file"
	if [ $? != 0 ] ; then
		lb_display_error "Cannot create last backup! Verify your right access on config directory."
	fi

	# get last backup timestamp
	last_backup_timestamp=$(cat "$last_backup_file" 2> /dev/null | grep -o -E "^[1-9][0-9]*$")

	# if recurrent, check frequency
	if $recurrent_backup ; then

		# recurrent backups not enabled in configuration
		if ! $recurrent ; then
			lb_display_error "Recurrent backups are disabled. You can enable it in configuration file."
			return 20
		fi

		# portable mode not permitted
		if $portable_mode ; then
			lb_display_error "Cannot run recurrent backups in portable mode!"
			return 20
		fi

		# if cannot get last timestamp, cancel (avoid to backup every minute)
		if ! [ -w "$last_backup_file" ] ; then
			lb_display_error "Cannot get/save the last backup timestamp."
			return 21
		fi

		# compare timestamps
		if [ -n "$last_backup_timestamp" ] ; then
			# convert frequency in seconds
			case "$frequency" in
				hourly)
					seconds_offset=3600
					;;
				""|daily)
					seconds_offset=86400
					;;
				weekly)
					seconds_offset=604800
					;;
				monthly)
					seconds_offset=18144000
					;;
				*)
					# custom
					case "${frequency:${#frequency}-1}" in
						m)
							fqunit=60
							;;
						h)
							fqunit=3600
							;;
						*)
							fqunit=86400
							;;
					esac

					fqnum=$(echo $frequency | grep -o -E "^[0-9]*")

					# set offset
					seconds_offset=$(( $fqnum * $fqunit))
					;;
			esac

			# test if delay is passed
			test_timestamp=$(($current_timestamp - $last_backup_timestamp))

			if [ $test_timestamp -gt 0 ] ; then
				if [ $test_timestamp -le $seconds_offset ] ; then
					lb_display_debug "Last backup was done at $(timestamp2date $last_backup_timestamp), we are now $(timestamp2date $current_timestamp) (backup every $(($seconds_offset / 60)) minutes)"
					lb_display_info "Recurrent backup: no need to backup."

					# exit without email or shutdown or delete log (does not exists)
					return 0
				fi
			else
				lb_display_critical "Last backup is more recent than today. Are you a time traveller?"
			fi
		fi
	fi

	# execute before backup command/script
	if [ ${#exec_before[@]} -gt 0 ] ; then
		# test command/script
		if lb_command_exists "${exec_before[0]}" ; then
			"${exec_before[@]}"
			# if error
			if [ $? != 0 ] ; then
				# if error, do not overwrite rsync exit code
				if [ $lb_exitcode == 0 ] ; then
					lb_exitcode=5
				fi

				# option exit if error
				if $exec_before_block ; then
					lb_display_debug --log "Before script exited with error."
					clean_exit --no-unmount
				fi
			fi
		else
			lb_error "Error: cannot run command $exec_before"

			# if error, do not overwrite rsync exit code
			if [ $lb_exitcode == 0 ] ; then
				lb_exitcode=5
			fi

			# option exit if error
			if $exec_before_block ; then
				clean_exit --no-unmount
			fi
		fi
	fi

	# test if destination exists
	if ! prepare_destination ; then
		if ! $recurrent_backup ; then
			lbg_display_error "$tr_backup_unreachable\n$tr_verify_media"
		fi
		return 6
	fi

	# auto unmount: unmount if it was not mounted
	if $unmount_auto ; then
		if ! $mounted ; then
			unmount=true
		fi
	fi

	# create destination if not exists
	mkdir -p "$backup_destination" &> /dev/null
	if [ $? == 0 ] ; then
		# give ownership for user, don't care of errors
		# (useful if time2backup is executed with sudo and --user option)
		chown "$user" "$backup_destination" &> /dev/null
	else
		# if mkdir failed, exit
		lbg_display_error "Could not create destination at $backup_destination. Please verify your access rights."
		return 7
	fi

	# test if destination is writable
	# must keep this test because if directory exists, the previous mkdir -p command returns no error
	if ! [ -w "$backup_destination" ] ; then
		lbg_display_error "You have no write access on $backup_destination directory. Please verify your access rights."
		return 7
	fi

	# test if a backup is running
	if current_lock &> /dev/null ; then
		lbg_display_error "A backup is already running. Abording."
		# exit
		return 8
	fi

	# create lock to avoid duplicates
	backup_lock="$backup_destination/.lock_$backup_date"
	touch "$backup_lock"

	# catch term signals
	trap cancel_exit SIGHUP SIGINT SIGTERM

	# if we want to keep some logs,
	if $logs_save || $keep_logs_if_error ; then

		# set log file directory
		if [ -z "$logs_directory" ] ; then
			logs_directory="$backup_destination/logs"
		fi

		# set log file path
		logfile="$logs_directory/time2backup_$backup_date.log"

		# create logs directory
		mkdir -p "$logs_directory"
		if [ $? == 0 ] ; then
			# give ownership for user, don't care of errors
			# (useful if time2backup is executed with sudo and --user option)
			chown "$user" "$logs_directory" &> /dev/null
		else
			# if mkdir failed,
			lb_error "Could not create logs directory. Please verify your access rights."

			# exit without email or shutdown or delete log (does not exists)
			clean_exit --no-rmlog --no-shutdown 9
		fi

		# create log file
		if ! lb_set_logfile "$logfile" ; then
			lb_error "Cannot create log file $logfile. Please verify your access rights."
			clean_exit --no-rmlog --no-shutdown 9
		fi
	fi

	lb_display --log "Backup started on $current_date\n"

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
	if $mirror_mode && [ -n "$last_backup" ] ; then
		mv "$backup_destination/$last_backup" "$dest"
	else
		# create destination
		mkdir "$dest"
	fi

	# if succeeded to move or to create
	if [ $? == 0 ] ; then
		# give ownership for user, don't care of errors
		# (useful if time2backup is executed with sudo and --user option)
		chown "$user" "$dest" &> /dev/null
	else
		# if failed,
		lb_display --log "Could not prepare backup destination. Please verify your access rights."
		clean_exit 7
	fi

	# check if destination supports hard links
	if $hard_links ; then
		if ! $force_hard_links ; then
			if ! test_hardlinks ; then
				lb_display_debug --log "Destination does not support hard links. Continue in trash mode."
				hard_links=false
			fi
		fi
	fi

	# basic rsync command
	rsync_cmd=(rsync -aHv --delete --progress)

	# get config for inclusions
	if [ -f "$config_includes" ] ; then
		rsync_cmd+=(--include-from "$config_includes")
	fi

	# get config for exclusions
	if [ -f "$config_excludes" ] ; then
		rsync_cmd+=(--exclude-from "$config_excludes")
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

		# get backup type (normal, ssh, network shares, ...)
		case $(get_backup_type "$src") in
			ssh)
				source_ssh=true
				source_network=true

				# get ssh user@host
				ssh_host="$(echo "$src" | awk -F '/' '{print $3}')"

				# get ssh path
				ssh_prefix="ssh://$ssh_host"
				ssh_path="${src#$ssh_prefix}"

				# do not include protocol in absolute path
				abs_src="$ssh_host:$ssh_path"

				# get full backup path
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
							lb_exitcode=10

							# continue to next source
							continue
						fi
					else
						homedir="$(lb_homepath "${homealias:1}")"
					fi
					src="$homedir/$(echo "$src" | sed 's/^[^/]*\///')"
				fi

				# get absolute path for source
				abs_src="$(lb_abspath "$src")"

				# test if source exists
				if ! [ -e "$abs_src" ] ; then
					lb_error "Source $src does not exists!"
					errors+=("$src (does not exists)")
					lb_exitcode=10

					# continue to next source
					continue
				fi

				# get backup path
				path_dest="$(get_backup_path "$abs_src")"
				;;
		esac

		# set final destination with is a representation of system tree
		# e.g. /path/to/my/backups/mypc/2016-12-31-2359/files/home/user/tobackup
		finaldest="$dest/$path_dest"

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
				mv "$backup_destination/$lastcleanbackup/$path_dest" "$(dirname "$finaldest")"
				prepare_dest=$?
			fi
		fi

		# if mkdir or mv succeeded,
		if [ $prepare_dest == 0 ] ; then
			# give ownership for user, don't care of errors
			# (useful if time2backup is executed with sudo and --user option)
			chown "$user" "$finaldest" &> /dev/null
		else
			# if error,
			lb_display --log "Could not prepare backup destination for source $src. Please verify your access rights."

			# prepare report and save exit code
			errors+=("$src (write error)")
			if [ $lb_exitcode == 0 ] ; then
				lb_exitcode=7
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
						cmd+=(--link-dest="$linkdest/$lastcleanbackup/$path_dest")
					fi
				else
					# backups with a "trash" folder that contains older revisions
					# be careful that trash must be set to parent directory
					# or it will create something like dest/src/src
					trash="$backup_destination/$lastcleanbackup/$path_dest"

					# create trash
					mkdir -p "$trash"

					# move last destination
					cmd+=(-b --backup-dir "$trash")
				fi
			fi
		fi

		# of course, we exclude the backup destination itself if it is included
		# into the backup source
		# e.g. to backup /media directory, we must exclude /user/device/path/to/backups
		if [[ "$backup_destination" == "$abs_src"* ]] ; then

			# get common path of the backup directory and source
			common_path="$(get_common_path "$backup_destination" "$abs_src")"

			if [ $? != 0 ] ; then
				lb_error "Cannot exclude directory backup from $src!"
				errors+=("$src (exclude error)")
				lb_exitcode=11

				# cleanup
				clean_empty_directories "$finaldest"

				# continue to next source
				continue
			fi

			# get relative exclude directory
			exclude_backup_dir="${backup_destination#$common_path}"

			if [ "${exclude_backup_dir:0:1}" != "/" ] ; then
				exclude_backup_dir="/$exclude_backup_dir"
			fi

			cmd+=(--exclude "$(dirname "$exclude_backup_dir")")
		fi

		# search in source if exclude conf file is set
		if [ -f "$abs_src/.rsyncignore" ] ; then
			cmd+=(--exclude-from="$abs_src/.rsyncignore")
		fi

		# add ssh options if ssh
		if $source_ssh ; then
			if [ -n "$ssh_options" ] ; then
				cmd+=(-e "$ssh_options")
			else
				cmd+=(-e ssh)
			fi
		fi

		# enable network compression if network
		if $source_network ; then
			if $network_compression ; then
				cmd+=(-z)
			fi
		fi

		# if it is a directory, add '/' at the end of the path
		if [ -d "$abs_src" ] ; then
			abs_src+="/"
		fi

		# add source and destination
		cmd+=("$abs_src" "$finaldest")

		lb_display --log "Preparing backup..."

		# display prepare notification
		if $notifications ; then
			if [ $s == 0 ] ; then
				lbg_notify "$tr_notify_prepare_backup"
			fi
		fi

		# test rsync and space available for backup
		if ! test_backup ; then
			lb_display --log "Error in rsync test."

			# prepare report and save exit code
			errors+=("$src (rsync test error)")
			if [ $lb_exitcode == 0 ] ; then
				lb_exitcode=12
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
			errors+=("$src (not enough space left)")
			if [ $lb_exitcode == 0 ] ; then
				lb_exitcode=13
			fi

			clean_empty_directories "$finaldest"

			# continue to next source
			continue
		fi

		# display backup notification
		if $notifications ; then
			if [ $s == 0 ] ; then
				lbg_notify "$tr_notify_progress_1\n$tr_notify_progress_2 $(date '+%H:%M:%S')"
			fi
		fi

		lb_display_debug --log "Executing: ${cmd[@]}\n"

		# execute rsync command, print into terminal and logfile
		"${cmd[@]}" 2> >(tee -a "$logfile" >&2)

		# get backup result and prepare report
		res=${PIPESTATUS[0]}
		case $res in
			0|24)
				# backup succeeded
				# (ignoring vanished files in transfer)
				success+=("$src")
				;;
			1|2|3|4|5|6)
				# critical errors that caused backup to fail
				errors+=("$src (backup failed; code: $res)")
				lb_exitcode=14
				;;
			*)
				# considering any other rsync error as not critical
				# (some files were not backuped)
				warnings+=("$src (some files were not backuped; code: $res)")
				lb_exitcode=15
				;;
		esac

		# clean empty trash directories
		if ! $hard_links ; then
			clean_empty_directories "$trash"
		fi

		# clean empty backup if nothing inside
		clean_empty_directories "$finaldest"
	done

	# final cleanup
	clean_empty_directories "$dest"

	# if nothing was backuped, consider it as critical error
	if ! [ -d "$dest" ] ; then
		errors+=("nothing was backuped!")
		lb_exitcode=14
	fi

	# if backup succeeded (all OK or even if warnings)
	if [ $lb_exitcode == 0 ] || [ $lb_exitcode == 15 ] ; then

		lb_display_debug --log "Save backup timestamp"

		# save current timestamp into config/.lastbackup file
		date '+%s' > "$last_backup_file"
		if [ $? != 0 ] ; then
			lb_display_error --log "Failed to save backup date! Please check your access rights on the config directory or recurrent backups won't work."
		fi

		# create a latest link to the last backup directory
		lb_display_debug --log "Create latest link..."

		latest_link="$backup_destination/latest"

		# delete link if exists
		if [ -L "$latest_link" ] ; then
			rm -f "$latest_link" &> /dev/null
		fi

		# create a new link (in a sub-context to avoid confusion)
		$(cd "$backup_destination" && ln -s "$backup_date" "latest" &> /dev/null)
	fi

	# print final report
	lb_display --log "\n********************************************"
	lb_display --log "\nBackup ended on $(date '+%Y-%m-%d at %H:%M:%S')"

	lb_display --log "$(report_duration)\n"

	if [ $lb_exitcode == 0 ] ; then
		lb_display --log "Backup finished successfully."

		if $notifications ; then
			lbg_notify "$tr_backup_finished\n$(report_duration)"
		fi
	else
		lb_display --log "Backup finished with some errors. Check report below and see log files for more details.\n"

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
				lbg_notify "$tr_backup_finished_warnings\n$(report_duration)"
			fi
		fi
		if [ ${#errors[@]} -gt 0 ] ; then
			report_details+="Errors: (${#errors[@]}/$nbsrc)\n"
			for ((i=0; i<${#errors[@]}; i++)) ; do
				report_details+="   - ${errors[$i]}\n"
			done

			if $notifications ; then
				lbg_notify "$tr_backup_failed\n$(report_duration)"
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
				if [ $lb_exitcode == 0 ] ; then
					lb_exitcode=16
				fi
				if $exec_after_block ; then
					clean_exit
				fi
			fi
		else
			lb_display --log "Error: cannot run command $exec_after"
			# if error, do not overwrite rsync exit code
			if [ $lb_exitcode == 0 ] ; then
				lb_exitcode=16
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
#   0: OK
#   1: usage error
#   3: config error
#   4: backup source is not reachable
#   5: no backup found for path
t2b_history() {

	# default options and variables
	quietmode=false
	history_opts=""

	# get options
	while true ; do
		case $1 in
			-a|--all)
				history_opts="-a "
				shift
				;;
			-q|--quiet)
				quietmode=true
				shift
				;;
			-h|--help)
				print_help history
				return 0
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

	# load configuration
	if ! load_config ; then
		return 3
	fi

	# test backup destination
	if ! prepare_destination ; then
		return 4
	fi

	# get file
	file="$*"

	# get backup versions of this file
	file_history=($(get_backup_history $history_opts"$file"))

	# no backup found
	if [ ${#file_history[@]} == 0 ] ; then
		lb_error "No backup found for '$file'!"
		return 5
	fi

	# print backup versions
	for b in ${file_history[@]} ; do
		# quiet mode: just print the version
		if $quietmode ; then
			echo "$b"
		else
			# complete result: print details
			abs_file="$(get_backup_path "$file")"
			if [ -z "$abs_file" ] ; then
				continue
			fi

			# get backup file
			backup_file="$backup_destination/$b/$abs_file"

			# print details of file/directory
			echo
			echo "$b:"
			ls -l "$backup_file" 2> /dev/null
		fi
	done

	# complete result (not quiet mode)
	if ! $quietmode ; then
		echo
		echo "${#file_history[@]} backups found for $file"
	fi

	return 0
}


# Restore a file
# Usage: t2b_restore [OPTIONS] [PATH]
# Options:
#   -d, --date DATE  restore file at backup DATE (use format YYYY-MM-DD-HHMMSS)"
#                    by default it restores the last available backup
#   --directory      path to restore is a directory (not necessary if path exists)
#                    If deleted or moved, indicate that the chosen path is a directory.
#   --delete-new     delete newer files if exists for directories (restore exactly the same version)
#   -f, --force      force restore; do not display confirmation
#   -h, --help       print help
# Exit codes:
#   0: file(s) restored
#   1: usage error
#   3: config error
#   4: backup source is not reachable
#   5: no backups available at this path
#   6: no backups of this file
#   7: no backup found at this date
#   8: cannot exclude destination
#   9: error while restore
#   10: some files were not restored
#   11: restore cancelled
#   12: operation not supported
t2b_restore() {

	# default options
	backup_date="latest"
	forcemode=false
	choose_date=true
	directorymode=false
	restore_moved=false
	delete_newer_files=false

	# get options
	while true ; do
		case $1 in
			-d|--date)
				if lb_test_arguments -eq 0 $2 ; then
					print_help restore
					return 1
				fi
				backup_date="$2"
				choose_date=false
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
				return 0
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
		return 3
	fi

	# test backup destination
	if ! prepare_destination ; then
		return 4
	fi

	# test hard links
	if ! $force_hard_links ; then
		if ! test_hardlinks ; then
			hard_links=false
		fi
	fi

	# get all backups
	backups=($(get_backups))
	# if no backups, exit
	if [ ${#backups[@]} == 0 ] ; then
		lbg_display_error "$tr_no_backups_available"
		return 5
	fi

	# if no file specified, go to interactive mode
	if [ $# == 0 ] ; then

		restore_opts=("$tr_restore_existing_file" "$tr_restore_moved_file")

		if $hard_links ; then
			restore_opts+=("$tr_restore_existing_directory" "$tr_restore_moved_directory")
		fi

		# choose type of file to restore (file/directory)
		lbg_choose_option -d 1 -l "$tr_choose_restore" "${restore_opts[@]}"
		case $? in
			0)
				# continue
				:
				;;
			2)
				# cancelled
				return 0
				;;
			*)
				# error
				return 1
				;;
		esac

		# manage choosed option
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
			lbg_choose_directory -t "$tr_choose_directory_to_restore" "$starting_path"
			case $? in
				0)
					# continue
					:
					;;
				2)
					# cancelled
					return 0
					;;
				*)
					# error
					return 1
					;;
			esac

			# get path to restore
			file="$lbg_choose_directory/"
		else
			# choose a file
			lbg_choose_file -t "$tr_choose_file_to_restore" "$starting_path"
			case $? in
				0)
					# continue
					:
					;;
				2)
					# cancelled
					return 0
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
				lbg_display_error "$tr_path_is_not_backup"
				return 1
			fi

			# remove destination path prefix
			file="${file#$backup_destination}"
			# remove slashes
			if [ "${file:0:1}" == "/" ] ; then
				file="${file:1}"
			fi

			# get backup date
			backup_date="$(echo "$file" | grep -oE "^[1-9][0-9]{3}-[0-1][0-9]-[0-3][0-9]-[0-2][0-9][0-5][0-9][0-5][0-9]" 2> /dev/null)"
			if [ -z "$backup_date" ] ; then
				lbg_display_error "$tr_path_is_not_backup"
				return 1
			fi

			choose_date=false

			# if it is a directory, add '/' at the end of the path
			if [ -d "$file" ] ; then
				file+="/"
			fi

			# remove backup date path prefix
			file="${file#$backup_date}"

			# check if it is a file backup
			if [ "$(echo ${file:0:7})" != "/files/" ] ; then
				lbg_display_error "$tr_path_is_not_backup"
				lb_error "Restoring ssh/network files is not supported yet."
				return 12
			fi

			# absolute path of destination
			file="${file:6}"
		fi
	else
		# get specified path
		file="$*"
	fi

	# case of symbolic links
	if [ -L "$file" ] ; then
		lbg_display_error "$tr_cannot_restore_links"
		return 12
	fi

	# if it is a directory, add '/' at the end of the path
	if [ -d "$file" ] ; then
		if [ "${file:${#file}-1}" != "/" ] ; then
			file+="/"
		fi
	fi

	lb_display_debug "Path to restore: $file"

	# get backup full path
	backup_file_path="$(get_backup_path "$file")"

	# if error, exit
	if [ -z "$backup_file_path" ] ; then
		return 1
	fi

	# get all versions of the file/directory
	file_history=($(get_backup_history "$file"))

	# if no backup found
	if [ ${#file_history[@]} == 0 ] ; then
		lbg_display_error "$tr_no_backups_for_file"
		return 6
	fi

	# search for dates
	if [ "$backup_date" != "latest" ] ; then
		# if date was specified but not here, error
		if ! lb_array_contains "$backup_date" "${file_history[@]}" ; then
			lbg_display_error "$tr_no_backups_on_date\n$tr_run_to_show_history $lb_current_script history $file"
			return 7
		fi
	fi

	# if only one backup, no need to choose one
	if [ ${#file_history[@]} -gt 1 ] ; then

		# if interactive mode, prompt user to choose a backup date
		if $choose_date ; then

			# change dates to a user-friendly format
			history_dates=(${file_history[@]})

			for ((i=0; i<${#file_history[@]}; i++)) ; do
				history_dates[$i]=$(get_backup_fulldate "${file_history[$i]}")
			done

			# choose backup date
			lbg_choose_option -d 1 -l "$tr_choose_backup_date" "${history_dates[@]}"
			case $? in
				0)
					# continue
					:
					;;
				2)
					# cancelled
					return 0
					;;
				*)
					# error
					return 1
					;;
			esac

			# get chosen backup (= chosen ID - 1 because array ID starts from 0)
			backup_date=${file_history[$(($lbg_choose_option - 1))]}
		fi
	fi

	# if latest backup wanted, get most recent date
	if [ "$backup_date" == "latest" ] ; then
		backup_date=${file_history[0]}
	fi

	# set backup source for restore command
	src="$backup_destination/$backup_date/$backup_file_path"

	# if source is a directory
	if [ -d "$src" ] ; then
		directorymode=true
	fi

	# prepare destination
	if $directorymode ; then

		# trash mode: cannot restore directories
		if ! $hard_links ; then
			lbg_display_error "$tr_cannot_restore_from_trash"
			return 12
		fi
	fi

	dest="$file"

	# catch term signals
	trap cancel_exit SIGHUP SIGINT SIGTERM

	# prepare rsync command
	rsync_cmd=(rsync -aHv)

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

	# of course, we exclude the backup destination itself if it is included
	# into the destination path
	# e.g. to restore /media directory, we must exclude /user/device/path/to/backups
	if [[ "$backup_destination" == "$dest"* ]] ; then

		# get common path of the backup directory and source
		common_path="$(get_common_path "$backup_destination" "$dest")"

		if [ $? != 0 ] ; then
			lb_error "Cannot exclude directory backup from $dest!"
			errors+=("$dest (exclude error)")
			lb_exitcode=8

			# continue to next source
			continue
		fi

		# get relative exclude directory
		exclude_backup_dir="${backup_destination#$common_path}"

		if [ "${exclude_backup_dir:0:1}" != "/" ] ; then
			exclude_backup_dir="/$exclude_backup_dir"
		fi

		rsync_cmd+=(--exclude "$(dirname "$exclude_backup_dir")")
	fi

	# search in source if exclude conf file is set
	if [ -f "$src/.rsyncignore" ] ; then
		rsync_cmd+=(--exclude-from="$src/.rsyncignore")
	fi

	# test newer files
	if ! $delete_newer_files ; then
		if $directorymode ; then
			# prepare test command
			cmd=("${rsync_cmd[@]}")
			cmd+=(--delete --dry-run "$src" "$dest")

			lb_display "Testing restore..."
			lb_display_debug ${cmd[@]}

			# test to check newer files
			"${cmd[@]}" | grep "^deleting "

			if [ $? == 0 ] ; then
				if ! lbg_yesno "$tr_ask_keep_newer_files_1\n$tr_ask_keep_newer_files_2" ; then
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
		if ! lbg_yesno "$(printf "$tr_confirm_restore_1" "$file" "$(get_backup_fulldate $backup_date)")\n$tr_confirm_restore_2" ; then
			# cancelled
			return 0
		fi
	fi

	# prepare rsync restore command
	cmd=("${rsync_cmd[@]}")

	if $delete_newer_files ; then
		cmd+=(--delete)
	fi

	cmd+=(--progress --human-readable "$src" "$dest")

	echo "Restore file from backup $backup_date..."
	lb_display_debug "Executing: ${cmd[@]}"

	# execute rsync command
	"${cmd[@]}"
	lb_result

	# rsync results
	case $? in
		0)
			# file restored
			lbg_display_info "$tr_restore_finished"
			;;
		1|2|3|4|5|6)
			# critical errors that caused backup to fail
			lbg_display_error "$tr_restore_failed"
			lb_exitcode=9
			;;
		*)
			# rsync minor error
			lbg_display_warning "$tr_restore_finished_warnings"
			lb_exitcode=10
			;;
	esac

	return $lb_exitcode
}


# Configure time2backup
# Usage: t2b_config [OPTIONS]
#   -g, --general     edit general configuration
#   -s, --sources     edit sources file (sources to backup)
#   -x, --excludes    edit excludes file (patterns to ignore)
#   -i, --includes    edit includes file (patterns to include)
#   -l, --show        show configuration; do not edit
#                     display configuration without comments
#   -t, --test        test configuration; do not edit
#   -w, --wizard      display configuration wizard instead of edit
#   -e, --editor BIN  use specified editor (e.g. vim, nano, ...)
#   -h, --help        print help
# Exit codes:
#   0: config OK
#   1: usage error
#   3: config is not OK
#   4: error when install config
#   5: failed to open/save configuration
#   6: no editor found to open configuration file
#   7: unknown error
t2b_config() {

	# default values
	file=""
	op_config=""
	cmd_opts=""
	show_sources=false

	# get options
	# following other options to edit_config() function
	while true ; do
		case $1 in
			-g|--general)
				file="$config_file"
				shift
				;;
			-x|--excludes)
				file="$config_excludes"
				shift
				;;
			-i|--includes)
				file="$config_includes"
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
			-w|--wizard)
				op_config="wizard"
				shift
				;;
			-e|--editor)
				if lb_test_arguments -eq 0 $2 ; then
					return 1
				fi
				cmd_opts="-e $2 "
				shift 2
				;;
			-h|--help)
				print_help config
				return 0
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

	if [ -z "$file" ] ; then

		if [ -z "$op_config" ] ; then
			if ! lbg_choose_option -l "$tr_choose_config_file" \
						"$tr_global_config" "$tr_sources_config" "$tr_excludes_config" "$tr_includes_config" "$tr_run_config_wizard" ; then
				return 0
			fi

			case "$lbg_choose_option" in
				1)
					file="$config_file"
					;;
				2)
					file="$config_sources"
					;;
				3)
					file="$config_excludes"
					;;
				4)
					file="$config_includes"
					;;
				5)
					op_config="wizard"
					;;
				*)
					# bad choice
					return 1
					;;
			esac
		fi
	fi

	# special operations: show and test
	case $op_config in
		wizard)
			load_config

			# run config wizard
			config_wizard
			;;
		show)
			# if not set, file config is general config
			if [ -z "$file" ] ; then
				file="$config_file"
			fi

			# get sources is a special case to print list without comments
			# read sources.conf file line by line
			while read line ; do
				if ! lb_is_comment $line ; then
					echo "$line"
				fi
			done < "$file"

			if [ $? != 0 ] ; then
				return 5
			fi
			;;
		test)
			# load and test configuration
			echo "Testing configuration..."
			load_config
			lb_result
			;;
		*)
			# edit configuration
			echo "Opening configuration file..."
			edit_config $cmd_opts"$file"

			case $? in
				0)
					install_config
					if [ $? != 0 ] ; then
						return 4
					fi
					;;
				3)
					return 5
					;;
				4)
					return 6
					;;
				*)
					return 7
					;;
			esac
			;;
	esac

	# config is not OK
	if [ $? != 0 ] ; then
		return 3
	fi

	return 0
}


# Install time2backup
# Create a link to execute time2backup easely and create default configuration
# Usage: t2b_install [OPTIONS]
#   -r, --reset-config  reset configuration files to default
#   -h, --help          print help
# Exit codes:
#   0: OK
#   1: usage error
#   3: there are errors in config
#   4: error while creating application shortcuts
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
				return 0
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

	echo "Install time2backup..."

	# create a desktop file (Linux)
	if [ "$(lb_detect_os)" != "macOS" ] ; then

		desktop_file="$script_directory/time2backup.desktop"

		cat > "$desktop_file" <<EOF
[Desktop Entry]
Version=1.0
Name=time2backup
GenericName=Files backup
Comment=Backup and restore your files
GenericName[fr]=Sauvegarde de fichiers
Comment[fr]=Sauvegardez et restaurez vos données
Type=Application
Exec=$(lb_realpath "$lb_current_script") $*
Icon=$(lb_realpath "$script_directory/resources/icon.png")
Terminal=false
Categories=System;Utility;Filesystem;
EOF

		# copy desktop file to /usr/share/applications
		if [ -d "/usr/share/applications" ] ; then

			cp -f "$desktop_file" "/usr/share/applications/" &> /dev/null
			if [ $? != 0 ] ; then
				echo
				echo "Cannot create application link. It's not critical, but you may not have the icon on your system."
				echo "You can try the following command:"
				echo "   sudo cp -f \"$desktop_file\" /usr/share/applications/"
				lb_exitcode=4
			fi
		fi
	fi

	# reset configuration
	if $reset_config ; then

		# confirm reset
		if lbg_yesno "Are you sure you want to reset config?" ; then
			rm -f "$config_file"
			rm -f "$config_sources"
			rm -f "$config_excludes"
			rm -f "$config_includes"

			if ! create_config ; then
				lb_exitcode=3
			fi
		fi
	fi

	# if alias exists,
	if [ -e "$cmd_alias" ] ; then
		# if the same path, OK
		if [ "$(lb_realpath "$cmd_alias")" == "$(lb_realpath "$lb_current_script")" ] ; then
			# quit
			return $lb_exitcode
		fi

		# delete old link
		rm -f "$cmd_alias" &> /dev/null
		if [ $? != 0 ] ; then
			echo "A link to time2backup already exists and we cannot remove it. Try the following commands:"
			echo "   sudo rm -f \"$cmd_alias\""
			echo "   sudo ln -s \"$current_script\" \"$cmd_alias\""

			# this exit code is less important
			if [ $lb_exitcode == 0 ] ; then
				lb_exitcode=4
			fi

			# quit
			return $lb_exitcode
		fi
	fi

	# create link
	ln -s "$current_script" "$cmd_alias" &> /dev/null
	if [ $? != 0 ] ; then
		echo
		echo "Cannot create command link. It's not critical, but you may not run time2backup command directly."
		echo "You can try the following command:"
		echo "   sudo ln -s \"$current_script\" \"$cmd_alias\""
		echo "or add an alias in your bashrc file."

		# this exit code is less important
		if [ $lb_exitcode == 0 ] ; then
			lb_exitcode=4
		fi
	fi

	return $lb_exitcode
}
