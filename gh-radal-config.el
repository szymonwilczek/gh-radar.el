;;; gh-radal-config.el --- User configuration for gh-radal -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Szymon Wilczek
;; Author: Szymon Wilczek <swilczek.lx@gmail.com>
;; License: GPL-3.0-or-later

;;; Commentary:
;; Configuration options, customizable variables, and user settings.

;;; Code:

(defgroup gh-radal nil
  "Lightweight GitHub issues and pull requests radar using gh CLI."
  :group 'tools
  :prefix "gh-radal-")

(defcustom gh-radal-repos nil
  "List of repository targets to monitor for issues and pull requests.
Each entry is of the form:
  (REPO-NAME TRACK-TYPES...)
where REPO-NAME is a string \"owner/repo\" and TRACK-TYPES are strings
or symbols: \"issues\", \"pr\", or :issues, :pr.

Example:
  \\='((\"szymonwilczek/dotfiles\" \"issues\" \"pr\")
    (\"szymonwilczek/bufferline.el\" \"issues\")
    (\"szymonwilczek/gh-radal.el\" \"pr\"))"
  :type '(repeat (cons (string :tag "Repository (owner/name)")
                       (repeat (choice (string :tag "Target (\"issues\" / \"pr\")")
                                       (symbol :tag "Target (:issues / :pr)")))))
  :group 'gh-radal)

(defcustom gh-radal-interval 600
  "Polling interval in seconds between GitHub API checks.
Default is 600 seconds (10 minutes)."
  :type 'integer
  :group 'gh-radal)

(defcustom gh-radal-gh-executable "gh"
  "Path or command name for the GitHub CLI executable."
  :type 'string
  :group 'gh-radal)

(defcustom gh-radal-notify-on-new t
  "Whether to notify when new issues or pull requests are detected."
  :type 'boolean
  :group 'gh-radal)

(provide 'gh-radal-config)
;;; gh-radal-config.el ends here
