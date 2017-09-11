#
# time2backup commands
#
# This file is part of time2backup (https://time2backup.github.io)
#
# MIT License
# Copyright (c) 2017 Jean Prunneaux
#

# Index of functions
#
#   t2b_backup
#   t2b_restore
#   t2b_history
#   t2b_explore
#   t2b_status
#   t2b_stop
#   t2b_config
#   t2b_install
#   t2b_uninstall


# Perform backup
# Usage: t2b_backup [OPTIONS] [PATH...]
t2b_backup() {

	# default values and options
	recurrent_backup=false
	destination_ssh=false
	source_ssh=false
	backup_on_network=false

	# get current date
	current_timestamp=$(date +%s)
	current_date=$(date '+%Y-%m-%d at %H:%M:%S')

	# set backup directory with current date (format: YYYY-MM-DD-HHMMSS)
	backup_date=$(date +%Y-%m-%d-%H%M%S)

	# get options
	while [ -n "$1" ] ; do
		case $1 in
			-u|--unmount)
				force_unmount=true
				unmount=true
				;;
			-s|--shutdown)
				force_shutdown=true
				shutdown=true
				;;
			-r|--recurrent)
				recurrent_backup=true
				;;
			-h|--help)
				print_help
				return 0
				;;
			-*)
				print_help
				return 1
				;;
			*)
				break
				;;
		esac
		shift # load next argument
	done

	# specified source(s)
	while [ -n "$1" ] ; do
		sources+=("$1")
		shift
	done

	# if not specified, get sources from config file
	if [ ${#sources[@]} == 0 ] ; then

		if ! lb_read_config "$config_sources" ; then
			lbg_display_error "Cannot read sources.conf file!"
			return 3
		fi

		sources=("${lb_read_config[@]}")
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

		# if disabled in default configuration
		if ! $enable_recurrent ; then
			lb_display_error "Recurrent backups are disabled."
			return 20
		fi

		# recurrent backups not enabled in configuration
		if ! $recurrent ; then
			lb_display_warning "Recurrent backups are disabled. You can enable it in configuration file."
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
			case $frequency in
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
					case ${frequency:${#frequency}-1} in
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
	fi # recurrent backups

	# execute before backup command/script
	if [ ${#exec_before[@]} -gt 0 ] ; then
		# test command/script
		if lb_command_exists "${exec_before[0]}" ; then

			# run command/script
			"${exec_before[@]}"

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
			# if command/script not found
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

	# prepare destination (mount and verify writable)
	prepare_destination
	case $? in
		1)
			# destination not reachable
			if ! $recurrent_backup ; then
				lbg_display_error "$tr_backup_unreachable\n$tr_verify_media"
			fi
			return 6
			;;
		2)
			# destination not writable
			return 7
			;;
	esac

	if ! $destination_ssh ; then
		# test if a backup is running
		if current_lock &> /dev/null ; then
			if $recurrent_backup ; then
				lb_display_error "$tr_backup_already_running"
			else
				lbg_display_error "$tr_backup_already_running"
			fi
			# exit
			return 8
		fi

		# create lock to avoid duplicates
		backup_lock="$backup_destination/.lock_$backup_date"
		touch "$backup_lock"
	fi

	# catch term signals
	trap cancel_exit SIGHUP SIGINT SIGTERM

	# set log file directory
	if [ -z "$logs_directory" ] ; then
		logs_directory="$backup_destination/logs"
	fi

	# set log file path
	logfile="$logs_directory/time2backup_$backup_date.log"

	# create log file
	if ! create_logfile "$logfile" ; then
		clean_exit --no-rmlog --no-shutdown 9
	fi

	lb_display --log "Backup started on $current_date\n"

	# get last backup
	if $destination_ssh ; then
		last_backup=latest
	else
		last_backup=$(ls "$backup_destination" | grep -E "^[1-9][0-9]{3}-[0-1][0-9]-[0-3][0-9]-[0-2][0-9][0-5][0-9][0-5][0-9]$" | tail -n 1)
	fi

	# set new backup directory
	dest="$backup_destination/$backup_date"

	lb_display --log "Prepare backup destination..."

	# if keep limit to 0, we are in a mirror mode
	if [ $keep_limit == 0 ] ; then
		mirror_mode=true
	fi

	# if mirror mode and there is an old backup, move last backup to current directory
	if $mirror_mode && [ -n "$last_backup" ] ; then
		mv "$backup_destination/$last_backup" "$dest"
	else
		# create destination
		mkdir "$dest"
	fi

	# if failed to move or to create
	if [ $? != 0 ] ; then
		lb_display_error --log "Could not prepare backup destination. Please verify your access rights."
		clean_exit 7
	fi

	# check if destination supports hard links
	if ! $destination_ssh ; then
		if $hard_links ; then
			if ! $force_hard_links ; then
				if ! test_hardlinks "$destination" ; then
					lb_display_debug --log "Destination does not support hard links. Continue in trash mode."
					hard_links=false
				fi
			fi
		fi
	fi

	# prepare rsync command
	prepare_rsync backup

	# execute backup for each source
	# do a loop like this to prevent errors with spaces in strings
	# do not use for ... in ... syntax
	for ((s=0; s < $nbsrc; s++)) ; do

		src=${sources[$s]}

		lb_display --log "\n********************************************\n"
		lb_display --log "Backup $src... ($(($s + 1))/$nbsrc)\n"

		# display notification when preparing backups
		# (just display the first notification, not for every sources)
		if $notifications ; then
			if [ $s == 0 ] ; then
				lbg_notify "$tr_notify_prepare_backup"
			fi
		fi

		lb_display --log "Preparing backup..."

		# get source path
		protocol=$(get_protocol "$src")
		case $protocol in
			ssh|t2b)
				# test if we don't have double ssh
				if $destination_ssh ; then
					lb_display_error --log "You cannot backup a distant path to a distant path."
					errors+=("$src (cannot backup a distant path on a distant destination)")
					lb_exitcode=3
					continue
				fi

				source_ssh=true
				backup_on_network=true

				# get ssh [user@]host
				ssh_host=$(echo "$src" | awk -F '/' '{print $3}')

				# get ssh path
				ssh_prefix="$protocol://$ssh_host"
				ssh_path=${src#$ssh_prefix}

				# do not include protocol in absolute path
				abs_src="$ssh_host:$ssh_path"

				# get full backup path
				path_dest=$(get_backup_path "$src")
				;;
			*)
				# file or directory
				# replace ~ by user home directory
				if [ "${src:0:1}" == "~" ] ; then
					# get first part of the path
					homealias=$(echo "$src" | awk -F '/' '{ print $1 }')

					# get user
					if [ "$homealias" == "~" ] ; then
						# current user
						homeuser=$user
					else
						# defined user
						homeuser=${homealias:1}
					fi

					if [ "$lb_current_os" == Windows ] ; then
						# path of the config is in c:\Users\{user}\AppData\Roaming\time2backup
						# so we can go up to c:\Users
						homedir=$config_directory
						for ((d=1; d<=4; d++)) ; do
							homedir=$(dirname "$homedir")
							lb_display_debug "Finding windows homedir: $homedir"
						done

						# then complete by \{user}
						homedir="$homedir/$homeuser"
						# and test it
						[ -d "$homedir" ]
					else
						# get home path of the user
						homedir=$(lb_homepath $homeuser)
					fi

					# if path is ok
					if [ $? != 0 ] ; then
						lb_display_error --log "Cannot get user homepath.\nPlease use absolute paths instead of ~ aliases in your sources.conf file."
						errors+=("$src (does not exists)")
						lb_exitcode=10

						# continue to next source
						continue
					fi

					src="$homedir/$(echo "$src" | sed 's/^[^/]*\///')"
				fi

				# get absolute path for source
				if [ "$lb_current_os" == Windows ] ; then
					# get realpath for Windows formats
					abs_src=$(lb_realpath "$src")
				else
					abs_src=$(lb_abspath "$src")
				fi

				# test if source exists
				if ! [ -e "$abs_src" ] ; then
					lb_error "Source $src does not exists!"
					errors+=("$src (does not exists)")
					lb_exitcode=10

					# continue to next source
					continue
				fi

				# get backup path
				path_dest=$(get_backup_path "$abs_src")
				;;
		esac

		# set final destination with is a representation of system tree
		# e.g. /path/to/my/backups/mypc/2016-12-31-2359/files/home/user/tobackup
		finaldest="$dest/$path_dest"

		# create destination folder
		mkdir -p "$finaldest"
		prepare_dest=$?

		# reset last backup date
		lastcleanbackup=""

		# if there is at least one old backup
		if [ -n "$last_backup" ] ; then

			# get all backup dates
			all_backups=($(get_backups))

			# find the last backup of this source
			# starting from the latest to the oldest but ignore current date (array length - 2)
			for ((b=${#all_backups[@]}-2; b>=0; b--)) ; do
				old_backup_path="$backup_destination/${all_backups[$b]}/$path_dest"

				# found an old backup for the current source
				if [ -d "$old_backup_path" ] ; then
					# must not be empty
					if ! lb_dir_is_empty "$old_backup_path" ; then

						lb_display_debug --log "Last backup found: $lastcleanbackup for $backup_destination/${all_backups[$b]}/$path_dest"

						# save last backup date and continue
						lastcleanbackup=${all_backups[$b]}
						break
					fi
				fi
			done
		fi

		# no hard links means to use the trash mode
		if ! $hard_links ; then
			# move old backup as current backup, if exists
			if [ -n "$lastcleanbackup" ] ; then
				mv "$backup_destination/$lastcleanbackup/$path_dest" "$(dirname "$finaldest")"
				prepare_dest=$?
			fi
		fi

		# if mkdir (hard links mode) or mv (trash mode) failed,
		if [ $prepare_dest != 0 ] ; then
			lb_display_error --log "Could not prepare backup destination for source $src. Please verify your access rights."

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
					linkdest=$(get_relative_path "$finaldest" "$backup_destination")
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
			common_path=$(get_common_path "$backup_destination" "$abs_src")

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
			exclude_backup_dir=${backup_destination#$common_path}

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
				# if empty, defines default option
				cmd+=(-e ssh)
			fi

			# rsync distant path option
			if [ -n "$rsync_remote_path" ] ; then
				cmd+=(--rsync-path "$rsync_remote_path")
			fi
		fi

		# enable network compression if network
		if $backup_on_network ; then
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

		# prepare backup: testing space
		if $test_destination ; then

			# reset backup size
			total_size=0

			# test rsync and space available for backup
			if ! test_backup ; then
				lb_display --log "Error in rsync test."

				# prepare report and save exit code
				errors+=("$src (rsync test error)")
				if [ $lb_exitcode == 0 ] ; then
					lb_exitcode=12
				fi

				clean_empty_directories "$finaldest"

				# continue to the next backup source
				continue
			fi

			# if not enough space on disk to backup, cancel
			if ! test_free_space ; then
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
		fi # end of free space tests

		# display notification when backup starts
		# (just display the first notification, not for every sources)
		if $notifications ; then
			if [ $s == 0 ] ; then
				lbg_notify "$tr_notify_progress_1\n$tr_notify_progress_2 $(date '+%H:%M:%S')"
			fi
		fi

		lb_display --log "Running backup..."
		lb_display_debug --log "Executing: ${cmd[@]}\n"

		# real backup: execute rsync command, print result into terminal and logfile
		"${cmd[@]}" 2> >(tee -a "$logfile" >&2)

		# get backup result and prepare report
		res=${PIPESTATUS[0]}

		if [ $res == 0 ] ; then
			# backup succeeded
			# (ignoring vanished files in transfer)
			success+=("$src")
		else
			if rsync_result $res ; then
				# rsync minor errors (partial transfers)
				warnings+=("$src (some files were not backuped; code: $res)")
				lb_exitcode=15
			else
				# critical errors that caused backup to fail
				errors+=("$src (backup failed; code: $res)")
				lb_exitcode=14
			fi
		fi

		# clean empty trash directories
		if ! $hard_links ; then
			clean_empty_directories "$trash"
		fi

		# clean empty backup if nothing inside
		clean_empty_directories "$finaldest"

	done # end of backup sources

	lb_display --log "\n********************************************\n"

	# final cleanup
	clean_empty_directories "$dest"

	# if nothing was backuped, consider it as a critical error
	# and do not rotate backups
	if ! [ -d "$dest" ] ; then
		errors+=("nothing was backuped!")
		lb_exitcode=14
	else
		# rotate backups
		if [ $keep_limit -ge 0 ] ; then
			if $notifications ; then
				lbg_notify "$tr_notify_rotate_backup"
			fi

			rotate_backups $keep_limit
		fi
	fi

	# if backup succeeded (all OK or even if warnings)
	case $lb_exitcode in
		0|5|15)
			lb_display_debug --log "Save backup timestamp"

			# save current timestamp into config/.lastbackup file
			date '+%s' > "$last_backup_file"
			if [ $? != 0 ] ; then
				lb_display_error --log "Failed to save backup date! Please check your access rights on the config directory or recurrent backups won't work."
			fi

			# create a latest link to the last backup directory
			lb_display_debug --log "Create latest link..."

			# create a new link (in a sub-context to avoid confusion)
			if [ "$lb_current_os" == Windows ] ; then
				$(cd "$backup_destination" && rm -f latest && ln -s "$backup_date" latest)
			else
				$(cd "$backup_destination" && rm -f latest && cmd /c mklink /j latest "$backup_date")
			fi
			;;
	esac

	# print final report
	lb_display --log "Backup ended on $(date '+%Y-%m-%d at %H:%M:%S')"

	lb_display --log "$(report_duration)\n"

	if [ $lb_exitcode == 0 ] ; then
		lb_display --log "Backup finished successfully."

		if $notifications ; then
			# Windows: display dialogs instead of notifications
			if [ "$lb_current_os" == Windows ] ; then
				# do not popup dialog that would prevent PC from shutdown
				if ! $shutdown ; then
					lbg_display_info "$tr_backup_finished\n$(report_duration)"
				fi
			else
				lbg_notify "$tr_backup_finished\n$(report_duration)"
			fi
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
				# Windows: display dialogs instead of notifications
				if [ "$lb_current_os" == Windows ] ; then
					# do not popup dialog that would prevent PC from shutdown
					if ! $shutdown ; then
						lbg_display_warning "$tr_backup_finished_warnings\n$(report_duration)"
					fi
				else
					lbg_notify "$tr_backup_finished_warnings\n$(report_duration)"
				fi
			fi
		fi

		if [ ${#errors[@]} -gt 0 ] ; then
			report_details+="Errors: (${#errors[@]}/$nbsrc)\n"
			for ((i=0; i<${#errors[@]}; i++)) ; do
				report_details+="   - ${errors[$i]}\n"
			done

			if $notifications ; then
				# Windows: display dialogs instead of notifications
				if [ "$lb_current_os" == Windows ] ; then
					# do not popup dialog that would prevent PC from shutdown
					if ! $shutdown ; then
						lbg_display_error "$tr_backup_failed\n$(report_duration)"
					fi
				else
					lbg_notify "$tr_backup_failed\n$(report_duration)"
				fi
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


# Restore a file
# Usage: t2b_restore [OPTIONS] [PATH]
t2b_restore() {

	# default options
	backup_date="latest"
	force_mode=false
	choose_date=true
	directorymode=false
	restore_moved=false
	delete_newer_files=false

	# get options
	while [ -n "$1" ] ; do
		case $1 in
			-d|--date)
				if [ -z "$2" ] ; then
					print_help
					return 1
				fi
				backup_date=$2
				choose_date=false
				shift
				;;
			--directory)
				directorymode=true
				;;
			--delete-new)
				delete_newer_files=true
				;;
			-f|--force)
				force_mode=true
				;;
			-h|--help)
				print_help
				return 0
				;;
			-*)
				print_help
				return 1
				;;
			*)
				break
				;;
		esac
		shift # load next argument
	done

	# test backup destination
	if ! prepare_destination ; then
		return 4
	fi

	# test hard links
	if ! $force_hard_links ; then
		if ! test_hardlinks "$destination" ; then
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

		# if hard links supported, add directory restore features
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

		# manage chosen option
		case $lbg_choose_option in
			1)
				# restore a file
				:
				;;
			2)
				# restore a moved file
				starting_path=$backup_destination
				restore_moved=true
				;;
			3)
				# restore a directory
				directorymode=true
				;;
			4)
				# restore a moved directory
				starting_path=$backup_destination
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
			file=$lbg_choose_file
		fi

		# restore a moved file
		if $restore_moved ; then

			# test if path to restore is stored in the backup directory
			if [[ "$file" != "$backup_destination"* ]] ; then
				lbg_display_error "$tr_path_is_not_backup"
				return 1
			fi

			# remove destination path prefix
			file=${file#$backup_destination}
			# remove slashes
			if [ "${file:0:1}" == "/" ] ; then
				file=${file:1}
			fi

			# get backup date
			backup_date=$(echo "$file" | grep -oE "^[1-9][0-9]{3}-[0-1][0-9]-[0-3][0-9]-[0-2][0-9][0-5][0-9][0-5][0-9]" 2> /dev/null)
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
			file=${file#$backup_date}

			# check if it is a file backup
			if [ "$(echo ${file:0:7})" != "/files/" ] ; then
				lbg_display_error "$tr_path_is_not_backup"
				lb_error "Restoring ssh/network files is not supported yet."
				return 12
			fi

			# absolute path of destination
			file=${file:6}
		fi
	else
		# get specified path
		if [ "$lb_current_os" == Windows ] ; then
			file=$(lb_realpath "$*")
		else
			file=$*
		fi
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
	backup_file_path=$(get_backup_path "$file")

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
		# trash mode: cannot restore directories
		if ! $hard_links ; then
			lbg_display_error "$tr_cannot_restore_from_trash"
			return 12
		else
			# enable directory mode
			directorymode=true
		fi
	fi

	# prepare destination
	dest=$file

	# catch term signals
	trap cancel_exit SIGHUP SIGINT SIGTERM

	# prepare rsync command
	prepare_rsync restore

	# of course, we exclude the backup destination itself if it is included
	# into the destination path
	# e.g. to restore /media directory, we must exclude /user/device/path/to/backups
	if [[ "$backup_destination" == "$dest"* ]] ; then

		# get common path of the backup directory and source
		common_path=$(get_common_path "$backup_destination" "$dest")

		if [ $? != 0 ] ; then
			lb_display_debug "Cannot exclude directory backup from $dest!"
			lbg_display_error "$tr_restore_unknown_error"
			return 8
		fi

		# get relative exclude directory
		exclude_backup_dir=${backup_destination#$common_path}

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

			# notify to prepare restore
			if $notifications ; then
				lbg_notify "$tr_notify_prepare_restore"
			fi

			echo "Preparing restore..."
			lb_display_debug ${cmd[@]}

			# test rsync to check newer files
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
	if ! $force_mode ; then
		if ! lbg_yesno "$(printf "$tr_confirm_restore_1" "$file" "$(get_backup_fulldate $backup_date)")\n$tr_confirm_restore_2" ; then
			# cancelled
			return 0
		fi
	fi

	# prepare rsync restore command
	cmd=("${rsync_cmd[@]}")

	# delete new files
	if $delete_newer_files ; then
		cmd+=(--delete)
	fi

	cmd+=("$src" "$dest")

	echo "Restore file from backup $backup_date..."
	lb_display_debug "Executing: ${cmd[@]}"

	# execute rsync command
	"${cmd[@]}"
	lb_result
	res=$?

	# rsync results
	if [ $res == 0 ] ; then
		# file restored
		lbg_display_info "$tr_restore_finished"
	else
		if rsync_result $res ; then
			# rsync minor errors (partial transfers)
			lbg_display_warning "$tr_restore_finished_warnings"
			lb_exitcode=10
		else
			# critical errors that caused backup to fail
			lbg_display_error "$tr_restore_failed"
			lb_exitcode=9
		fi
	fi

	return $lb_exitcode
}


# Get history/versions of a file
# Usage: t2b_history [OPTIONS] PATH
t2b_history() {

	# default options
	local quiet_mode=false
	local history_opts=""

	# get options
	while [ -n "$1" ] ; do
		case $1 in
			-a|--all)
				history_opts="-a "
				;;
			-q|--quiet)
				quiet_mode=true
				;;
			-h|--help)
				print_help
				return 0
				;;
			-*)
				print_help
				return 1
				;;
			*)
				break
				;;
		esac
		shift # load next argument
	done

	# usage errors
	if [ $# == 0 ] ; then
		print_help
		return 1
	fi

	# test backup destination
	if ! prepare_destination ; then
		return 4
	fi

	# get file
	if [ "$lb_current_os" == Windows ] ; then
		file=$(lb_realpath "$*")
	else
		file=$*
	fi

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
		if $quiet_mode ; then
			echo "$b"
		else
			# complete result: print details
			abs_file=$(get_backup_path "$file")
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
	if ! $quiet_mode ; then
		echo
		echo "${#file_history[@]} backups found for $file"
	fi

	return 0
}


