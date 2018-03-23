#
#  time2backup commands
#
#  This file is part of time2backup (https://time2backup.org)
#
#  MIT License
#  Copyright (c) 2017-2018 Jean Prunneaux
#

# Index of functions
#
#   t2b_backup
#   t2b_restore
#   t2b_history
#   t2b_explore
#   t2b_status
#   t2b_stop
#   t2b_mv
#   t2b_clean
#   t2b_config
#   t2b_install
#   t2b_uninstall


# Perform backup
# Usage: t2b_backup [OPTIONS] [PATH...]
t2b_backup() {

	# default values and options
	recurrent_backup=false
	source_ssh=false
	force_unlock=false
	local quiet_mode=false

	# get options
	while [ $# -gt 0 ] ; do
		case $1 in
			-p|--progress)
				files_progress=true
				;;
			-u|--unmount)
				force_unmount=true
				unmount=true
				;;
			-s|--shutdown)
				shutdown=true
				;;
			-r|--recurrent)
				recurrent_backup=true
				;;
			--force-lock|--force-unlock)
				force_unlock=true
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

	# specified source(s)
	while [ $# -gt 0 ] ; do
		sources+=("$1")
		shift
	done

	# if not specified, get sources from config file
	if [ ${#sources[@]} == 0 ] ; then

		if ! lb_read_config "$config_sources" ; then
			lbg_error "Cannot read sources.conf file!"
			clean_exit 3
		fi

		sources=("${lb_read_config[@]}")
	fi

	# if no sources to backup, exit
	if [ ${#sources[@]} == 0 ] ; then
		lbg_warning "$tr_nothing_to_backup\n$tr_please_configure_sources"
		clean_exit 4
	fi

	# get current date
	start_timestamp=$(date +%s)
	current_date=$(lb_timestamp2date -f '%Y-%m-%d at %H:%M:%S' $start_timestamp)

	# set backup directory with current date (format: YYYY-MM-DD-HHMMSS)
	backup_date=$(lb_timestamp2date -f '%Y-%m-%d-%H%M%S' $start_timestamp)

	# get last backup file
	last_backup_file=$config_directory/.lastbackup

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
			clean_exit 20
		fi

		# recurrent backups not enabled in configuration
		if ! $recurrent ; then
			lb_warning "Recurrent backups are disabled. You can enable it in configuration file."
			clean_exit 20
		fi

		# if cannot get last timestamp, cancel (avoid to backup every minute)
		if ! [ -w "$last_backup_file" ] ; then
			lb_display_error "Cannot get/save the last backup timestamp."
			clean_exit 21
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
			test_timestamp=$(($start_timestamp - $last_backup_timestamp))

			if [ $test_timestamp -gt 0 ] ; then
				if [ $test_timestamp -le $seconds_offset ] ; then
					lb_debug "Last backup was done at $(lb_timestamp2date -f "$tr_readable_date" $last_backup_timestamp), we are now $(lb_timestamp2date -f "$tr_readable_date" $start_timestamp) (backup every $(($seconds_offset / 60)) minutes)"
					lb_info "Recurrent backup: no need to backup."

					# exit without email or shutdown or delete log (does not exists)
					return 0
				fi
			else
				lb_display_critical "Last backup is more recent than today. Are you a time traveller?"
			fi
		fi
	fi # recurrent backups

	# execute before backup command/script
	run_before

	# prepare destination (mount and verify writable)
	prepare_destination
	case $? in
		1)
			# destination not reachable
			if ! $recurrent_backup ; then
				lbg_error "$tr_backup_unreachable\n$tr_verify_media"
			fi
			clean_exit 6
			;;
		2)
			# destination not writable
			clean_exit 7
			;;
	esac

	# test if a backup is running
	existing_lock=$(ls "$destination/.lock_"* 2> /dev/null)
	if [ -n "$existing_lock" ] ; then

		lb_warning "Backup lock found: $(basename "$existing_lock")"

		# force mode: delete old lock
		if $force_unlock ; then
			lb_info "Force mode: deleting lock"
			rm -f "$existing_lock"
		else
			false
		fi

		# if no force mode or failed to delete lock
		if [ $? != 0 ] ; then
			# print error message
			lb_display_error "$tr_backup_already_running"
			if ! $recurrent_backup && ! $console_mode ; then
				lbg_error "$tr_backup_already_running"
			fi
			clean_exit 8
		fi
	fi

	create_lock

	# catch term signals
	trap cancel_exit SIGHUP SIGINT SIGTERM

	# set log file path
	logfile=$logs_directory/time2backup_$backup_date.log

	# create log file and exit if error
	create_logfile "$logfile" || clean_exit 9

	lb_display --log "Backup started on $current_date\n"

	# set new backup directory
	dest=$destination/$backup_date

	notify "$tr_notify_prepare_backup"
	lb_display --log "Prepare backup destination..."

	# if mirror mode and there is an old backup, move last backup to current directory
	last_backup=$(get_backups | tail -1)
	if $mirror_mode && [ -n "$last_backup" ] ; then
		mv "$destination/$last_backup" "$dest"
	else
		# create destination
		mkdir "$dest"
	fi

	# if failed to move or to create
	if [ $? != 0 ] ; then
		lb_display_error --log "Could not prepare backup destination. Please verify your access rights."
		clean_exit 7
	fi

	# prepare rsync command
	prepare_rsync backup

	# create the info file
	infofile=$dest/backup.info
	echo "[time2backup]
version = $version
os = $lb_current_os
recurrent = $recurrent_backup

[destination]
path = $destination
date = $backup_date
hard_links = $hard_links" > "$infofile"

	# execute backup for each source
	# do a loop like this to prevent errors with spaces in strings
	# do not use for ... in ... syntax
	for ((s=0; s < ${#sources[@]}; s++)) ; do

		src=${sources[s]}
		estimated_time=""

		lb_display --log "\n********************************************\n"
		lb_display --log "Backup $src... ($(($s + 1))/${#sources[@]})\n"

		lb_display --log "Preparing backup..."

		# save current timestamp
		src_timestamp=$(date +%s)

		# source path checksum
		if [ "$lb_current_os" == macOS ] ; then
			src_checksum=$(echo "$src" | md5)
		else
			src_checksum=$(echo "$src" | md5sum | awk '{print $1}')
		fi

		# write to info file
		echo -e "\n[$src_checksum]\npath = $src" >> "$infofile"

		# get source path
		protocol=$(get_protocol "$src")
		case $protocol in
			ssh)
				# test if we don't have double remotes
				# (rsync does not support ssh to ssh copy)
				if $remote_destination ; then
					lb_display_error --log "You cannot backup a distant path to a distant path."
					errors+=("$src (cannot backup a distant path on a distant destination)")
					lb_exitcode=3
					continue
				fi

				source_ssh=true

				# get full backup path
				path_dest=$(get_backup_path "$src")

				# get server path from URL
				abs_src=$(url2ssh "$src")
				;;

			*)
				# file or directory

				# remove file:// prefix
				if [ "${src:0:7}" == "file://" ] ; then
					src=${src:7}
				fi

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
						done

						# then complete by \{user}
						homedir=$homedir/$homeuser

						lb_debug "Windows homedir: $homedir"

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

				# get UNIX format for Windows paths
				if [ "$lb_current_os" == Windows ] ; then
					src=$(cygpath "$src")
				fi

				# get absolute path for source
				abs_src=$(lb_abspath "$src")

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
		finaldest=$dest/$path_dest

		# create parent destination folder
		mkdir -p "$(dirname "$finaldest")"
		prepare_dest=$?

		if [ $prepare_dest == 0 ] ; then
			# reset last backup date
			last_clean_backup=""
			last_clean_backup_linkdest=""

			# find the last backup of this source (non empty)
			if [ -n "$last_backup" ] ; then
				last_clean_backup=$(get_backup_history -n -l "$src")
				lb_debug --log "Last backup used for link/trash: $last_clean_backup"
			fi

			if [ -n "$last_clean_backup" ] && ! $remote_destination ; then

				# default behaviour: mkdir or mv destination
				if $hard_links ; then
					mv_dest=false
				else
					mv_dest=true
				fi

				# load last backup info
				last_backup_info=$destination/$last_clean_backup/backup.info

				if [ -f "$last_backup_info" ] ; then
					estimated_time=$(lb_get_config -s $src_checksum "$last_backup_info" duration)

					# if bad result, reset it
					lb_is_integer $estimated_time || estimated_time=""

					# check status of the last backup
					if $hard_links ; then
						# if last backup failed or was cancelled
						rsync_result $(lb_get_config -s $src_checksum "$last_backup_info" rsync_result)

						if [ $? == 2 ] ; then
							lb_debug "Resume from failed backup: $last_clean_backup"

							# search again for the last clean backup before that
							for b in $(get_backup_history -n "$src" | head -2) ; do
								# ignore the current last backup
								[ "$b" == "$last_clean_backup" ] && continue

								last_clean_backup_linkdest=$b
								break
							done

							mv_dest=true
						fi
					fi
				fi

				if $mv_dest ; then
					# move old backup as current backup
					mv "$destination/$last_clean_backup/$path_dest" "$(dirname "$finaldest")"
					prepare_dest=$?

					# clean old directory if empty
					clean_empty_directories "$(dirname "$destination/$last_clean_backup/$path_dest")"

					# change last clean backup for hard links
					if $hard_links ; then
						if [ -n "$last_clean_backup_linkdest" ] ; then
							lb_debug "Last backup used for links: $last_clean_backup_linkdest"
							last_clean_backup=$last_clean_backup_linkdest
						else
							# if no older link, reset it
							last_clean_backup=""
						fi
					fi
				else
					# create destination
					mkdir "$finaldest"
					prepare_dest=$?
				fi
			fi
		fi

		# if mkdir (hard links mode) or mv (trash mode) failed,
		if [ $prepare_dest != 0 ] ; then
			lb_display_error --log "Could not prepare backup destination for source $src. Please verify your access rights."

			# prepare report and save exit code
			errors+=("$src (write error)")
			[ $lb_exitcode == 0 ] && lb_exitcode=7

			# clean final destination directory
			clean_empty_directories "$finaldest"

			# continue to next source
			continue
		fi

		# display start notification
		notification_started_backup=$tr_backup_in_progress
		if [ ${#sources[@]} -gt 1 ] ; then
			notification_started_backup+=" ($(($s + 1))/${#sources[@]})"
		fi

		# display estimated time
		if [ -n "$estimated_time" ] ; then
			info_estimated_time=$(printf "$tr_estimated_time" $estimated_time)

			lb_info "$info_estimated_time"

			notification_started_backup+="\n$info_estimated_time"
		fi

		notify "$notification_started_backup"

		# define rsync command
		cmd=("${rsync_cmd[@]}")

		if ! $mirror_mode ; then
			# if first backup, no need to add incremental options
			if [ -n "$last_clean_backup" ] ; then
				# if destination supports hard links, use incremental with hard links system
				if $hard_links ; then
					# revision folder
					linkdest=$(get_relative_path "$finaldest" "$destination")
					if [ -e "$linkdest" ] ; then
						cmd+=(--link-dest="$linkdest/$last_clean_backup/$path_dest")

						echo "trash = $last_clean_backup" >> "$infofile"
					fi
				else
					# backups with a "trash" folder that contains older revisions
					# be careful that trash must be set to parent directory
					# or it will create something like dest/src/src
					trash=$destination/$last_clean_backup/$path_dest

					# create trash
					mkdir -p "$trash"

					# move last destination
					cmd+=(-b --backup-dir "$trash")

					echo "trash = $last_clean_backup" >> "$infofile"
				fi
			fi
		fi

		# set a bad result to detect cancelled or interrupted backups
		echo "rsync_result = -1" >> "$infofile"

		# of course, we exclude the backup destination itself if it is included
		# into the backup source
		# e.g. to backup /media directory, we must exclude /user/device/path/to/backups
		exclude_backup_dir=$(auto_exclude "$abs_src")
		if [ $? == 0 ] ; then
			# if there is something to exclude, do it
			if [ -n "$exclude_backup_dir" ] ; then
				cmd+=(--exclude "$exclude_backup_dir")
			fi
		else
			errors+=("$src (exclude error)")
			lb_exitcode=11

			# cleanup
			clean_empty_directories "$finaldest"

			# continue to next source
			continue
		fi

		# search in source if exclude conf file is set
		if [ -f "$abs_src/.rsyncignore" ] ; then
			cmd+=(--exclude-from="$abs_src/.rsyncignore")
		fi

		if $source_ssh ; then
			# network compression
			if $network_compression ; then
				cmd+=(-z)
			fi

			# add ssh options
			if [ -n "$ssh_options" ] ; then
				cmd+=(-e "$ssh_options")
			else
				# if empty, defines ssh
				cmd+=(-e ssh)
			fi

			# rsync distant path option
			if [ -n "$rsync_remote_path" ] ; then
				cmd+=(--rsync-path "$rsync_remote_path")
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

			# test rsync and space available for backup
			if ! test_backup ; then
				lb_display --log "Error in rsync test."

				# prepare report and save exit code
				errors+=("$src (rsync test error)")
				[ $lb_exitcode == 0 ] && lb_exitcode=12

				clean_empty_directories "$finaldest"

				# continue to the next backup source
				continue
			fi

			# if not enough space on disk to backup, cancel
			if ! test_free_space ; then
				lb_display_error --log "Not enough space on device to backup. Abording."

				# prepare report and save exit code
				errors+=("$src (not enough space left)")
				[ $lb_exitcode == 0 ] && lb_exitcode=13

				clean_empty_directories "$finaldest"

				# continue to next source
				continue
			fi
		fi # end of free space tests

		lb_display --log "\nRunning backup..."
		lb_debug --log "Executing: ${cmd[*]}\n"

		# real backup: execute rsync command, print result into terminal and logfile
		"${cmd[@]}" 2> >(tee -a "$logfile" >&2)

		# get backup result and prepare report
		res=${PIPESTATUS[0]}

		# save rsync result in info file and delete temporary file
		lb_set_config "$infofile" rsync_result $res && \
		rm -f "$infofile~" &> /dev/null

		if [ $res == 0 ] ; then
			# backup succeeded
			# (ignoring vanished files in transfer)
			success+=("$src")
		else
			# determine between warnings and errors
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

		# save duration in minutes (rounded upper)
		echo "duration = $((($(date +%s) - $src_timestamp) / 60 + 1))" >> "$infofile"

		# clean empty backup if nothing inside
		clean_empty_directories "$finaldest"

	done # end of backup sources

	lb_display --log "\n********************************************\n"

	# if destination disappered (e.g. network folder disconnected),
	# return a critical error
	if ! [ -d "$destination" ] ; then
		errors+=("Destination folder vanished! Disk or network may have been disconnected.")
		lb_exitcode=14
	else
		# final cleanup
		clean_empty_directories "$dest"

		# if destination was not empty, rotate backups
		if [ -d "$dest" ] ; then
			rotate_backups
		else
			# if nothing was backuped, consider it as a critical error
			# and do not rotate backups
			errors+=("Nothing was backuped.")
			lb_exitcode=14
		fi
	fi

	# if backup succeeded (all OK or even if warnings)
	case $lb_exitcode in
		0|5|15)
			lb_debug --log "Save backup timestamp"

			# save current timestamp into config/.lastbackup file
			date +%s > "$last_backup_file"
			if [ $? != 0 ] ; then
				lb_display_error --log "Failed to save backup date! Please check your access rights on the config directory or recurrent backups won't work."
			fi

			# create a latest link to the last backup directory
			lb_debug --log "Create latest link..."

			# create a new link
			# in a sub-context to avoid confusion and do not care of output
			if [ "$lb_current_os" == Windows ] ; then
				dummy=$(cd "$destination" 2> /dev/null && rm -f latest && cmd /c mklink /j latest "$backup_date")
			else
				dummy=$(cd "$destination" 2> /dev/null && rm -f latest && ln -s "$backup_date" latest 2> /dev/null)
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
					# release lock now, do not wait until user closes the window!
					release_lock
					lbg_info "$tr_backup_finished\n$(report_duration)"
				fi
			else
				notify "$tr_backup_finished\n$(report_duration)"
			fi
		fi

	else
		lb_display --log "Backup finished with some errors. Check report below and see log files for more details.\n"

		if [ ${#success[@]} -gt 0 ] ; then
			report_details+="
Success:
"
			for i in "${success[@]}" ; do
				report_details+="   - $i
"
			done
		fi

		if [ ${#warnings[@]} -gt 0 ] ; then
			report_details+="
Warnings:
"
			for i in "${warnings[@]}" ; do
				report_details+="   - $i
"
			done

			if $notifications ; then
				# do not display warning message if there are critical errors to come after that
				if [ ${#errors[@]} == 0 ] ; then
					fail_message="$tr_backup_finished_warnings $tr_see_logfile_for_details\n$(report_duration)"

					# Windows: display dialogs instead of notifications
					if [ "$lb_current_os" == Windows ] ; then
						# do not popup dialog that would prevent PC from shutdown
						if ! $shutdown ; then
							# release lock now, do not wait until user closes the window!
							release_lock
							lbg_warning "$fail_message"
						fi
					else
						notify "$fail_message"
					fi
				fi
			fi
		fi

		if [ ${#errors[@]} -gt 0 ] ; then
			report_details+="
Errors:
"
			for i in "${errors[@]}" ; do
				report_details+="   - $i
"
			done

			if $notifications ; then
				fail_message="$tr_backup_failed $tr_see_logfile_for_details\n$(report_duration)"

				# Windows: display dialogs instead of notifications
				if [ "$lb_current_os" == Windows ] ; then
					# do not popup dialog that would prevent PC from shutdown
					if ! $shutdown ; then
						# release lock now, do not wait until user closes the window!
						release_lock
						lbg_error "$fail_message"
					fi
				else
					notify "$fail_message"
				fi
			fi
		fi

		lb_display --log "$report_details"
	fi

	# execute custom after backup script
	run_after

	clean_exit
}


# Restore a file
# Usage: t2b_restore [OPTIONS] [PATH]
t2b_restore() {

	# default option values
	backup_date=latest
	force_mode=false
	choose_date=true
	directory_mode=false
	restore_moved=false
	delete_newer_files=false
	local quiet_mode=false

	# get options
	while [ $# -gt 0 ] ; do
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
			--delete-new)
				delete_newer_files=true
				;;
			-p|--progress)
				files_progress=true
				;;
			-f|--force)
				force_mode=true
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

	# test backup destination
	prepare_destination || return 4

	# get all backups
	backups=($(get_backups))
	# if no backups, exit
	if [ ${#backups[@]} == 0 ] ; then
		lbg_error "$tr_no_backups_available"
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
				;;
			2)
				# restore a moved file
				starting_path=$destination
				restore_moved=true
				;;
			3)
				# restore a directory
				directory_mode=true
				;;
			4)
				# restore a moved directory
				starting_path=$destination
				directory_mode=true
				restore_moved=true
				;;
			*)
				return 1
				;;
		esac

		# choose a directory
		if $directory_mode ; then
			lbg_choose_directory -t "$tr_choose_directory_to_restore" "$starting_path"
			case $? in
				0)
					# continue
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
			file=$lbg_choose_directory/

		else
			# choose a file
			lbg_choose_file -t "$tr_choose_file_to_restore" "$starting_path"
			case $? in
				0)
					# continue
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
			if [[ "$file" != "$destination"* ]] ; then
				lbg_error "$tr_path_is_not_backup"
				return 1
			fi

			# remove destination path prefix
			file=${file#$destination}
			# remove first slash
			if [ "${file:0:1}" == "/" ] ; then
				file=${file:1}
			fi

			# get backup date
			backup_date=$(echo $file | grep -oE "^$backup_date_format")
			if [ -z "$backup_date" ] ; then
				lbg_error "$tr_path_is_not_backup"
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
				lbg_error "$tr_path_is_not_backup"
				lb_error "Restoring ssh/network files is not supported yet."
				return 12
			fi

			# absolute path of destination
			file=${file:6}
		fi
	else
		# get specified path
		file=$*

		# detect directory mode (useful for deleted directories)
		if [ "${file:${#file}-1}" == "/" ] ; then
			directory_mode=true
		fi

		# get UNIX format for Windows paths
		if [ "$(get_protocol "$file")" == files ] && [ "$lb_current_os" == Windows ] ; then
			file=$(cygpath "$file")
			if $directory_mode ; then
				file+="/"
			fi
		fi
	fi

	# case of symbolic links
	if [ -L "$file" ] ; then
		lbg_error "$tr_cannot_restore_links"
		return 12
	fi

	# if it is a directory, add '/' at the end of the path
	if [ -d "$file" ] ; then
		if [ "${file:${#file}-1}" != "/" ] ; then
			file+="/"
		fi
	fi

	lb_debug "Path to restore: $file"

	# get backup full path
	backup_file_path=$(get_backup_path "$file")

	# if error, exit
	[ -z "$backup_file_path" ] && return 1

	# get all versions of the file/directory
	file_history=($(get_backup_history "$file"))

	# if no backup found
	if [ ${#file_history[@]} == 0 ] ; then
		lbg_error "$tr_no_backups_for_file"
		return 6
	fi

	# search for dates
	if [ "$backup_date" != latest ] ; then
		# if date was specified but not here, error
		if ! lb_array_contains "$backup_date" "${file_history[@]}" ; then
			lbg_error "$tr_no_backups_on_date\n$tr_run_to_show_history $lb_current_script history $file"
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
				history_dates[$i]=$(get_backup_fulldate "${file_history[i]}")
			done

			# choose backup date
			lbg_choose_option -d 1 -l "$tr_choose_backup_date" "${history_dates[@]}"
			case $? in
				0)
					# continue
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
			backup_date=${file_history[$lbg_choose_option-1]}
		fi
	fi

	# if latest backup wanted, get most recent date
	if [ "$backup_date" == latest ] ; then
		backup_date=${file_history[0]}
	fi

	# set backup source for restore command
	src=$destination/$backup_date/$backup_file_path

	# if source is a directory
	if [ -d "$src" ] ; then
		# trash mode: cannot restore directories
		if ! $hard_links ; then
			lbg_error "$tr_cannot_restore_from_trash"
			return 12
		else
			# enable directory mode
			directory_mode=true
		fi
	fi

	# prepare destination path
	case $(get_protocol "$file") in
		ssh)
			dest=$(url2ssh "$file")
			;;
		*)
			dest=$file
			;;
	esac

	# warn user if incomplete backup of directory
	if $directory_mode ; then
		infofile=$destination/$backup_date/backup.info
		if [ -f "$infofile" ] ; then
			# search sections
			for section in $(grep -Eo "^\[.*\]" "$infofile" 2> /dev/null | grep -v destination | tr -d '[]') ; do
				# if current path
				if [[ "$dest" == "$(lb_get_config -s $section "$infofile" path)"* ]] ; then
					# and rsync result was not good
					if [ "$(lb_get_config -s $section "$infofile" rsync_result)" != 0 ] ; then
						# warn user
						if ! lbg_yesno "$tr_warn_restore_partial\n$tr_confirm_restore_2" ; then
							return 0
						fi
					fi
					break
				fi
			done
		fi
	fi

	# catch term signals
	trap cancel_exit SIGHUP SIGINT SIGTERM

	# prepare rsync command
	prepare_rsync restore

	# of course, we exclude the backup destination itself if it is included
	# into the destination path
	# e.g. to restore /media directory, we must exclude /user/device/path/to/backups
	exclude_backup_dir=$(auto_exclude "$dest")
	if [ $? == 0 ] ; then
		# if there is something to exclude, do it
		if [ -n "$exclude_backup_dir" ] ; then
			rsync_cmd+=(--exclude "$exclude_backup_dir")
		fi
	else
		lbg_error "$tr_restore_unknown_error"
		return 8
	fi

	# search in source if exclude conf file is set
	if [ -f "$src/.rsyncignore" ] ; then
		rsync_cmd+=(--exclude-from="$src/.rsyncignore")
	fi

	# test newer files
	if ! $delete_newer_files ; then
		if $directory_mode ; then
			# prepare test command
			cmd=("${rsync_cmd[@]}")
			cmd+=(--delete --dry-run "$src" "$dest")

			notify "$tr_notify_prepare_restore"
			echo "Preparing restore..."
			lb_debug "${cmd[*]}"

			# test rsync to check newer files
			"${cmd[@]}" | grep -q "^deleting "

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
			notify "$tr_restore_cancelled"
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

	# set log file path
	logfile="$logs_directory/restore_$(date '+%Y-%m-%d-%H%M%S').log"

	# create log file for errors
	if ! create_logfile "$logfile" ; then
		lb_warning "Cannot create log file. If there are errors, you will not be able to check them easely."
	fi

	lb_display --log "Restore $(lb_abspath "$dest") from backup $backup_date...\n"
	lb_debug --log "Executing: ${cmd[*]}\n"

	# execute rsync command, print result into terminal and errors in logfile
	"${cmd[@]}" 2> >(tee -a "$logfile" >&2)
	lb_result
	local res=$?

	# if no errors,
	if [ $res == 0 ] ; then
		# delete logfile, print info and quit
		rm -f "$logfile" &> /dev/null
		lbg_info "$tr_restore_finished"
		return 0
	fi

	# if the was errors,
	if rsync_result $res ; then
		# rsync minor errors (partial transfers)
		lbg_warning "$tr_restore_finished_warnings"
		res=10
	else
		# rsync critical error: open logfile and print message
		if [ -r "$logfile" ] ; then
			open_config "$logfile" &> /dev/null &
		fi
		lbg_error "$tr_restore_failed"
		res=9
	fi

	# open logfile if exists and is readable
	if [ -e "$logfile" ] && [ -r "$logfile" ] ; then
		open_config "$logfile" &> /dev/null &
	fi

	return $res
}


# Get history/versions of a file
# Usage: t2b_history [OPTIONS] PATH
t2b_history() {

	# default option values
	local history_opts=""
	local quiet_mode=false

	# get options
	while [ $# -gt 0 ] ; do
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
	prepare_destination || return 4

	# get file
	if [ "$lb_current_os" == Windows ] ; then
		# get UNIX format for Windows paths
		file=$(cygpath "$*")
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
	for b in "${file_history[@]}" ; do
		# quiet mode: just print the version
		if $quiet_mode ; then
			echo "$b"
		else
			# complete result: print details
			abs_file=$(get_backup_path "$file")
			[ -z "$abs_file" ] && continue

			backup_file=$destination/$b/$abs_file

			echo

			# get number of files
			nb_files=$(ls -l "$backup_file" 2> /dev/null | wc -l)

			if [ -n "$nb_files" ] ; then
				if [ $nb_files -gt 1 ] ; then
					nb_files=$(($nb_files - 1))
					echo "$b: $nb_files file(s)"
				else
					echo "$b: $nb_files file"
				fi
			fi

			# print details of file/directory
			echo "$(cd "$(dirname "$backup_file")" && ls -l "$(basename "$backup_file")" 2> /dev/null)"
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
	backup_date=""
	local explore_all=false

	# get options
	while [ $# -gt 0 ] ; do
		case $1 in
			-d|--date)
				if [ -z "$2" ] ; then
					print_help
					return 1
				fi
				backup_date=$2
				shift
				;;
			-l|--latest)
				backup_date=latest
				;;
			-a|--all)
				explore_all=true
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

	path=$*

	if $console_mode ; then
		echo "This command is not available in console mode."
		return 255
	fi

	if $remote_destination ; then
		echo "This command is disabled for remote destinations."
		return 255
	fi

	# if path specified, test it
	if [ -n "$path" ] ; then
		if ! [ -e "$path" ] ; then
			print_help
			return 1
		fi
	fi

	# test backup destination
	prepare_destination || return 4

	# if path is not specified, open the backup destination folder
	if [ -z "$path" ] ; then
		echo "Exploring backups..."
		lbg_open_directory "$destination"

		if [ $? == 0 ] ; then
			return 0
		else
			return 8
		fi
	fi

	# get all backups
	backups=($(get_backups))
	# if no backups, exit
	if [ ${#backups[@]} == 0 ] ; then
		lbg_error "$tr_no_backups_available"
		return 5
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
		lbg_error "$tr_no_backups_for_file"
		return 6
	fi

	# if backup date is specified,
	if [ -n "$backup_date" ] ; then
		# get the latest one
		if [ "$backup_date" == latest ] ; then
			backup_date=${path_history[0]}
		else
			# test if specified date exists
			if ! lb_array_contains "$backup_date" "${path_history[@]}" ; then
				lbg_error "$tr_no_backups_on_date\n$tr_run_to_show_history $lb_current_script history $path"
				return 7
			fi
		fi

	else
		# explore all backups
		if $explore_all ; then
			# warn user if displaying many folders
			if [ ${#path_history[@]} -ge 10 ] ; then
				if ! lbg_yesno "Warning: You are about to open ${#path_history[@]} windows! Are you sure to continue?" ; then
					return 0
				fi
			fi
			backup_date=${path_history[@]}

		else
			# if only one backup, no need to choose one
			if [ ${#path_history[@]} == 1 ] ; then
				backup_date=${path_history[0]}
			else
				# prompt user to choose a backup date

				# change dates to a user-friendly format
				history_dates=(${path_history[@]})

				for ((i=0; i<${#path_history[@]}; i++)) ; do
					history_dates[$i]=$(get_backup_fulldate "${path_history[i]}")
				done

				# choose backup date
				lbg_choose_option -d 1 -l "$tr_choose_backup_date" "${history_dates[@]}"
				case $? in
					0)
						# continue
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
				backup_date=${path_history[$lbg_choose_option-1]}
			fi
		fi
	fi

	if ! [ -d "$path" ] ; then
		backup_path=$(dirname "$backup_path")
	fi

	for b in "${backup_date[@]}" ; do
		echo "Exploring backup $b..."
		lbg_open_directory "$destination/$b/$backup_path"
	done

	if [ $? != 0 ] ; then
		return 8
	fi
}


# Check if a backup is currently running
# Usage: t2b_status [OPTIONS]
t2b_status() {

	# default option values
	local quiet_mode=false

	# get options
	while [ $# -gt 0 ] ; do
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
	if ! prepare_destination &> /dev/null ; then
		if ! $quiet_mode ; then
			echo "backup destination not reachable"
		fi
		return 4
	fi

	# if no backup lock exists, exit
	if ! current_lock &> /dev/null ; then
		if ! $quiet_mode ; then
			echo "backup is not running"
		fi
		return 0
	fi

	# search for a t2b PID
	local t2b_pids=($(ps -ef | grep time2backup | awk '{print $2}'))

	for pid in "${t2b_pids[@]}" ; do
		# if current script, continue
		[ $pid == $$ ] && continue

		if ! $quiet_mode ; then
			echo "backup is running with PID $pid"
		fi
		return 5
	done

	# if no t2b process found,
	if ! $quiet_mode ; then
		echo "backup lock is here, but there is no rsync command currently running"
	fi
	return 6
}


# Stop a running backup
# Usage: t2b_stop [OPTIONS]
t2b_stop() {

	# default options and values
	local force_mode=false
	local quiet_mode=false
	local pid_killed=false

	# get options
	while [ $# -gt 0 ] ; do
		case $1 in
			-f|--force)
				force_mode=true
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

	# check status of backup
	t2b_status &> /dev/null

	# if no backup is running or error, cannot stop
	case $? in
		0)
			if ! $quiet_mode ; then
				echo "backup is not running"
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
				echo "backup destination not reachable"
			fi
			return 4
			;;
		6)
			if ! $quiet_mode ; then
				echo "backup lock is here, but there is no rsync command currently running"
			fi
			return 7
			;;
	esac

	# prompt confirmation
	if ! $force_mode ; then
		if ! lb_yesno "Are you sure you want to interrupt the current backup?" ; then
			return 0
		fi
	fi

	# search for a current rsync command and get parent PIDs
	rsync_ppids=($(ps -ef | grep "$rsync_path" | head -1 | awk '{print $2}'))

	for pid in "${rsync_ppids[@]}" ; do
		# get parent PID
		parent_pid=$(ps -f $pid 2> /dev/null | tail -1 | awk '{print $3}')
		[ -z "$parent_pid" ] && continue

		# check if parent process is an instance of time2backup
		ps -f $parent_pid 2> /dev/null | grep -q time2backup
		if [ $? == 0 ] ; then
			# send to t2b THEN rsync subprocess the kill signal
			kill $parent_pid $pid && pid_killed=true
			break
		fi
	done

	# if no rsync process found, quit
	if ! $pid_killed ; then
		if ! $quiet_mode ; then
			echo "Cannot found rsync PID"
		fi
		return 7
	fi

	# wait 30 sec max until time2backup is really stopped
	for i in $(seq 1 30) ; do
		if t2b_status &> /dev/null ; then
			if ! $quiet_mode ; then
				echo "time2backup was successfully cancelled"
			fi
			return 0
		fi
		sleep 1
	done

	if ! $quiet_mode ; then
		echo "Still running! Could not stop time2backup process. You may retry in sudo."
	fi
	return 5
}


# Move backup files
# Usage: t2b_mv [OPTIONS] PATH
t2b_mv() {

	# default option values
	local force_mode=false
	local quiet_mode=false

	# get options
	while [ $# -gt 0 ] ; do
		case $1 in
			-f|--force)
				force_mode=true
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
	if lb_test_arguments -lt 2 $* ; then
		print_help
		return 1
	fi

	if $remote_destination ; then
		lb_error "This command is disabled for remote destinations."
		return 255
	fi

	# test backup destination
	prepare_destination || return 4

	if [ "$lb_current_os" == Windows ] ; then
		# get UNIX format for Windows paths
		src=$(cygpath "$1")
		dest=$(cygpath "$2")
	else
		src=$1
		dest=$2
	fi

	# get all backup versions of this file
	file_history=$(get_backup_history -l "$src")

	# no backup found
	if [ -z "$file_history" ] ; then
		lb_error "No backup found for '$src'!"
		return 5
	fi

	# get path of file
	abs_src=$(get_backup_path "$src")
	if [ $? != 0 ] ; then
		lb_error "Cannot determine the backup path of your source."
		return 6
	fi

	# get path of new file
	abs_dest=$(get_backup_path "$dest")
	if [ $? != 0 ] ; then
		lb_error "Cannot determine the backup path of your destination. Please retry with an absolute path."
		return 6
	fi

	# confirm action
	if ! $force_mode ; then
		if ! $quiet_mode ; then
			echo "You are about to move backup '$1' to '$2'."
		fi

		# warn user if destination already exists
		if [ -e "$destination/$file_history/$abs_dest" ] ; then
			lb_warning "Destination already exists! This action may erase files."
		fi

		if ! lb_yesno "Do you want to continue?" ; then
			return 0
		fi
	fi

	# move files
	if ! $quiet_mode ; then
		echo "Moving file(s)..."
	fi

	mv "$destination/$file_history/$abs_src" "$destination/$file_history/$abs_dest"
	local mv_res=$?

	if ! $quiet_mode ; then
		lb_result
	fi
	if [ $mv_res != 0 ] ; then
		return 7
	fi
}


# Clean files in backups
# Usage: t2b_clean [OPTIONS] PATH
t2b_clean() {

	# default option values
	local force_mode=false
	local clean_result=0
	local quiet_mode=false

	# get options
	while [ $# -gt 0 ] ; do
		case $1 in
			-f|--force)
				force_mode=true
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

	if $remote_destination ; then
		echo "This command is disabled for remote destinations."
		return 255
	fi

	# test backup destination
	prepare_destination || return 4

	file=$*

	# get all backup versions of this file
	file_history=($(get_backup_history -a "$file"))

	# no backup found
	if [ ${#file_history[@]} == 0 ] ; then
		lb_error "No backup found for '$file'!"
		return 5
	fi

	# confirmation
	if ! $force_mode ; then
		echo "${#file_history[@]} backups were found for this file."
		lb_yesno "Do you really want to delete them?" || return 0
	fi

	# print backup versions
	for b in "${file_history[@]}" ; do
		# get path of file
		abs_file=$(get_backup_path "$file")
		[ -z "$abs_file" ] && continue

		if ! $quiet_mode ; then
			echo "Deleting backup $b..."
		fi

		# delete file(s)
		rm -rf "$destination/$b/$abs_file" || clean_result=6
	done

	return $clean_result
}


# Configure time2backup
# Usage: t2b_config [OPTIONS]
t2b_config() {

	# default values
	file=""
	local op_config=""
	local cmd_opts=""

	# get options
	# following other options to open_config() function
	while [ $# -gt 0 ] ; do
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
			[ -z "$file" ] && file=$config_file

			# get sources is a special case to print list without comments
			# read sources.conf file line by line
			while read -r line ; do
				lb_is_comment $line || echo "$line"
			done < "$file"

			if [ $? != 0 ] ; then
				return 5
			fi
			;;

		test)
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
			open_config $cmd_opts"$file"

			# after config,
			case $? in
				0)
					# config ok: reload it
					load_config || return 3

					# apply config
					apply_config || return 4
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

	# get options
	while [ $# -gt 0 ] ; do
		case $1 in
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

	# create a desktop file (Linux)
	if [ "$lb_current_os" == Linux ] ; then

		desktop_file=$script_directory/time2backup.desktop

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
				echo "You may have to run install command in sudo."
				lb_exitcode=4
			fi
		fi
	fi

	create_link=true

	# if alias already exists,
	if [ -e "$cmd_alias" ] ; then
		# if the same path, do not recreate link
		if [ "$(lb_realpath "$cmd_alias")" == "$(lb_realpath "$lb_current_script")" ] ; then
			create_link=false
		fi
	fi

	# (re)create link
	if $create_link ; then
		ln -s -f "$current_script" "$cmd_alias" &> /dev/null
		if [ $? != 0 ] ; then
			echo
			echo "Cannot create command link. It's not critical, but you may not run time2backup command directly."
			echo "You may have to run install command in sudo, or add an alias in your bashrc file."

			# this exit code is less important
			[ $lb_exitcode == 0 ] && lb_exitcode=4
		fi
	fi

	# copy bash completion script
	cp "$lb_current_script_directory/resources/t2b_completion" /etc/bash_completion.d/time2backup
	if [ $? != 0 ] ; then
		echo
		echo "Cannot install bash completion script. It's not critical, but you can retry in sudo."

		# this exit code is less important
		[ $lb_exitcode == 0 ] && lb_exitcode=5
	fi

	# make completion working in the current session (does not need to create a new one)
	. "$lb_current_script_directory/resources/t2b_completion"

	echo "time2backup is installed"

	return $lb_exitcode
}


# Uninstall time2backup
# Usage: t2b_uninstall [OPTIONS]
t2b_uninstall() {

	# default options
	local delete_files=false
	local force_mode=false

	# get options
	while [ $# -gt 0 ] ; do
		case $1 in
			-y|--yes)
				force_mode=true
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
		lb_yesno "Uninstall time2backup?" || return 0
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
			lb_error "Failed to remove application link.  You may have to run in sudo."
			lb_exitcode=4
		fi
	fi

	# delete alias if exists
	if [ -e "$cmd_alias" ] ; then
		rm -f "$cmd_alias"
		if [ $? != 0 ] ; then
			lb_error "Failed to remove command alias. You may have to run in sudo."
			lb_exitcode=5
		fi
	fi

	# delete files
	if $delete_files ; then
		rm -rf "$script_directory"
		if [ $? != 0 ] ; then
			lb_error "Failed to delete time2backup directory. You may have to run in sudo."
			lb_exitcode=6
		fi
	fi

	# delete bash completion script
	if [ -f /etc/bash_completion.d/time2backup ] ; then
		rm -f /etc/bash_completion.d/time2backup
		if [ $? != 0 ] ; then
			lb_error "Failed to remove bash auto-completion script. You may have to run in sudo."
			lb_exitcode=7
		fi

		# reset completion for current session
		complete -W "" time2backup &> /dev/null
	fi

	# simple print
	if [ $lb_exitcode == 0 ] ; then
		echo
		echo "time2backup is uninstalled"
	fi

	# we quit as soon as possible (do not use libbash that may be already deleted)
	# do not exit with error to avoid crashes in packages removal
	exit
}
