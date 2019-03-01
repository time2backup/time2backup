#
#  time2backup commands
#
#  This file is part of time2backup (https://time2backup.org)
#
#  MIT License
#  Copyright (c) 2017-2019 Jean Prunneaux
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
#   t2b_copy
#   t2b_config
#   t2b_install
#   t2b_uninstall


# Perform backup
# Usage: t2b_backup [OPTIONS] [PATH...]
t2b_backup() {

	# default values and options
	recurrent_backup=false
	local sources=() source_ssh=false force_unlock=false

	# get options
	while [ $# -gt 0 ] ; do
		case $1 in
			-p|--progress)
				files_progress=true
				;;
			-c|--comment)
				backup_comment=$(lb_getopt "$@")
				if [ $? != 0 ] ; then
					print_help
					return 1
				fi
				shift
				;;
			-u|--unmount)
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

	# set specified source(s)
	if [ $# -gt 0 ] ; then
		sources=("$@")
	else
		# if sources not specified, get them from config file
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
	touch "$last_backup_file" || \
		lb_warning "Cannot create last backup file! Verify your right access on config directory."

	# get last backup timestamp
	last_backup_timestamp=$(cat "$last_backup_file" 2> /dev/null | grep -Eo "^[1-9][0-9]*$")

	# if recurrent, check frequency
	if $recurrent_backup ; then

		# if disabled in default configuration
		if ! lb_istrue $enable_recurrent ; then
			lb_display_error "Recurrent backups are disabled."
			clean_exit 20
		fi

		# recurrent backups not enabled in configuration
		if ! lb_istrue $recurrent ; then
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

					fqnum=$(echo $frequency | grep -Eo "^[0-9]*")

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
	[ ${#exec_before[@]} -gt 0 ] && run_before

	# prepare destination (mount and verify writable)
	prepare_destination
	case $? in
		1)
			# destination not reachable: display error if not recurrent backup
			$recurrent_backup || lbg_error "$tr_backup_unreachable\n$tr_verify_media"
			return 6
			;;
		2)
			# destination not writable
			return 7
			;;
	esac

	# test if a backup is running
	local existing_lock
	existing_lock=$(current_lock)
	if [ -n "$existing_lock" ] ; then

		lb_debug "Lock found: $existing_lock"

		# force mode: delete old lock
		if $force_unlock ; then
			lb_info "Force mode: deleting lock $existing_lock"
			release_lock || clean_exit 8
		else
			# print error message
			lb_display_error "$tr_backup_already_running"

			# display window error
			if ! $recurrent_backup && ! lb_istrue $console_mode ; then
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

	# create destination
	mkdir "$dest"
	if [ $? != 0 ] ; then
		lb_display_error --log "Could not prepare backup destination. Please verify your access rights."
		clean_exit 7
	fi

	# prepare rsync command
	prepare_rsync backup

	# force "false" in variable
	lb_istrue $hard_links || hard_links=false

	# create the info file
	infofile=$dest/backup.info
	echo "[time2backup]
version = $version
os = $lb_current_os
hostname = $lb_current_hostname
recurrent = $recurrent_backup
comment = $backup_comment

[destination]
path = $destination
date = $backup_date
hard_links = $hard_links" > "$infofile"

	# prepare results
	local success=() warnings=() errors=()

	# execute backup for each source
	# do a loop like this to prevent errors with spaces in strings
	# do not use for ... in ... syntax
	for ((s=0; s < ${#sources[@]}; s++)) ; do

		src=${sources[s]}
		total_size=""
		estimated_time=""

		lb_display --log "\n********************************************\n"
		lb_display --log "Backup $src... ($(($s + 1))/${#sources[@]})\n"
		lb_display --log "Preparing backup..."

		# save current timestamp
		src_timestamp=$(date +%s)

		# get source path
		protocol=$(get_protocol "$src")
		case $protocol in
			ssh)
				# test if we don't have double remotes
				# (rsync does not support ssh to ssh copy)
				if lb_istrue $remote_destination ; then
					lb_display_error --log "You cannot backup a remote path to a remote destination."
					errors+=("$src (cannot backup a remote path on a remote destination)")
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
				[ "${src:0:7}" == "file://" ] && src=${src:7}

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

					src=$homedir/$(echo "$src" | sed 's/^[^/]*\///')
				fi

				# get UNIX format for Windows paths
				[ "$lb_current_os" == Windows ] && src=$(cygpath "$src")

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

		# write source section to info file
		echo -e "\n[src$(($s + 1))]\npath = $src" >> "$infofile"

		# set final destination with is a representation of system tree
		# e.g. /path/to/my/backups/mypc/2016-12-31-2359/files/home/user/tobackup
		finaldest=$dest/$path_dest

		# create parent destination folder
		mkdir -p "$(dirname "$finaldest")"
		prepare_dest=$?

		if [ $prepare_dest == 0 ] ; then
			# reset last backup date
			real_last_clean_backup=""

			# find the last backup of this source
			last_clean_backup=$(get_backup_history -n -l "$src")
			lb_debug --log "Last backup used for link/trash: $last_clean_backup"

			if [ -n "$last_clean_backup" ] ; then

				# default behaviour: mkdir
				mv_dest=false

				# if mirror mode or trash mode, move destination
				if [ $keep_limit == 0 ] || ! lb_istrue $hard_links ; then
					mv_dest=true
				fi

				# load last backup info
				last_backup_info=$destination/$last_clean_backup/backup.info

				# check status of the last backup
				# (only if infofile exists and in hard links mode)
				if lb_istrue $hard_links && [ -f "$last_backup_info" ] ; then
					# if last backup failed or was cancelled
					rsync_result $(get_infofile_value "$last_backup_info" "$src" rsync_result)

					if [ $? == 2 ] ; then
						lb_debug "Resume from failed backup: $last_clean_backup"

						# search again for the last clean backup before that
						for b in $(get_backup_history -n "$src" | head -2) ; do
							# ignore the current last backup
							[ "$b" == "$last_clean_backup" ] && continue

							real_last_clean_backup=$b
							break
						done

						mv_dest=true
					fi
				fi

				if $mv_dest ; then
					# move old backup as current backup
					mv "$destination/$last_clean_backup/$path_dest" "$(dirname "$finaldest")"
					prepare_dest=$?

					# clean old directory if empty, but keep the infofile
					clean_empty_backup $last_clean_backup "$(dirname "$path_dest")"

					# change last clean backup for hard links
					if lb_istrue $hard_links ; then
						if [ -n "$real_last_clean_backup" ] ; then
							lb_debug "Last backup used for links: $real_last_clean_backup"
							last_clean_backup=$real_last_clean_backup
						else
							# if no older link, reset it
							last_clean_backup=""
						fi
					fi

					# move latest link
					create_latest_link
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

			# clean directory but NOT the infofile
			clean_empty_backup $backup_date "$path_dest"

			# continue to next source
			continue
		fi

		# define rsync command
		cmd=("${rsync_cmd[@]}")

		# if keep_limit = 0, we don't need to use versionning
		# if first backup, no need to add incremental options
		if [ $keep_limit != 0 ] && [ -n "$last_clean_backup" ] ; then
			# if destination supports hard links, use incremental with hard links system
			if lb_istrue $hard_links ; then
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

			# clean directory but NOT the infofile
			clean_empty_backup $backup_date "$path_dest"

			# continue to next source
			continue
		fi

		# search in source if exclude conf file is set
		[ -f "$abs_src"/.rsyncignore ] && cmd+=(--exclude-from="$abs_src"/.rsyncignore)

		# if remote source
		if $source_ssh ; then
			# enables network compression
			lb_istrue $network_compression && cmd+=(-z)

			# add ssh options
			[ -n "$ssh_options" ] && cmd+=(-e "$ssh_options")

			# set rsync distant path
			if [ -n "$rsync_remote_path" ] ; then
				if lb_istrue $remote_sudo ; then
					cmd+=(--rsync-path "sudo $rsync_remote_path")
				else
					cmd+=(--rsync-path "$rsync_remote_path")
				fi
			else
				lb_istrue $remote_sudo && cmd+=(--rsync-path "sudo rsync")
			fi
		fi

		# if it is a directory, add '/' at the end of the path
		[ -d "$abs_src" ] && abs_src=$(remove_end_slash "$abs_src")/

		# add source and destination
		cmd+=("$abs_src" "$finaldest")

		# prepare backup: testing space
		if lb_istrue $test_destination ; then

			# test rsync and space available for backup
			if ! test_backup ; then
				lb_display --log "Error in rsync test."

				# prepare report and save exit code
				errors+=("$src (rsync test error)")
				[ $lb_exitcode == 0 ] && lb_exitcode=12

				# clean directory but NOT the infofile
				clean_empty_backup $backup_date "$path_dest"

				# continue to the next backup source
				continue
			fi

			# if not enough space on disk to backup, cancel
			if ! test_free_space ; then
				lb_display_error --log "Not enough space on device to backup. Abording."

				# prepare report and save exit code
				errors+=("$src (not enough space left)")
				[ $lb_exitcode == 0 ] && lb_exitcode=13

				# clean directory but NOT the infofile
				clean_empty_backup $backup_date "$path_dest"

				# continue to next source
				continue
			fi
		fi # end of free space tests

		lb_display --log "\nRunning backup..."
		lb_debug --log "Executing: ${cmd[*]}\n"

		# display start notification
		notification_started_backup=$tr_backup_in_progress
		if [ ${#sources[@]} -gt 1 ] ; then
			notification_started_backup+=" ($(($s + 1))/${#sources[@]})"
		fi

		# get estimated time
		estimated_time=$(estimate_backup_time "$last_backup_info" "$src" $total_size)
		if [ -n "$estimated_time" ] ; then
			# convert into minutes
			estimated_time=$(($estimated_time / 60 + 1))

			info_estimated_time=$(printf "$tr_estimated_time" $estimated_time)

			# print estimated time in console
			lb_info "$info_estimated_time"
			echo

			notification_started_backup+="\n$info_estimated_time"
		fi

		# display started backup notification
		notify "$notification_started_backup"

		# real backup: execute rsync command, print result into terminal and logfile
		"${cmd[@]}" 2> >(tee -a "$logfile" >&2)

		# get backup result and prepare report
		res=${PIPESTATUS[0]}

		# save rsync result in info file and delete temporary file
		lb_set_config "$infofile" rsync_result $res

		if [ $res == 0 ] ; then
			# backup succeeded
			# (ignoring vanished files in transfer)
			success+=("$src")
		else
			# determine between warnings and errors
			if rsync_result $res ; then
				# rsync minor errors (partial transfers)
				warnings+=("$src (some files were not backed up; code: $res)")
				lb_exitcode=15
			else
				# critical errors that caused backup to fail
				errors+=("$src (backup failed; code: $res)")
				lb_exitcode=14
			fi
		fi

		# clean empty trash and infofile
		clean_empty_backup -i $last_clean_backup "$path_dest"

		# save duration
		echo "duration = $(( $(date +%s) - $src_timestamp ))" >> "$infofile"

		# clean directory WITHOUT infofile
		clean_empty_backup $backup_date "$path_dest"

	done # end of backup sources

	lb_display --log "\n********************************************\n"

	# if destination disappered (e.g. network folder disconnected),
	# return a critical error
	if ! [ -d "$destination" ] ; then
		errors+=("Destination folder vanished! Disk or network may have been disconnected.")
		lb_exitcode=14
	else
		# final cleanup
		clean_empty_backup -i $backup_date

		# if destination was not empty, rotate backups
		if [ -d "$dest" ] ; then
			rotate_backups
		else
			# if nothing was backed up, consider it as a critical error
			# and do not rotate backups
			errors+=("Nothing was backed up.")
			lb_exitcode=14
		fi
	fi

	# if backup succeeded (all OK or even if warnings)
	case $lb_exitcode in
		0|5|15)
			lb_debug --log "Save backup timestamp"

			# save current timestamp into config/.lastbackup file
			date +%s > "$last_backup_file" || \
				lb_display_error --log "Failed to save backup date! Please check your access rights on the config directory or recurrent backups won't work."

			# create latest backup directory link
			create_latest_link
			;;
	esac

	# print final report
	lb_display --log "Backup ended on $(date '+%Y-%m-%d at %H:%M:%S')"
	lb_display --log "$(report_duration)\n"

	if [ $lb_exitcode == 0 ] ; then
		lb_display --log "Backup finished successfully."
		notify_backup_end "$tr_backup_finished\n$(report_duration)"
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

			# do not display warning message if there are critical errors to display after that
			if [ ${#errors[@]} == 0 ] ; then
				notify_backup_end "$tr_backup_finished_warnings $tr_see_logfile_for_details\n$(report_duration)"
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

			notify_backup_end "$tr_backup_failed $tr_see_logfile_for_details\n$(report_duration)"
		fi

		lb_display --log "$report_details"
	fi

	# execute custom after backup script
	[ ${#exec_after[@]} -gt 0 ] && run_after

	clean_exit
}


# Restore a file
# Usage: t2b_restore [OPTIONS] [PATH]
t2b_restore() {

	# default option values
	backup_date=latest
	local choose_date=true force_mode=false directory_mode=false \
	      restore_moved=false delete_newer_files=false

	# get options
	while [ $# -gt 0 ] ; do
		case $1 in
			-d|--date)
				backup_date=$(lb_getopt "$@")
				if [ -z "$backup_date" ] ; then
					print_help
					return 1
				fi
				choose_date=false
				shift
				;;
			-l|--latest)
				backup_date=latest
				choose_date=false
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

		# choose type of file to restore (file/directory)
		lbg_choose_option -d 1 -l "$tr_choose_restore" "$tr_restore_existing_file" "$tr_restore_moved_file" "$tr_restore_existing_directory" "$tr_restore_moved_directory"

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
			file=$(remove_end_slash "$lbg_choose_directory")/

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
			[ "${file:0:1}" == "/" ] && file=${file:1}

			# get backup date
			backup_date=$(echo $file | grep -oE "^$backup_date_format")
			if [ -z "$backup_date" ] ; then
				lbg_error "$tr_path_is_not_backup"
				return 1
			fi

			choose_date=false

			# if it is a directory, add '/' at the end of the path
			[ -d "$file" ] && file=$(remove_end_slash "$file")/

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

		# detect directory mode if path ends with / (useful for deleted directories)
		[ "${file:${#file}-1}" == "/" ] && directory_mode=true

		# get UNIX format for Windows paths
		if [ "$(get_protocol "$file")" == files ] && [ "$lb_current_os" == Windows ] ; then
			file=$(cygpath "$file")

			# directory: add a slash at the end of path (without duplicate it)
			$directory_mode && file=$(remove_end_slash "$file")/
		fi
	fi

	# case of symbolic links
	if [ -L "$file" ] ; then
		lbg_error "$tr_cannot_restore_links"
		return 12
	fi

	# if it is a directory, add '/' at the end of the path
	[ -d "$file" ] && file=$(remove_end_slash "$file")/

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

	# no hard links: do not permit restore an old version
	# (get the last entry)
	file_history=(${file_history[0]})

	# search for dates
	if [ "$backup_date" != latest ] ; then
		# if date was specified but not here, error
		if ! lb_in_array "$backup_date" "${file_history[@]}" ; then
			lbg_error "$tr_no_backups_on_date\n$tr_run_to_show_history $lb_current_script history $file"
			return 7
		fi
	fi

	# if interactive mode and more than 1 backup,
	# prompt user to choose a backup date
	if $choose_date && [ ${#file_history[@]} -gt 1 ] ; then

		# change dates to a user-friendly format
		history_dates=(${file_history[@]})

		for ((i=0; i<${#file_history[@]}; i++)) ; do
			history_dates[i]=$(get_backup_fulldate "${file_history[i]}")
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
		backup_date=${file_history[lbg_choose_option-1]}
	fi

	# if latest backup wanted, get most recent date
	[ "$backup_date" == latest ] && backup_date=${file_history[0]}

	# set backup source for restore command
	src=$destination/$backup_date/$backup_file_path

	# if source is a directory
	if [ -d "$src" ] ; then
		# trash mode: cannot restore directories
		if ! lb_istrue $hard_links ; then
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

		# if rsync result was not good (backup failed or was incomplete)
		if [ "$(get_infofile_value "$destination/$backup_date/backup.info" "$dest" rsync_result)" != 0 ] ; then
			# warn user
			lb_warning "$tr_warn_restore_partial"
			# and ask user to cancel
			lbg_yesno "$tr_warn_restore_partial\n$tr_confirm_restore_2" || return 0
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
		[ -n "$exclude_backup_dir" ] && rsync_cmd+=(--exclude "$exclude_backup_dir")
	else
		lbg_error "$tr_restore_unknown_error"
		return 8
	fi

	# search in source if exclude conf file is set
	[ -f "$src/.rsyncignore" ] && rsync_cmd+=(--exclude-from="$src/.rsyncignore")

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
				# ask to keep new files
				lbg_yesno "$tr_ask_keep_newer_files_1\n$tr_ask_keep_newer_files_2" || delete_newer_files=true
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
	$delete_newer_files && cmd+=(--delete)

	cmd+=("$src" "$dest")

	# set log file path
	logfile=$logs_directory/restore_$(date '+%Y-%m-%d-%H%M%S').log

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
		# delete log file, print info and quit
		delete_logfile
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
	local history_opts

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

	# missing arguments
	if [ $# == 0 ] ; then
		print_help
		return 1
	fi

	if lb_istrue $remote_destination ; then
		echo "This command is disabled for remote destinations."
		return 255
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
		if lb_istrue $quiet_mode ; then
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
	if ! lb_istrue $quiet_mode ; then
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
				backup_date=$(lb_getopt "$@")
				if [ -z "$backup_date" ] ; then
					print_help
					return 1
				fi
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

	if lb_istrue $console_mode ; then
		echo "This command is not available in console mode."
		return 255
	fi

	if lb_istrue $remote_destination ; then
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
			if ! lb_in_array "$backup_date" "${path_history[@]}" ; then
				lbg_error "$tr_no_backups_on_date\n$tr_run_to_show_history $lb_current_script history $path"
				return 7
			fi
		fi

	else
		# explore all backups
		if $explore_all ; then
			# warn user if displaying many folders
			if [ ${#path_history[@]} -ge 10 ] ; then
				lbg_yesno "Warning: You are about to open ${#path_history[@]} windows! Are you sure to continue?" || return 0
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
					history_dates[i]=$(get_backup_fulldate "${path_history[i]}")
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
				backup_date=${path_history[lbg_choose_option-1]}
			fi
		fi
	fi

	# not a directory: get parent
	[ -d "$path" ] || backup_path=$(dirname "$backup_path")

	for b in "${backup_date[@]}" ; do
		echo "Exploring backup $b..."
		lbg_open_directory "$destination/$b/$backup_path"
	done

	return 0
}


# Check if a backup is currently running
# Usage: t2b_status [OPTIONS]
t2b_status() {

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
		lb_istrue $quiet_mode || echo "backup destination not reachable"
		return 4
	fi

	# if no backup lock exists, exit
	if ! current_lock &> /dev/null ; then
		lb_istrue $quiet_mode || echo "backup is not running"
		return 0
	fi

	# get process PID
	local pid
	pid=$(current_lock -p)

	lb_debug "File lock contains: $pid"

	if ! lb_is_integer "$pid" ; then
		lb_istrue $quiet_mode || echo "Cannot retrieve process PID! Please search it manually."
		return 7
	fi

	# search if time2backup is running
	if ps -f $pid &> /dev/null ; then
		lb_istrue $quiet_mode || echo "backup is running with PID $pid"
		return 5
	else
		# if no time2backup process found,
		lb_istrue $quiet_mode || echo "backup lock is here, but no backup is currently running"
		return 6
	fi
}


# Stop a running backup
# Usage: t2b_stop [OPTIONS]
t2b_stop() {

	# default options and values
	local force_mode=false pid_killed=false

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
			lb_istrue $quiet_mode || echo "backup is not running"
			return 0
			;;
		5)
			# backup is running: continue
			;;
		1)
			lb_istrue $quiet_mode || echo "Unknown error"
			return 6
			;;
		4)
			lb_istrue $quiet_mode || echo "backup destination not reachable"
			return 4
			;;
		*)
			lb_istrue $quiet_mode || echo "Cannot retrieve information about process"
			return 7
			;;
	esac

	local t2b_pid

	# get time2backup PID
	t2b_pid=$(current_lock -p)
	if ! lb_is_integer $t2b_pid ; then
		lb_istrue $quiet_mode || lb_error "PID not found"
		return 7
	fi

	# prompt confirmation
	$force_mode || lb_yesno "Are you sure you want to interrupt the current backup (PID $pid)?" || return 0

	# send kill signal to time2backup
	if kill $t2b_pid ; then

		local rsync_pid

		# search for a current rsync command
		rsync_pid=$(ps -ef | grep -w $t2b_pid | grep "$rsync_path" | head -1 | awk '{print $2}')

		if lb_is_integer $rsync_pid ; then
			lb_debug "Found rsync PID: $rsync_pid"

			# send the kill signal to rsync
			kill $rsync_pid || lb_warning "Failed to kill rsync PID $rsync_pid"
		fi

		# wait 30 sec max until time2backup is really stopped
		local i
		for i in $(seq 1 20) ; do
			if t2b_status &> /dev/null ; then
				break
			fi
			sleep 1
		done
	fi

	# recheck
	if t2b_status &> /dev/null ; then
		lb_istrue $quiet_mode || echo "time2backup was successfully stopped"
		return 0
	else
		lb_istrue $quiet_mode || echo "Still running! Could not stop time2backup process. You may retry in sudo."
		return 5
	fi
}


# Move backup files
# Usage: t2b_mv [OPTIONS] PATH
t2b_mv() {

	# default option values
	local mv_latest=false force_mode=false

	# get options
	while [ $# -gt 0 ] ; do
		case $1 in
			-l|--latest)
				mv_latest=true
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

	# usage errors
	if lb_test_arguments -lt 2 $* ; then
		print_help
		return 1
	fi

	if lb_istrue $remote_destination ; then
		lb_error "This command is disabled for remote destinations."
		return 255
	fi

	# test backup destination
	prepare_destination || return 4

	src=$1
	abs_src=$1

	if [ "$(get_protocol "$src")" == files ] ; then
		# get UNIX format for Windows paths
		[ "$lb_current_os" == Windows ] && src=$(cygpath "$src")

		# get absolute path of source
		abs_src=$(lb_abspath "$src")
	fi

	dest=$2
	abs_dest=$2

	if [ "$(get_protocol "$dest")" == files ] ; then
		# get UNIX format for Windows paths
		[ "$lb_current_os" == Windows ] && dest=$(cygpath "$dest")

		# get absolute path of source
		abs_dest=$(lb_abspath "$dest")
	fi

	# get all backup versions of this path
	file_history=($(get_backup_history -a "$src"))

	# no backup found
	if [ ${#file_history[@]} == 0 ] ; then
		lb_error "No backup found for '$src'!"
		return 5
	fi

	# get backup path of the source
	path_src=$(get_backup_path "$src")
	if [ $? != 0 ] || [ -z "$path_src" ] ; then
		lb_error "Cannot determine the backup path of your source. Please retry with an absolute path."
		return 6
	fi

	# get backup path of the destination
	path_dest=$(get_backup_path "$dest")
	if [ $? != 0 ] || [ -z "$path_dest" ] ; then
		lb_error "Cannot determine the backup path of your destination. Please retry with an absolute path."
		return 6
	fi

	# confirm action
	if ! $force_mode ; then
		lb_istrue $quiet_mode || echo "You are about to move ${#file_history[@]} backups from '$1' to '$2'."

		# warn user if destination already exists
		[ -e "$destination/$file_history/$path_dest" ] && \
			lb_warning "Destination already exists! This action may erase files."

		lb_yesno "Do you want to continue?" || return 0
	fi

	local b infofile section result=0
	for b in "${file_history[@]}" ; do
		lb_istrue $quiet_mode || echo "Moving file(s) for backup $b..."

		mv "$destination/$b/$path_src" "$destination/$b/$path_dest"
		if [ $? == 0 ] ; then
			# get the infofile
			infofile=$destination/$b/backup.info
			section=$(find_infofile_section "$infofile" "$abs_src")

			# if the moved source is a source itself, rename it
			if [ -n "$section" ] ; then
				[ "$(lb_get_config -s $section "$infofile" path)" == "$abs_src" ] && \
					lb_set_config -s $section "$infofile" path "$abs_dest"
			fi

		else
			# mv failed
			lb_istrue $quiet_mode || lb_result 1
			result=7
		fi

		# if mv only latest backup, quit
		$mv_latest && break
	done

	return $result
}


# Clean files in backups
# Usage: t2b_clean [OPTIONS] PATH
t2b_clean() {

	# default option values
	local keep_latest=false force_mode=false

	# get options
	while [ $# -gt 0 ] ; do
		case $1 in
			-l|--keep-latest)
				keep_latest=true
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

	# missing arguments
	if [ $# == 0 ] ; then
		print_help
		return 1
	fi

	if lb_istrue $remote_destination ; then
		echo "This command is disabled for remote destinations."
		return 255
	fi

	# test backup destination
	prepare_destination || return 4

	if [ "$lb_current_os" == Windows ] ; then
		# get UNIX format for Windows paths
		src=$(cygpath "$1")
	else
		src=$1
	fi

	# get all backup versions of this path
	file_history=($(get_backup_history -a "$src"))

	# no backup found
	if [ ${#file_history[@]} == 0 ] ; then
		lb_error "No backup found for '$src'!"
		return 5
	fi

	# get path of file
	path_src=$(get_backup_path "$src")
	if [ $? != 0 ] || [ -z "$path_src" ] ; then
		lb_error "Cannot determine the backup path of your source. Please retry with an absolute path."
		return 6
	fi

	if $keep_latest && [ ${#file_history[@]} == 1 ] ; then
		lb_istrue $quiet_mode || echo "1 backup found, nothing to do"
		return 0
	fi

	lb_istrue $quiet_mode || echo "${#file_history[@]} backup(s) found for '$src'"

	# confirm action
	$force_mode || lb_yesno "Proceed cleaning?" || return 0

	local b result=0 first=true
	for b in "${file_history[@]}" ; do

		# if keep the latest, ignore this first entry
		if $first && $keep_latest ; then
			first=false
			continue
		fi

		lb_istrue $quiet_mode || echo "Deleting backup $b..."

		# delete file(s)
		rm -rf "$destination/$b/$path_src"
		if [ $? != 0 ] ; then
			lb_istrue $quiet_mode || lb_result 1
			result=7
		fi
	done

	return $result
}


# Copy backups
# Usage: t2b_copy [OPTIONS] PATH
t2b_copy() {

	# default option values
	local only_latest=false reference

	# get options
	while [ $# -gt 0 ] ; do
		case $1 in
			-l|--latest)
				only_latest=true
				;;
			--reference)
				if ! check_backup_date "$(lb_getopt "$@")" ; then
					print_help
					return 1
				fi
				reference=$2
				shift
				;;
			--force-hardlinks)
				hard_links=true
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

	# missing arguments
	if [ -z "$1" ] ; then
		print_help
		return 1
	fi

	# TODO: enable for remote destinations
	if lb_istrue $remote_destination ; then
		lb_error "This command is disabled for remote destinations."
		return 255
	fi

	# test backup destination
	prepare_destination || return 4

	# get destination path
	if [ "$lb_current_os" == Windows ] ; then
		# get UNIX format for Windows paths
		copy_destination=$(cygpath "$1")
	else
		copy_destination=$1
	fi

	local -a backups existing_copies

	# get available backups
	if $only_latest ; then
		backups=($(get_backups -l))
	else
		backups=($(get_backups))
	fi

	# no backup found
	if [ ${#backups[@]} == 0 ] ; then
		lb_error "No backups to copy."
		return 0
	fi

	# search for a backup reference
	if [ -z "$reference" ] ; then
		existing_copies=($(get_backups "$copy_destination"))
		if [ $? != 0 ] ; then
			lb_warning "Destination copy not found. Copy may take more time."
			lb_info "Please use the reference option to make it faster."
		fi
	fi

	lb_istrue $quiet_mode || lb_display "${#backups[@]} backups found"

	# confirm action
	$force_mode || lb_yesno "Proceed to copy?" || return 0

	# prepare rsync command
	prepare_rsync copy

	local b d src cmd first=true result errors=()
	for ((b=${#backups[@]}-1; b>=0; b--)) ; do

		src=${backups[b]}

		lb_print
		lb_print "Synchronise $src... ($((${#backups[@]} - $b))/${#backups[@]})"

		# prepare rsync command
		cmd=("${rsync_cmd[@]}")

		# defines hard links
		if lb_istrue $hard_links ; then
			# if reference link not set
			if [ -z "$reference" ] ; then

				# search the last existing distant backup
				if [ ${#existing_copies[@]} -gt 0 ] ; then
					for ((d=${#existing_copies[@]}-1; d>=0; d--)) ; do
						# avoid reference to be equal to the current item
						if [ "${existing_copies[d]}" != "$src" ] ; then
							reference=${existing_copies[d]}
							break
						fi
					done
				fi
			fi

			# add link and avoid to use the same backup date
			if [ -n "$reference" ] && [ "$reference" != "$src" ] ; then
				cmd+=(--link-dest ../"$reference")
			fi
		fi

		# add source and destination in rsync command
		cmd+=("$destination/$src/" "$copy_destination/$src")

		lb_debug Running ${cmd[*]}

		"${cmd[@]}"
		lb_result
		result=$?

		lb_debug Result: $result

		if [ $result != 0 ] ; then
			if rsync_result $result ; then
				errors+=("Partial copy $src (exit code: $result)")
			else
				errors+=("Failed to copy $src (exit code: $result)")
			fi
		fi

		# change reference
		if $first && rsync_result $result ; then
			reference=$src
			first=false
		fi
	done

	# print report
	lb_print
	if [ ${#errors[@]} == 0 ] ; then
		lb_print "Copy finished"
	else
		lb_print "Some errors occurred when copy:"
		local e
		for e in "${errors[@]}" ; do
			lb_print "   - $e"
		done

		return 6
	fi
}


# Configure time2backup
# Usage: t2b_config [OPTIONS]
t2b_config() {

	# default values
	file=""
	local op_config cmd_opts

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
				if [ -z "$(lb_getopt "$@")" ] ; then
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
			lbg_choose_option -d 1 -l "$tr_choose_config_file" \
				"$tr_global_config" "$tr_sources_config" "$tr_excludes_config" \
				"$tr_includes_config" "$tr_run_config_wizard" || return 0

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

			[ $? != 0 ] && return 5
			;;

		test)
			echo "Testing configuration..."
			load_config
			lb_result
			;;

		reset)
			# reset config file
			lb_yesno "$tr_confirm_reset_config" && \
				cat "$lb_current_script_directory/config/time2backup.example.conf" > "$config_file"
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
	[ $? != 0 ] && return 3
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

		desktop_file=$lb_current_script_directory/time2backup.desktop

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
Icon=$(lb_realpath "$lb_current_script_directory/resources/icon.png")
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

	local create_link=true

	# if alias already exists,
	if [ -e "$cmd_alias" ] ; then
		# if the same path, do not recreate link
		if [ "$(lb_realpath "$cmd_alias")" == "$(lb_realpath "$lb_current_script")" ] ; then
			create_link=false
		fi
	fi

	# (re)create link
	if $create_link ; then
		ln -snf "$lb_current_script" "$cmd_alias" &> /dev/null
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
	local delete_files=false force_mode=false

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
	$force_mode || lb_yesno "Uninstall time2backup?" || return 0

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
		rm -rf "$lb_current_script_directory"
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