# Explore backups
# Usage: t2b_explore [OPTIONS] [PATH]
t2b_explore() {

	# default options
	backup_date=latest
	choose_date=true
	explore_all=false

	# get options
	while [ -n "$1" ] ; do
		case $1 in
			-a|--all)
				explore_all=true
				;;
			-d|--date)
				if [ -z "$2" ] ; then
					print_help
					return 1
				fi
				backup_date=$2
				choose_date=false
				shift
				;;
			-h|--help)
				print_help
				return 0
				;;
			-*)
				print_help
				return 1
				;;
			*)
				break
				;;
		esac
		shift # load next argument
	done

	# test backup destination
	if ! prepare_destination ; then
		return 4
	fi

	# get all backups
	backups=($(get_backups))
	# if no backups, exit
	if [ ${#backups[@]} == 0 ] ; then
		lbg_display_error "$tr_no_backups_available"
		return 5
	fi

	path=$*

	if ! [ -e "$path" ] ; then
		print_help
		return 1
	fi

	# get backup full path
	backup_path=$(get_backup_path "$path")

	# if error, exit
	if [ -z "$backup_path" ] ; then
		print_help
		return 1
	fi

	# get all versions of the file/directory
	path_history=($(get_backup_history "$path"))

	# if no backup found
	if [ ${#path_history[@]} == 0 ] ; then
		lbg_display_error "$tr_no_backups_for_file"
		return 6
	fi


	if $explore_all ; then
		backup_date=${path_history[@]}
	else
		# search for dates
		if [ "$backup_date" != latest ] ; then
			# if date was specified but not here, error
			if ! lb_array_contains "$backup_date" "${path_history[@]}" ; then
				lbg_display_error "$tr_no_backups_on_date\n$tr_run_to_show_history $lb_current_script history $path"
				return 7
			fi
		fi

		# if only one backup, no need to choose one
		if [ ${#path_history[@]} -gt 1 ] ; then

			# if interactive mode, prompt user to choose a backup date
			if $choose_date ; then

				# change dates to a user-friendly format
				history_dates=(${path_history[@]})

				for ((i=0; i<${#path_history[@]}; i++)) ; do
					history_dates[$i]=$(get_backup_fulldate "${path_history[$i]}")
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
				backup_date=${path_history[$(($lbg_choose_option - 1))]}
			fi
		fi

		# if latest backup wanted, get most recent date
		if [ "$backup_date" == latest ] ; then
			backup_date=${path_history[0]}
		fi
	fi

	if ! [ -d "$path" ] ; then
		backup_path=$(dirname "$backup_path")
	fi

	for b in ${backup_date[@]} ; do
		echo "Exploring backup $b..."
		lbg_open_directory "$backup_destination/$b/$backup_path"
	done

	if [ $? != 0 ] ; then
		return 8
	fi
}


# Check if a backup is currently running
# Usage: t2b_status [OPTIONS]
t2b_status() {

	# default options
	local quiet_mode=false

	# get options
	while [ -n "$1" ] ; do
		case $1 in
			-q|--quiet)
				quiet_mode=true
				;;
			-h|--help)
				print_help
				return 0
				;;
			-*)
				print_help
				return 1
				;;
			*)
				break
				;;
		esac
		shift # load next argument
	done

	# test backup destination
	if ! prepare_destination ; then
		return 4
	fi

	# test if a backup is running
	if current_lock &> /dev/null ; then
		if ! $quiet_mode ; then
			echo "backup is running"
		fi
		return 5
	else
		if ! $quiet_mode ; then
			echo "backup is not running"
		fi
	fi
}


# Stop a running backup
# Usage: t2b_stop [OPTIONS]
t2b_stop() {

	# default options
	local quiet_mode=false
	local exit_code=5

	# get options
	while [ -n "$1" ] ; do
		case $1 in
			-q|--quiet)
				quiet_mode=true
				;;
			-h|--help)
				print_help
				return 0
				;;
			-*)
				print_help
				return 1
				;;
			*)
				break
				;;
		esac
		shift # load next argument
	done

	# check status of backup
	t2b_status --quiet

	# if no backup is running or error, cannot stop
	case $? in
		0)
			if ! $quiet_mode ; then
				echo "No backup running"
			fi
			return 0
			;;
		1)
			if ! $quiet_mode ; then
				echo "Unknown error"
			fi
			return 6
			;;
		4)
			if ! $quiet_mode ; then
				echo "Cannot reach destination."
			fi
			return 4
			;;
	esac

	# search for a current rsync command and get parent PIDs
	rsync_ppids=($(ps -ef | grep "$rsync_path" | head -n -1 | awk '{print $2}'))

	if [ ${#rsync_ppids[@]} == 0 ] ; then
		echo "No rsync process found. Please find it manually"
		return 7
	fi

	for pid in ${rsync_ppids[@]} ; do
		# get parent process
		parent_pid=$(ps -f $pid 2> /dev/null | awk '{print $3}')
		if [ -z "$parent_pid" ] ; then
			continue
		fi

		# check if parent process is an instance of time2backup server
		ps -f $parent_pid 2> /dev/null | grep -q "time2backup"
		if [ $? == 0 ] ; then
			# kill rsync process
			kill $parent_pid
			if [ $? != 0 ] ; then
				return 5
			fi
			break
		fi
	done

	# wait 10 sec max until time2backup is really stopped
	for ((i=0; i<10; i++)) ; do
		t2b_status --quiet
		if [ $? == 0 ] ; then
			exit_code=0
			break
		fi
		sleep 1
	done

	if ! $quiet_mode ; then
		if [ $exit_code == 0 ] ; then
			echo "Stopped"
		else
			echo "Still running! Could not stop time2backup process. Please retry maybe in root mode."
		fi
	fi

	return $exit_code
}


# Configure time2backup
# Usage: t2b_config [OPTIONS]
t2b_config() {

	# default values
	file=""
	local op_config=""
	local cmd_opts=""

	# get options
	# following other options to edit_config() function
	while [ -n "$1" ] ; do
		case $1 in
			-g|--general)
				file=$config_file
				;;
			-x|--excludes)
				file=$config_excludes
				;;
			-i|--includes)
				file=$config_includes
				;;
			-s|--sources)
				file=$config_sources
				;;
			-l|--show)
				op_config=show
				;;
			-t|--test)
				op_config=test
				;;
			-w|--wizard)
				op_config=wizard
				;;
			-r|--reset)
				op_config=reset
				;;
			-e|--editor)
				if [ -z "$2" ] ; then
					print_help
					return 1
				fi
				cmd_opts="-e $2 "
				shift
				;;
			-h|--help)
				print_help
				return 0
				;;
			-*)
				print_help
				return 1
				;;
			*)
				break
				;;
		esac
		shift # load next argument
	done

	# if config file not defined, ask user to choose which file to edit
	if [ -z "$file" ] ; then

		if [ -z "$op_config" ] ; then
			if ! lbg_choose_option -d 1 -l "$tr_choose_config_file" \
			     "$tr_global_config" "$tr_sources_config" "$tr_excludes_config" "$tr_includes_config" "$tr_run_config_wizard" ; then
				return 0
			fi

			case $lbg_choose_option in
				1)
					file=$config_file
					;;
				2)
					file=$config_sources
					;;
				3)
					file=$config_excludes
					;;
				4)
					file=$config_includes
					;;
				5)
					op_config=wizard
					;;
				*)
					# bad choice
					return 1
					;;
			esac
		fi
	fi

	# operations to do on config
	case $op_config in
		wizard)
			# run config wizard
			config_wizard
			;;
		show)
			# if not set, file config is general config
			if [ -z "$file" ] ; then
				file=$config_file
			fi

			# get sources is a special case to print list without comments
			# read sources.conf file line by line
			while read -r line ; do
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
		reset)
			# reset config file
			if lb_yesno "$tr_confirm_reset_config" ; then
				cat "$script_directory/config/time2backup.example.conf" > "$config_file"
			fi
			;;
		*)
			# edit configuration
			echo "Opening configuration file..."
			edit_config $cmd_opts"$file"

			# after config,
			case $? in
				0)
					# config ok: reload it
					if ! load_config ; then
						return 3
					fi

					# retest config
					if ! test_config ; then
						return 3
					fi

					# apply config
					if ! apply_config ; then
						return 4
					fi
					;;
				3)
					# errors in config
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
}


