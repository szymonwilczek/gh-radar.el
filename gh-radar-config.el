;;; gh-radar-config.el --- User configuration for gh-radar -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Szymon Wilczek
;; Author: Szymon Wilczek <swilczek.lx@gmail.com>
;; License: GPL-3.0-or-later

;;; Commentary:
;; Configuration options, customizable variables, and user settings.

;;; Code:

(defgroup gh-radar nil
  "GitHub issues and pull requests radar using gh CLI."
  :group 'tools
  :prefix "gh-radar-")

(defcustom gh-radar-repos nil
  "List of repository targets to monitor for issues and pull requests.
Each entry is of the form:
  (REPO-NAME TRACK-TYPES...)
where REPO-NAME is a string \"owner/repo\" and TRACK-TYPES are strings
or symbols: \"issues\", \"pr\", or :issues, :pr."

  :type '(repeat (cons (string :tag "Repository (owner/name)")
                       (repeat (choice (string :tag "Target (\"issues\" / \"pr\")")
                                       (symbol :tag "Target (:issues / :pr)")))))
  :group 'gh-radar)

(defcustom gh-radar-interval 600
  "Polling interval in seconds between GitHub API checks.
Default is 600 seconds (10 minutes)."
  :type 'integer
  :group 'gh-radar)

(defcustom gh-radar-gh-executable "gh"
  "Path or command name for the GitHub CLI executable."
  :type 'string
  :group 'gh-radar)

(defcustom gh-radar-notify-on-new t
  "Whether to notify when new issues or pull requests are detected."
  :type 'boolean
  :group 'gh-radar)

(defcustom gh-radar-show-prefix nil
  "Whether to display the GitHub icon or prefix before the counters.
Defaults to nil."
  :type 'boolean
  :group 'gh-radar)

(defcustom gh-radar-show-inbox-icon t
  "Whether to display the inbox icon in the mode-line.
Defaults to t."
  :type 'boolean
  :group 'gh-radar)

(defcustom gh-radar-show-issue-icon t
  "Whether to display the issues icon in the mode-line.
Defaults to t."
  :type 'boolean
  :group 'gh-radar)

(defcustom gh-radar-show-pr-icon t
  "Whether to display the pull requests icon in the mode-line.
Defaults to t."
  :type 'boolean
  :group 'gh-radar)

(defcustom gh-radar-modeline-icons '(inbox issues pr)
  "List of icon identifiers to display in the mode-line.
Can contain `inbox', `issues', and `pr'.
Defaults to \\='(inbox issues pr)."
  :type '(set (const :tag "Inbox icon" inbox)
              (const :tag "Issues icon" issues)
              (const :tag "Pull requests icon" pr))
  :group 'gh-radar)

(defcustom gh-radar-hide-zero-counts nil
  "Whether to hide mode-line segments when their count is zero.
When t, hide any segment (inbox, issues, pr) whose count is 0.
When a list of symbols (e.g. `(inbox)', `(issues)', `(pr)'), hide only
those specific segments when their count is 0.
Defaults to nil (show segments even with zero count)."
  :type '(choice (const :tag "Never hide zero counts" nil)
                 (const :tag "Hide all zero counts" t)
                 (set :tag "Hide specific zero counts"
                      (const :tag "Inbox" inbox)
                      (const :tag "Issues" issues)
                      (const :tag "Pull requests" pr)))
  :group 'gh-radar)

(defcustom gh-radar-track-notifications t
  "Whether to track unread notifications from GitHub inbox.
Defaults to t."
  :type 'boolean
  :group 'gh-radar)

(defcustom gh-radar-dashboard-display-style 'full-window
  "Display style for opening the interactive dashboard buffer.
Supported values:
  `full-window'  - Open fullscreen in active frame and maximize (default).
  `same-window'  - Open in current window as a buffer tab.
  `pop-to-buffer' - Use standard Emacs `pop-to-buffer'."
  :type '(choice (const :tag "Full window (maximize)" full-window)
                 (const :tag "Same window" same-window)
                 (const :tag "Pop to buffer" pop-to-buffer))
  :group 'gh-radar)

(defface gh-radar-prefix-face
  '((t :inherit font-lock-comment-face :weight bold))
  "Face for the radar prefix or icon."
  :group 'gh-radar)

(defface gh-radar-repo-face
  '((t :inherit default :weight bold))
  "Face for repository labels."
  :group 'gh-radar)

(defface gh-radar-issue-face
  '((t :inherit warning))
  "Face for open issues count."
  :group 'gh-radar)

(defface gh-radar-pr-face
  '((t :inherit font-lock-builtin-face))
  "Face for open pull requests count."
  :group 'gh-radar)

(defface gh-radar-new-face
  '((t :inherit error :weight bold))
  "Face for newly detected issues or pull requests."
  :group 'gh-radar)

(defface gh-radar-inbox-face
  '((t :inherit font-lock-constant-face))
  "Face for inbox notification count."
  :group 'gh-radar)

(provide 'gh-radar-config)
;;; gh-radar-config.el ends here
