#
#  time2backup English messages
#
#  This file is part of time2backup (https://time2backup.org)
#
#  MIT License
#  Copyright (c) 2017-2020 Jean Prunneaux
#

# Dates formatting
tr_readable_date="%Y-%m-%d at %H:%M:%S"

# Global
tr_not_sure_say_yes="If you are not sure, choose 'Yes'."
tr_not_sure_say_no="If you are not sure, choose 'No'."
tr_please_retry="Please retry."
tr_see_logfile_for_details="See the log file for more details."

# Main program
tr_error_no_rsync_1="rsync is not installed. time2backup will not work."
tr_error_no_rsync_2="Please install it and retry."
tr_error_getting_homepath_1="Cannot get your homepath."
tr_error_getting_homepath_2="Please install the configuration file manually."
tr_loading_config="Loading config..."
tr_error_read_config="Config file is corrupted or cannot be read!"
tr_error_create_config="Cannot create config files!"
tr_upgrade_config="Upgrading your configuration file..."
tr_error_upgrade_config="Cannot upgrade your configuration file. Please do it manually."

# Choose operation
tr_choose_an_operation="Choose an operation:"
tr_backup_files="Backup files"
tr_restore_file="Restore a file"
tr_explore_backups="Explore backups"
tr_configure_time2backup="Configure time2backup"
tr_quit="Quit"

# Config mode
tr_choose_config_file="Choose file to edit:"
tr_global_config="General configuration"
tr_sources_config="Elements to backup"
tr_excludes_config="Excluded files"
tr_includes_config="Included files (not used in most cases)"
tr_run_config_wizard="Run configuration wizard"
tr_confirm_reset_config="Do you really want to reset configuration?"

# Config wizard
tr_choose_backup_destination="Choose a destination for backups:"
tr_change_hostname="Backups from another PC named '%s' were found. Do you want to use them?"
tr_change_hostname_no="Choose 'no' if you are not owner of those backups."
tr_error_set_destination="Error while setting destination."
tr_edit_config_manually="Please edit configuration file manually."
tr_force_hard_links_confirm="Previously you chose to force using hard links. Keep this choice?"
tr_ask_edit_sources="Do you want to choose which elements will be backed up?"
tr_default_source="By default, it will backup your private home directory."
tr_choose_backup_source="Choose a directory to backup:"
tr_finished_edit="If you have finished to edit the configuration file, save the file and press OK."
tr_ask_activate_recurrent="Do you want to activate recurrent backups?"
tr_choose_backup_frequency="Choose backup frequency:"
tr_frequency_hourly="hourly"
tr_frequency_daily="daily"
tr_frequency_weekly="weekly"
tr_frequency_monthly="monthly"
tr_frequency_custom="customized"
tr_enter_frequency="Enter a custom frequency (h for hours, d for days):"
tr_frequency_examples="e.g. 4h for 4 hours, 2d for 2 days"
tr_frequency_syntax_error="Syntax error in your custom frequency."
tr_errors_in_config="There are errors in your configuration. Please correct it in configuration files."
tr_ask_edit_config="Do you want to edit the configuration files?"
tr_cannot_install_cronjobs="Cannot activate recurrent backups.\nPlease set it manually in your crontab."
tr_ask_backup_now="time2backup is ready! Do you want to run a backup now?"

# Backup
tr_nothing_to_backup="Nothing to backup!"
tr_please_configure_sources="Please configure sources."
tr_backup_unreachable="Backup destination is not reachable."
tr_verify_media="Please verify if your media is plugged in and try again."
tr_verify_access_rights="Please verify your access rights."
tr_write_error_destination="You have no write access on backup destination directory."
tr_backup_already_running="A backup is already running. Backup is cancelled."
tr_backup_cancelled_at="Backup cancelled at %s"
tr_report_duration="Elapsed time:"
tr_error_unlock="Could not remove lock. Please delete it manually or further backups will fail!"
tr_error_unmount="Can not unmount destination!"
tr_notify_rotate_backup="Cleaning old backups..."
tr_notify_prepare_backup="Preparing backup..."
tr_notify_cleaning_space="Free space on backup destination..."
tr_estimated_time="Estimated time: %s minutes"
tr_backup_in_progress="Backup in progress..."
tr_backup_finished="Backup finished."
tr_backup_finished_warnings="Backup finished, but some files may not be transferred."
tr_backup_failed="Backup failed."

# Restore
tr_choose_restore="What do you want to restore?"
tr_restore_existing_file="An existing file"
tr_restore_moved_file="A renamed/moved/deleted file"
tr_restore_existing_directory="An existing directory"
tr_restore_moved_directory="A renamed/moved/deleted directory"
tr_choose_directory_to_restore="Choose a directory to restore"
tr_choose_file_to_restore="Choose a file to restore"
tr_path_is_not_backup="The path you chose is not a valid backup!"
tr_cannot_restore_links="You cannot restore symbolic links!"
tr_no_backups_available="No backups available."
tr_no_backups_on_date="No backups available at this date!"
tr_run_to_show_history="Run the following command to show available backup for this file:"
tr_no_backups_for_file="No backups available for this file."
tr_choose_backup_date="Choose a backup date:"
tr_restore_unknown_error="Unknown error in the restore path. Run the debug mode for more details."
tr_notify_prepare_restore="Preparing restore..."
tr_warn_restore_partial="You are about to restore a directory from an incomplete backup! Some files may be missing."
tr_ask_keep_newer_files_1="There are newer files in this directory. Do you want to keep them?"
tr_ask_keep_newer_files_2="Press Yes to keep new files, No to restore directory at backup state."
tr_confirm_restore_1="You will restore '%s' to backup on %s."
tr_confirm_restore_2="Are your sure to continue?"
tr_notify_restoring="Restore file(s) in progress..."
tr_restore_finished="Restore finished."
tr_restore_finished_warnings="Restore finished, but some files may not be transferred."
tr_restore_failed="Restore failed! Retry in a console to see details."
tr_restore_cancelled="Restore cancelled."

# Report email
tr_email_report_subject="time2backup report:"
tr_email_report_subject_success="Backup succeeded on %s"
tr_email_report_subject_failed="Backup failed on %s"
tr_email_report_greetings="Dear user,"
tr_email_report_success="A backup succeeded on %s."
tr_email_report_failed="A backup failed on %s (exit code: %s)."
tr_email_report_details="Backup started on %s"
tr_email_report_regards="Regards,"