# Install time2backup
# Usage: t2b_install [OPTIONS]
t2b_install() {

	local reset_config=false

	# get options
	while [ -n "$1" ] ; do
		case $1 in
			-r|--reset-config)
				reset_config=true
				;;
			-h|--help)
				print_help
				return 0
				;;
			-*)
				print_help
				return 1
				;;
			*)
				break
				;;
		esac
		shift # load next argument
	done

	echo "Installing time2backup..."

	# create a desktop file (Linux)
	if [ "$lb_current_os" == Linux ] ; then

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
		# delete old config files
		rm -f "$config_directory/*" &> /dev/null
		if [ $? == 0 ] ; then
			# recreate config
			if ! create_config ; then
				lb_exitcode=3
			fi
		else
			echo "Error: cannot reset configuration files!"
			lb_exitcode=5
		fi
	fi

	# considering that we are installed (don't care of errors)
	touch "$script_directory/config/.install" &> /dev/null

	# if alias already exists,
	if [ -e "$cmd_alias" ] ; then
		# if the same path, OK
		if [ "$(lb_realpath "$cmd_alias")" == "$(lb_realpath "$lb_current_script")" ] ; then
			# quit
			return $lb_exitcode
		fi
	fi

	# (re)create link
	ln -s -f "$current_script" "$cmd_alias" &> /dev/null
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


