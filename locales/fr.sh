#
# time2backup French translations
#
# This file is part of time2backup (https://github.com/pruje/time2backup)
#
# MIT License
# Copyright (c) 2017 Jean Prunneaux
#

# Global
tr_file="fichier"
tr_directory="dossier"
tr_not_sure_say_yes="Si vous n'êtes pas sûr(e), choisissez 'Oui'."
tr_not_sure_say_no="Si vous n'êtes pas sûr(e), choisissez 'Non'."
tr_please_retry="Veuillez réessayer."

# Main program
tr_error_no_rsync_1="rsync n'est pas installé. time2backup ne fonctionnera pas."
tr_error_no_rsync_2="Veuillez l'installer puis réessayez."
tr_error_getting_homepath_1="Impossible de trouver votre répertoire utilisateur."
tr_error_getting_homepath_2="Veuillez installer le fichier de configuration manuellement."

# Choose operation
tr_choose_an_operation="Choisissez une opération :"
tr_backup_files="Sauvegarder les fichiers"
tr_restore_file="Restaurer un fichier"
tr_configure_time2backup="Configurer time2backup"

# First run wizard
tr_confirm_install_1="Voulez-vous installer time2backup ?"
tr_confirm_install_2="Choisissez 'Non' si vous souhaitez l'installer manuellement."
tr_ask_edit_config="Voulez-vous éditer les fichiers de configuration ? (en anglais)"
tr_ask_first_backup="Voulez-vous lancer votre première sauvegarde maintenant ?"
tr_info_time2backup_ready="time2backup est prêt !"

# Config mode
tr_choose_config_file="Choisissez le fichier à éditer :"
tr_global_config="Configuration générale (anglais)"
tr_sources_config="Éléments à sauvegarder"
tr_excludes_config="Fichiers exclus"
tr_includes_config="Fichiers inclus (souvent peu utile)"
tr_run_config_wizard="Lancer l'assistant de configuration"

# Config wizard
tr_choose_backup_destination="Choisissez le dossier de destination des sauvegardes :"
tr_error_set_destination="Erreur lors de l'enregistrement de la destination."
tr_edit_config_manually="Veuillez éditer le fichier de configuration manuellement."
tr_force_hard_links_confirm="Vous aviez choisi précédemment de forcer les liens physiques. Conserver ce choix ?"
tr_ntfs_or_exfat="Le volume de destination des sauvegardes est-il au format NTFS ?"
tr_ask_edit_sources="Voulez-vous choisir les éléments à sauvegarder ?"
tr_default_source="Par défaut, tout votre répertoire personnel sera sauvegardé."
tr_finished_edit="Si vous avez terminé l'édition du fichier de configuration, enregistrez le fichier et cliquez sur OK."
tr_ask_activate_recurrent="Voulez-vous activer les sauvegardes récurrentes ?"
tr_choose_backup_frequency="Choisissez la fréquence des sauvegardes :"
tr_frequency_hourly="toutes les heures"
tr_frequency_daily="tous les jours"
tr_frequency_weekly="toutes les semaines"
tr_frequency_monthly="tous les mois"
tr_frequency_custom="personnalisé"
tr_enter_frequency="Entrez une fréquence (h pour heures, d pour jours):"
tr_frequency_examples="ex: 4h pour 4 heures, 2d pour 2 jours"
tr_frequency_syntax_error="Il y a une erreur de syntaxe dans votre choix."
tr_errors_in_config="Il y a des erreurs dans votre configuration. Veuillez les corriger dans les fichiers de configuration."

# Backup
tr_backup_cancelled_at="Sauvegarde annulée à %s"
tr_report_duration="Temps écoulé :"
tr_error_unlock="Impossible d'enlever le verrou. Veuillez le supprimer manuellement ou les prochaines sauvegardes échoueront !"
tr_error_unmount="Impossible de démonter le volume !"
tr_notify_progress_1="Sauvegarde en cours..."
tr_notify_progress_2="Démarré à :"
tr_backup_finished="Sauvegarde terminée."
tr_backup_finished_warnings="Sauvegarde terminée, mais certains fichiers n'ont pas été transférés."
tr_backup_failed="Échec de la sauvegarde. Voir les fichiers de log pour plus de détails."

# Restore
tr_choose_restore="Que voulez-vous restaurer ?"
tr_restore_existing_file="Un fichier existant"
tr_restore_moved_file="Un fichier renommé/déplacé/supprimé"
tr_restore_existing_directory="Un dossier existant"
tr_restore_moved_directory="Un dossier renommé/déplacé/supprimé"
tr_choose_directory_to_restore="Choisissez le dossier à restaurer"
tr_choose_file_to_restore="Choisissez le fichier à restaurer"
tr_path_is_not_backup="Le chemin que vous avez choisi n'est pas une sauvegarde !"
tr_cannot_restore_links="Vous ne pouvez pas restaurer des liens !"
tr_no_backups_available="Aucune sauvegarde disponible."
tr_no_backups_on_date="Aucune sauvegarde disponible à cette date !"
tr_run_to_show_history="Exécutez la commande suivante pour afficher les sauvegardes disponibles :"
tr_no_backups_for_file="Aucune sauvegarde disponible pour ce fichier."
tr_choose_backup_date="Choisissez une date de sauvegarde :"
tr_cannot_restore_from_trash="Vous ne pouvez pas restaurer des dossiers en mode trash !"
tr_ask_keep_newer_files_1="Il y a des fichiers plus récents dans ce dossier. Voulez-vous les conserver ?"
tr_ask_keep_newer_files_2="Cliquez sur Oui pour conserver, Non pour restaurer le dossier à l'état de la sauvegarde."
tr_confirm_restore_1="Vous allez restaurer '%s' à la sauvegarde du %s."
tr_confirm_restore_2="Êtes-vous sûr(e) de continuer ?"
tr_restore_finished="Restauration terminée."
tr_restore_finished_warnings="Restauration terminée, mais certains fichiers n'ont pas été transférés."
tr_restore_failed="Échec de la restauration! Réessayez dans un terminal pour voir les détails."
tr_restore_cancelled="Restauration annulée."
