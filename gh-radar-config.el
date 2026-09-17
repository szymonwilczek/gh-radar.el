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

(declare-function notifications-notify "notifications")

(defcustom gh-radar-desktop-notification-backend nil
  "Backend for desktop system notifications when new activity is detected.
Supported values:
- `nil': Disabled (default).
- `notifications' or `notifications-notify': Use Emacs built-in
  `notifications-notify' (D-Bus / libnotify).
- `notify-send': Use external `notify-send' CLI executable.
- A custom function taking two arguments: (TITLE BODY)."
  :type '(choice (const :tag "Disabled" nil)
                 (const :tag "Built-in notifications-notify (D-Bus)" notifications)
                 (const :tag "External notify-send command" notify-send)
                 (function :tag "Custom notification function"))
  :group 'gh-radar)

(defun gh-radar-notify-desktop (title body)
  "Send desktop system notification with TITLE and BODY according to backend."
  (pcase gh-radar-desktop-notification-backend
    ((or 'notifications 'notifications-notify 'libnotify)
     (when (require 'notifications nil t)
       (ignore-errors
         (notifications-notify
          :title title
          :body body
          :app-name "gh-radar"
          :app-icon "emacs"))))
    ('notify-send
     (when (executable-find "notify-send")
       (start-process "gh-radar-notify" nil "notify-send"
                      "-a" "gh-radar"
                      "-i" "emacs"
                      title body)))
    ((pred functionp)
     (ignore-errors
       (funcall gh-radar-desktop-notification-backend title body)))
    (_ nil)))

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

(defcustom gh-radar-show-bell-icon t
  "Whether to display the bell icon in aggregate mode-line mode.
Defaults to t."
  :type 'boolean
  :group 'gh-radar)

(defcustom gh-radar-modeline-icons '(inbox issues pr bell)
  "List of icon identifiers to display in the mode-line.
Can contain `inbox', `issues', `pr', and `bell'.
Defaults to \\='(inbox issues pr bell)."
  :type '(set (const :tag "Inbox icon" inbox)
              (const :tag "Issues icon" issues)
              (const :tag "Pull requests icon" pr)
              (const :tag "Bell icon" bell))
  :group 'gh-radar)

(defvaralias 'gh-radar-modeline-bell 'gh-radar-bell-modeline)

(defcustom gh-radar-bell-modeline nil
  "Whether to display a single aggregate bell icon in the mode-line.
When non-nil, replaces individual mode-line icons and counters with a single
bell icon followed by the sum of all tracked notifications, issues, and PRs.
Defaults to nil."
  :type 'boolean
  :group 'gh-radar)

(defcustom gh-radar-hide-zero-counts nil
  "Whether to hide mode-line segments when their count is zero.
When t, hide any segment (inbox, issues, pr, bell) whose count is 0.
When a list of symbols (e.g. `(inbox)', `(issues)', `(pr)', `(bell)'),
hide only those specific segments when their count is 0.
When nil, individual segments with zero counts are shown, but in bell mode
(`gh-radar-bell-modeline') a total count of zero is hidden by default.
To force displaying zero in bell mode, set to `never'."
  :type '(choice (const :tag "Never hide zero counts" nil)
                 (const :tag "Hide all zero counts" t)
                 (const :tag "Never hide zero counts even in bell mode" never)
                 (set :tag "Hide specific zero counts"
                      (const :tag "Inbox" inbox)
                      (const :tag "Issues" issues)
                      (const :tag "Pull requests" pr)
                      (const :tag "Bell (aggregate)" bell)))
  :group 'gh-radar)

(defcustom gh-radar-track-notifications t
  "Whether to track unread notifications from GitHub inbox.
Defaults to t."
  :type 'boolean
  :group 'gh-radar)

(defcustom gh-radar-count-display 'all
  "Mode for displaying counts in the mode-line and dashboard.
Can be:
  `all'      - Display total counts along with unread deltas (default).
  `only-new' - Display only the delta of newly arrived unread items:
               e.g. \"+2\" (or \"0\" when none).
Defaults to `all'."
  :type '(choice (const :tag "All counts (total + new delta)" all)
                 (const :tag "Only new counts (unread delta)" only-new))
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

(declare-function nerd-icons-octicon "nerd-icons")
(declare-function nerd-icons-faicon "nerd-icons")
(declare-function nerd-icons-codicon "nerd-icons")
(declare-function nerd-icons-mdicon "nerd-icons")
(declare-function gh-radar-cache-get-setting "gh-radar-cache")

(defcustom gh-radar-icons
  '((inbox . "nf-oct-inbox")
    (issues . "nf-oct-issue_opened")
    (pr . "nf-oct-git_pull_request")
    (bell . "nf-oct-bell")
    (repo . "nf-oct-repo")
    (prefix . "nf-oct-mark_github"))
  "Alist mapping gh-radar item types to icon names or unicode characters."
  :type '(alist :key-type symbol :value-type string)
  :group 'gh-radar)

(defcustom gh-radar-icon-fallbacks
  '((inbox . "@")
    (issues . "#")
    (pr . "!")
    (bell . "B")
    (repo . "R")
    (prefix . "GH"))
  "Alist mapping gh-radar item types to terminal/fallback strings."
  :type '(alist :key-type symbol :value-type string)
  :group 'gh-radar)

(defun gh-radar-resolve-icon (name fallback &optional face)
  "Resolve icon NAME into a glyph string using nerd-icons or FALLBACK.
If NAME is an emoji or raw string, return it directly.
If FACE is non-nil, apply FACE to the returned glyph."
  (let ((glyph
         (cond
          ((null name) fallback)
          ((not (display-graphic-p)) fallback)
          ((and (string-prefix-p "nf-oct-" name) (fboundp 'nerd-icons-octicon))
           (or (ignore-errors (nerd-icons-octicon name)) fallback))
          ((and (string-prefix-p "nf-fa-" name) (fboundp 'nerd-icons-faicon))
           (or (ignore-errors (nerd-icons-faicon name)) fallback))
          ((and (string-prefix-p "nf-cod-" name) (fboundp 'nerd-icons-codicon))
           (or (ignore-errors (nerd-icons-codicon name)) fallback))
          ((and (string-prefix-p "nf-md-" name) (fboundp 'nerd-icons-mdicon))
           (or (ignore-errors (nerd-icons-mdicon name)) fallback))
          ((and (fboundp 'nerd-icons-octicon)
                (ignore-errors (nerd-icons-octicon (concat "nf-oct-" name)))))
          ((stringp name) name)
          (t fallback))))
    (if face
        (propertize glyph 'face face 'font-lock-face face)
      glyph)))

(defun gh-radar-icon (type &optional face)
  "Return resolved icon glyph for symbol TYPE (:inbox, :issues, :pr, :bell, :repo).
If FACE is non-nil, apply FACE to the glyph."
  (let* ((type-sym (if (keywordp type) (intern (substring (symbol-name type) 1)) type))
         (cached-icons (when (fboundp 'gh-radar-cache-get-setting)
                         (gh-radar-cache-get-setting :icons nil)))
         (icon-entry (or (assq type-sym cached-icons)
                         (assq type-sym gh-radar-icons)))
         (name (if (consp icon-entry) (cdr icon-entry) icon-entry))
         (fallback-entry (assq type-sym gh-radar-icon-fallbacks))
         (fallback (if (consp fallback-entry) (cdr fallback-entry) (symbol-name type-sym))))
    (gh-radar-resolve-icon (or name (symbol-name type-sym)) (or fallback "?") face)))

(provide 'gh-radar-config)
;;; gh-radar-config.el ends here