# Uninstall time2backup
# Usage: t2b_uninstall [OPTIONS]
t2b_uninstall() {

	# default options
	local delete_config=false
	local delete_files=false
	local force_mode=false

	# get options
	while [ -n "$1" ] ; do
		case $1 in
			-y|--yes)
				force_mode=true
				;;
			-c|--delete-config)
				delete_config=true
				;;
			-x|--delete-files)
				delete_files=true
				;;
			-h|--help)
				print_help
				return 0
				;;
			-*)
				print_help
				return 1
				;;
			*)
				break
				;;
		esac
		shift # load next argument
	done

	# confirm action
	if ! $force_mode ; then
		if ! lb_yesno "Uninstall time2backup?" ; then
			return 0
		fi
	fi

	echo "Uninstall time2backup..."

	# delete cron job
	if ! crontab_config disable &> /dev/null ; then
		lb_error "Failed to remove cron job(s). Please remove them manually."
		lb_exitcode=3
	fi

	# delete desktop file (Linux)
	application_link=/usr/share/applications/time2backup.desktop

	# delete desktop file
	if [ -f "$application_link" ] ; then
		rm -f "$application_link"
		if [ $? != 0 ] ; then
			lb_error "Failed to remove application link."
			lb_error "Please retry in sudo, or run the following command:"
			lb_error "   sudo rm -f \"$application_link\""
			lb_exitcode=4
		fi
	fi

	# delete alias if exists
	if [ -e "$cmd_alias" ] ; then
		rm -f "$cmd_alias"
		if [ $? != 0 ] ; then
			lb_error "Failed to remove command alias."
			lb_error "Please retry in sudo, or run the following command:"
			lb_error "   sudo rm -f \"$cmd_alias\""
			lb_exitcode=5
		fi
	fi

	# delete .install file
	rm -f "$script_directory/config/.install" #&> /dev/null

	# delete configuration
	if $delete_config ; then
		rm -rf "$config_directory"
		if [ $? != 0 ] ; then
			lb_error "Failed to delete config directory."
			lb_exitcode=6
		fi
	fi

	# delete files
	if $delete_files ; then
		rm -rf "$script_directory"
		if [ $? != 0 ] ; then
			lb_error "Failed to delete time2backup directory."
			lb_exitcode=7
		fi
	fi

	# simple print
	if [ $lb_exitcode == 0 ] || [ $lb_exitcode == 5 ] ; then
		echo
		echo "time2backup is uninstalled"
	fi

	# we quit as soon as possible (do not use libbash that may be already deleted)
	exit $lb_exitcode
}
