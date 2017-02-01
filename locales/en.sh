# English messages

# Global
tr_file="file"
tr_directory="directory"
tr_not_sure_say_yes="If you are not sure, choose 'Yes'."
tr_not_sure_say_no="If you are not sure, choose 'No'."

# Main program
tr_error_no_rsync_1="rsync is not installed. time2backup will not work."
tr_error_no_rsync_2="Please install it and retry."
tr_error_getting_homepath_1="Cannot get your homepath."
tr_error_getting_homepath_2="Please install the configuration file manually."

# Choose operation
tr_choose_an_operation="Choose an operation:"
tr_backup_files="Backup files"
tr_restore_file="Restore a file"
tr_configure_time2backup="Configure time2backup"

# First run wizard
tr_confirm_install_1="Do you want to install time2backup?"
tr_confirm_install_2="Choose 'No' if you want to install manually."
tr_ask_edit_config="Do you want to edit the configuration files?"
tr_ask_first_backup="Do you want to perform your first backup now?"
tr_info_time2backup_ready="time2backup is ready!"

# Config wizard
tr_choose_backup_destination="Choose a destination for backups"
tr_force_hard_links_confirm="Previously you choosed to force using hard links. Keep this choice?"
tr_ntfs_or_exfat="Is your backup destination volume formatted in NTFS?"
tr_ask_activate_recurrent="Do you want to activate recurrent backups?"
tr_choose_backup_frequency="Choose backup frequency:"
tr_frequency_hourly="hourly"
tr_frequency_daily="daily"
tr_frequency_weekly="weekly"
tr_frequency_monthly="monthly"
tr_errors_in_config="There are errors in your configuration. Please correct it in configuration files."

# Backup
tr_notify_cancelled="Backup cancelled at %s"
tr_report_duration="Elapsed time:"
tr_error_unlock="Could not remove lock. Please delete it manually or further backups will fail!"
tr_error_unmount="Can not unmount destination!"
tr_notify_progress_1="Backup in progress..."
tr_notify_progress_2="Started at:"
tr_backup_finished="Backup finished."
tr_backup_finished_warnings="Backup finished, but some files may not be transferred."
tr_backup_failed="Backup failed! See log files for more details."

# Restore
tr_choose_restore="What do you want to restore?"
tr_restore_existing_file="An existing file"
tr_restore_moved_file="A renamed/moved/deleted file"
tr_restore_existing_directory="An existing directory"
tr_restore_moved_directory="A renamed/moved/deleted directory"
tr_choose_directory_to_restore="Choose a directory to restore"
tr_choose_file_to_restore="Choose a file to restore"
tr_cannot_restore_links="You cannot restore symbolic links!"
tr_no_backups_available="No backups available."
tr_no_backups_on_date="No backups available at this date!"
tr_run_to_show_history="Run the following command to show available backup for this file:"
tr_no_backups_for_file="No backups available for this file."
tr_choose_backup_date="Choose a backup date:"
tr_ask_keep_newer_files_1="There are newer files in this directory. Do you want to keep them?"
tr_ask_keep_newer_files_2="Press Yes to keep new files, No to restore directory at backup state."
tr_confirm_restore_1="You will restore '%s' to backup on %s."
tr_confirm_restore_2="Are your sure to continue?"
tr_restore_finished="Restore finished."
tr_restore_finished_warnings="Restore finished, but some files may not be transferred."
tr_restore_failed="Restore failed! Retry in a console to see details."
