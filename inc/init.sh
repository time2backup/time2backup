###########################
#  VARIABLES DECLARATION  #
###########################

new_config=false
custom_config=false
sources=()
mounted=false
rsync_cmd=()
success=()
warnings=()
errors=()
default_verbose_level=INFO
default_log_level=INFO
force_unmount=false
quiet_mode=false
remote_destination=false
backup_date_format="[1-9][0-9]{3}-[0-1][0-9]-[0-3][0-9]-[0-2][0-9][0-5][0-9][0-5][0-9]"


############################
#  DEFAULT CONFIG OPTIONS  #
############################

# time2backup default core config
enable_recurrent=true
ask_to_install=true
cmd_alias=/usr/bin/time2backup

# default config
destination_subdirectories=true
test_destination=true

resume_cancelled=true
resume_failed=false

console_mode=false
debug_mode=false

mount=true

network_compression=false
ssh_options=ssh

recurrent=false
frequency=daily

keep_limit=-1
clean_old_backups=true
clean_keep=0

keep_logs=on_error
log_level=$default_log_level

notifications=true
email_report=none

exec_before_block=false
exec_after_block=false

# unmount after backup
unmount=false
unmount_auto=true

# shutdown after backup
shutdown=false
shutdown_cmd=(shutdown -h now)

# advanced options
hard_links=true
force_hard_links=false
mirror_mode=false
rsync_path=rsync
rsync_options=()
verbose_level=$default_verbose_level
