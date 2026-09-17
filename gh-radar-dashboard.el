;;; gh-radar-dashboard.el --- Dashboard for gh-radar -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Szymon Wilczek
;; Author: Szymon Wilczek <swilczek.lx@gmail.com>
;; License: GPL-3.0-or-later

;;; Commentary:
;; Dashboard buffer displaying monitored repositories, issues,
;; and pull requests metrics with keyboard navigation and actions.

;;; Code:

(require 'cl-lib)
(require 'parse-time)
(require 'gh-radar-config)
(require 'gh-radar-state)

(declare-function evil-define-key "evil-core" (state keymap key def &rest bindings))
(declare-function evil-make-overriding-map "evil-core" (keymap &optional state copy))
(declare-function gh-radar-process-fetch "gh-radar-process" (&optional callback))

(declare-function gh-radar-settings "gh-radar-settings" ())

(defcustom gh-radar-dashboard-max-width 100
  "Maximum character width for the radar dashboard layout."
  :type 'integer
  :group 'gh-radar)

(defface gh-radar-dashboard-title
  '((t :height 1.3 :weight bold :inherit default))
  "Face for the dashboard title banner."
  :group 'gh-radar)

(defface gh-radar-dashboard-repo
  '((t :height 1.1 :weight bold :inherit font-lock-function-name-face))
  "Face for repository names in the dashboard."
  :group 'gh-radar)

(defface gh-radar-dashboard-meta
  '((t :inherit shadow :height 0.95))
  "Face for metadata and secondary timestamps in dashboard rows."
  :group 'gh-radar)

(defface gh-radar-dashboard-separator
  '((t :inherit shadow))
  "Face for horizontal rules in the dashboard."
  :group 'gh-radar)

(defface gh-radar-dashboard-row-highlight
  '((((background dark)) :background "#1b2027" :extend t)
    (((background light)) :background "#eef1f5" :extend t)
    (t :inherit highlight :extend t))
  "Face used to highlight the repository row at point."
  :group 'gh-radar)

(defface gh-radar-dashboard-unread-bullet
  '((t :inherit warning :weight bold))
  "Face for bullets preceding unread items in the dashboard."
  :group 'gh-radar)

(defface gh-radar-dashboard-unread-title
  '((t :inherit default :weight bold))
  "Face for unread item titles in the dashboard."
  :group 'gh-radar)

(defface gh-radar-dashboard-section-header
  '((t :height 1.1 :weight bold :inherit font-lock-keyword-face))
  "Face for section headers in the dashboard."
  :group 'gh-radar)

(defvar-local gh-radar-dashboard--rows nil
  "List of (BEG END REPO-DATA) describing rendered repository rows.")

(defvar-local gh-radar-dashboard--highlight nil
  "Overlay highlighting the active repository row at point.")

(defun gh-radar-dashboard-width ()
  "Compute responsive layout width for the dashboard buffer."
  (let* ((buf-win (get-buffer-window (current-buffer)))
         (win (if (and buf-win (window-live-p buf-win)) buf-win (selected-window)))
         (win-w (if (and win (window-live-p win)) (window-body-width win) 80)))
    (max 40 (min (- win-w 4) gh-radar-dashboard-max-width))))

(defun gh-radar-dashboard--icon (name fallback &optional face)
  "Return nerd-icon NAME or FALLBACK propertized with FACE."
  (let ((glyph (if (and (fboundp 'nerd-icons-octicon) (display-graphic-p))
                   (or (ignore-errors (nerd-icons-octicon name)) fallback)
                 fallback)))
    (if face (propertize glyph 'face face 'font-lock-face face) glyph)))

(defun gh-radar-dashboard--time-ago (time)
  "Format internal TIME into a human-readable relative time string."
  (if (null time)
      "never"
    (let ((diff (max 0 (truncate (float-time (time-subtract (current-time) time))))))
      (cond
       ((< diff 60) "just now")
       ((< diff 3600) (format "%dm ago" (/ diff 60)))
       ((< diff 86400) (format "%dh ago" (/ diff 3600)))
       (t (format "%dd ago" (/ diff 86400)))))))

(defun gh-radar-dashboard--row-at-point ()
  "Return the (BEG END REPO-DATA) row triple containing point, or nil."
  (let ((pos (point)))
    (cl-find-if (lambda (row) (and (>= pos (nth 0 row)) (< pos (nth 1 row))))
                gh-radar-dashboard--rows)))

(defun gh-radar-dashboard--update-highlight ()
  "Move the row highlight overlay to the repository row at point."
  (if-let* ((row (gh-radar-dashboard--row-at-point)))
      (let ((beg (nth 0 row))
            (end (nth 1 row)))
        (unless (overlayp gh-radar-dashboard--highlight)
          (setq gh-radar-dashboard--highlight (make-overlay beg end))
          (overlay-put gh-radar-dashboard--highlight 'face 'gh-radar-dashboard-row-highlight))
        (move-overlay gh-radar-dashboard--highlight beg end))
    (when (overlayp gh-radar-dashboard--highlight)
      (delete-overlay gh-radar-dashboard--highlight))))

(defun gh-radar-dashboard-next-row ()
  "Move point to the beginning of the next repository row."
  (interactive)
  (let* ((cur (gh-radar-dashboard--row-at-point))
         (pos (point))
         (next (cl-find-if (lambda (r) (> (nth 0 r) (if cur (nth 0 cur) pos)))
                           gh-radar-dashboard--rows)))
    (when next
      (goto-char (nth 0 next))
      (gh-radar-dashboard--update-highlight))))

(defun gh-radar-dashboard-previous-row ()
  "Move point to the beginning of the previous repository row."
  (interactive)
  (let* ((cur (gh-radar-dashboard--row-at-point))
         (pos (point))
         (prev (car (last (cl-remove-if-not
                           (lambda (r) (< (nth 0 r) (if cur (nth 0 cur) pos)))
                           gh-radar-dashboard--rows)))))
    (when prev
      (goto-char (nth 0 prev))
      (gh-radar-dashboard--update-highlight))))

(defun gh-radar-dashboard-current-repo ()
  "Return the repository plist for the row at point, or nil."
  (nth 2 (gh-radar-dashboard--row-at-point)))

(defun gh-radar-dashboard-open-notifications ()
  "Open GitHub notifications in web browser."
  (interactive)
  (browse-url "https://github.com/notifications"))

(defun gh-radar-dashboard-open-issues ()
  "Open issues for the repository or inbox at point in web browser."
  (interactive)
  (if-let* ((item (gh-radar-dashboard-current-repo)))
      (if (plist-get item :inbox)
          (gh-radar-dashboard-open-notifications)
        (let ((repo (or (plist-get item :repo)
                        (format "%s/%s" (plist-get item :owner) (plist-get item :name)))))
          (browse-url (format "https://github.com/%s/issues" repo))))
    (user-error "No item at point")))

(defun gh-radar-dashboard-open-pulls ()
  "Open pull requests for the repository or inbox at point in web browser."
  (interactive)
  (if-let* ((item (gh-radar-dashboard-current-repo)))
      (if (plist-get item :inbox)
          (gh-radar-dashboard-open-notifications)
        (let ((repo (or (plist-get item :repo)
                        (format "%s/%s" (plist-get item :owner) (plist-get item :name)))))
          (browse-url (format "https://github.com/%s/pulls" repo))))
    (user-error "No item at point")))

(defun gh-radar-dashboard-open-at-point ()
  "Open repository page, unread item, or inbox at point in web browser."
  (interactive)
  (if-let* ((item (gh-radar-dashboard-current-repo)))
      (cond
       ((plist-get item :unread)
        (let ((url (plist-get item :url))
              (repo (plist-get item :repo))
              (type (plist-get item :type))
              (num (plist-get item :number)))
          (when url
            (browse-url url)
            (gh-radar-state-dismiss-item repo type num)
            (gh-radar-dashboard-render))))
       ((plist-get item :inbox)
        (gh-radar-dashboard-open-notifications))
       (t
        (let ((repo (or (plist-get item :repo)
                        (format "%s/%s" (plist-get item :owner) (plist-get item :name)))))
          (browse-url (format "https://github.com/%s" repo)))))
    (user-error "No item at point")))

(defun gh-radar-dashboard-dismiss ()
  "Dismiss the unread item or all unread items for repository at point."
  (interactive)
  (if-let* ((item (gh-radar-dashboard-current-repo)))
      (cond
       ((plist-get item :unread)
        (let ((repo (plist-get item :repo))
              (type (plist-get item :type))
              (num (plist-get item :number)))
          (gh-radar-state-dismiss-item repo type num)
          (gh-radar-dashboard-render)
          (message "[gh-radar] Dismissed %s #%d in %s"
                   (if (eq type :pr) "PR" "issue") num repo)))
       ((plist-get item :repo)
        (let ((repo (plist-get item :repo)))
          (gh-radar-state-dismiss-repo repo)
          (gh-radar-dashboard-render)
          (message "[gh-radar] Dismissed unread items for %s" repo)))
       (t
        (user-error "Nothing to dismiss at point")))
    (user-error "No item at point")))

(defun gh-radar-dashboard-dismiss-all ()
  "Dismiss all unread activity across all repositories."
  (interactive)
  (gh-radar-state-dismiss-all)
  (gh-radar-dashboard-render)
  (message "[gh-radar] Dismissed all unread notifications"))

(defun gh-radar-dashboard--insert-unread-section ()
  "Insert the unread activity section if any unread items exist."
  (let ((unread (gh-radar-state-unread-items))
        (width (gh-radar-dashboard-width)))
    (when unread
      (insert "  "
              (propertize (format "New Activity (%d)" (length unread))
                          'face 'gh-radar-dashboard-section-header)
              "  "
              (propertize "· [d] dismiss item · [D] dismiss all"
                          'face 'gh-radar-dashboard-meta)
              "\n"
              "  "
              (propertize (make-string width ?─) 'face 'gh-radar-dashboard-separator)
              "\n\n")
      (dolist (item unread)
        (let* ((repo (plist-get item :repo))
               (type (plist-get item :type))
               (num (plist-get item :number))
               (title (plist-get item :title))
               (author (plist-get item :author))
               (time (plist-get item :created-at))
               (type-label (if (eq type :pr) "PR" "issue"))
               (type-face (if (eq type :pr) 'gh-radar-pr-face 'gh-radar-issue-face))
               (type-icon (if (eq type :pr)
                              (gh-radar-dashboard--icon "nf-oct-git_pull_request" "PR" type-face)
                            (gh-radar-dashboard--icon "nf-oct-issue_opened" "#" type-face)))
               (bullet (propertize "●" 'face 'gh-radar-dashboard-unread-bullet))
               (data (append (list :unread t) item))
               (beg (point)))
          (insert "  " bullet "  "
                  type-icon " "
                  (propertize (format "#%d" num) 'face type-face) "  "
                  (propertize (or title "(no title)") 'face 'gh-radar-dashboard-unread-title)
                  "  "
                  (propertize (format "(%s)" type-label) 'face 'gh-radar-dashboard-meta)
                  "\n")
          (let ((rel-time (when time
                            (ignore-errors
                              (gh-radar-dashboard--time-ago (parse-iso8601-time-string time))))))
            (insert "       "
                    (propertize (format "in %s by @%s%s"
                                        repo
                                        (or author "ghost")
                                        (if rel-time (format " · %s" rel-time) ""))
                                'face 'gh-radar-dashboard-meta)
                    "\n\n"))
          (let ((end (point)))
            (put-text-property beg end 'gh-radar-item data)
            (push (list beg end data) gh-radar-dashboard--rows)))))))

(defun gh-radar-dashboard--insert-header ()
  "Insert the dashboard banner, statistics, and rule."
  (let* ((width (gh-radar-dashboard-width))
         (tot-issues 0)
         (tot-prs 0)
         (tot-new-issues 0)
         (tot-new-prs 0)
         (tot-repos (length gh-radar-state-data))
         (inbox-cnt (when (and gh-radar-track-notifications gh-radar-state-notifications)
                      (or (plist-get gh-radar-state-notifications :count) 0)))
         (inbox-new (when (and gh-radar-track-notifications gh-radar-state-notifications)
                      (or (plist-get gh-radar-state-notifications :new) 0)))
         (only-new (memq gh-radar-count-display '(new only-new)))
         (meta-parts (list (format "Tracking %d repositories" tot-repos))))
    (dolist (item gh-radar-state-data)
      (let ((data (cdr item)))
        (setq tot-issues (+ tot-issues (or (plist-get data :issues) 0)))
        (setq tot-prs (+ tot-prs (or (plist-get data :pr) 0)))
        (setq tot-new-issues (+ tot-new-issues (or (plist-get data :new-issues) 0)))
        (setq tot-new-prs (+ tot-new-prs (or (plist-get data :new-pr) 0)))))
    (when inbox-cnt
      (push (if only-new
                (format "%s%d unread notifications" (if (> (or inbox-new 0) 0) "+" "") (or inbox-new 0))
              (format "%d unread notifications" inbox-cnt))
            meta-parts))
    (if only-new
        (progn
          (push (format "%s%d new issues" (if (> tot-new-issues 0) "+" "") tot-new-issues) meta-parts)
          (push (format "%s%d new PRs" (if (> tot-new-prs 0) "+" "") tot-new-prs) meta-parts))
      (push (format "%d open issues" tot-issues) meta-parts)
      (push (format "%d open PRs" tot-prs) meta-parts))
    (insert "  "
            (propertize "gh-radar" 'face 'gh-radar-dashboard-title)
            "\n"
            "  "
            (propertize (string-join (nreverse meta-parts) " · ")
                        'face 'gh-radar-dashboard-meta)
            "\n\n"
            "  "
            (propertize "[d] Dismiss   [D] Dismiss all   [RET] Open"
                        'face 'gh-radar-dashboard-meta)
            "\n"
            "  "
            (propertize "[i] Issues   [p] PRs   [n] Notifications"
                        'face 'gh-radar-dashboard-meta)
            "\n"
            "  "
            (propertize "[s] Settings   [?] Help   [q] Quit"
                        'face 'gh-radar-dashboard-meta)
            "\n"
            "  "
            (propertize (make-string width ?─) 'face 'gh-radar-dashboard-separator)
            "\n\n")))

(defun gh-radar-dashboard--insert-row (item)
  "Insert a single repository entry for ITEM ((REPO . PLIST)) and record bounds."
  (let* ((repo (car item))
         (data (append (list :repo repo) (cdr item)))
         (issues (or (plist-get data :issues) 0))
         (prs (or (plist-get data :pr) 0))
         (new-issues (or (plist-get data :new-issues) 0))
         (new-prs (or (plist-get data :new-pr) 0))
         (time (plist-get data :timestamp))
         (only-new (memq gh-radar-count-display '(new only-new)))
         (repo-icon (gh-radar-dashboard--icon "nf-oct-repo" "GH" 'gh-radar-dashboard-repo))
         (issue-icon (gh-radar-dashboard--icon "nf-oct-issue_opened" "#" 'gh-radar-issue-face))
         (pr-icon (gh-radar-dashboard--icon "nf-oct-git_pull_request" "PR" 'gh-radar-pr-face))
         (beg (point)))
    (insert "  " repo-icon "  " (propertize repo 'face 'gh-radar-dashboard-repo) "\n")
    (if only-new
        (insert "     "
                issue-icon " "
                (propertize (format "%s%d new issues" (if (> new-issues 0) "+" "") new-issues)
                            'face (if (> new-issues 0) 'gh-radar-new-face 'gh-radar-issue-face))
                "    "
                pr-icon " "
                (propertize (format "%s%d new PRs" (if (> new-prs 0) "+" "") new-prs)
                            'face (if (> new-prs 0) 'gh-radar-new-face 'gh-radar-pr-face))
                "    "
                (propertize (format "· updated %s" (gh-radar-dashboard--time-ago time))
                            'face 'gh-radar-dashboard-meta)
                "\n\n")
      (insert "     "
              issue-icon " "
              (propertize (format "%d issues" issues) 'face 'gh-radar-issue-face)
              (if (> new-issues 0)
                  (format " %s" (propertize (format "(+%d)" new-issues) 'face 'gh-radar-new-face))
                "")
              "    "
              pr-icon " "
              (propertize (format "%d PRs" prs) 'face 'gh-radar-pr-face)
              (if (> new-prs 0)
                  (format " %s" (propertize (format "(+%d)" new-prs) 'face 'gh-radar-new-face))
                "")
              "    "
              (propertize (format "· updated %s" (gh-radar-dashboard--time-ago time))
                          'face 'gh-radar-dashboard-meta)
              "\n\n"))
    (let ((end (point)))
      (put-text-property beg end 'gh-radar-item data)
      (push (list beg end data) gh-radar-dashboard--rows))))

(defun gh-radar-dashboard--insert-inbox ()
  "Insert an interactive row for GitHub notifications inbox."
  (when gh-radar-track-notifications
    (let* ((cnt (if gh-radar-state-notifications (or (plist-get gh-radar-state-notifications :count) 0) 0))
           (new-cnt (if gh-radar-state-notifications (or (plist-get gh-radar-state-notifications :new) 0) 0))
           (time (when gh-radar-state-notifications (plist-get gh-radar-state-notifications :timestamp)))
           (inbox-icon (gh-radar-dashboard--icon "nf-oct-inbox" "@" 'gh-radar-inbox-face))
           (data (list :inbox t :count cnt :new new-cnt :timestamp time))
           (beg (point)))
      (insert "  " inbox-icon "  " (propertize "Inbox (Notifications)" 'face 'gh-radar-dashboard-repo) "\n")
      (insert "     "
              (propertize (format "%d unread notifications" cnt) 'face 'gh-radar-inbox-face)
              (if (> new-cnt 0)
                  (format " %s" (propertize (format "(+%d)" new-cnt) 'face 'gh-radar-new-face))
                "")
              "    "
              (propertize (format "· updated %s" (gh-radar-dashboard--time-ago time))
                          'face 'gh-radar-dashboard-meta)
              "\n\n")
      (let ((end (point)))
        (put-text-property beg end 'gh-radar-item data)
        (push (list beg end data) gh-radar-dashboard--rows)))))

(defun gh-radar-dashboard-render ()
  "Render the whole radar dashboard buffer."
  (let ((inhibit-read-only t)
        (win (get-buffer-window (current-buffer)))
        (orig-line (line-number-at-pos (point)))
        (orig-col (current-column)))
    (setq gh-radar-dashboard--rows nil)
    (when (overlayp gh-radar-dashboard--highlight)
      (delete-overlay gh-radar-dashboard--highlight))
    (erase-buffer)
    (gh-radar-dashboard--insert-header)
    (gh-radar-dashboard--insert-inbox)
    (gh-radar-dashboard--insert-unread-section)
    (if (null gh-radar-state-data)
        (unless gh-radar-track-notifications
          (insert "  " (propertize "No repository data available. Press 'g' to refresh."
                                   'face 'gh-radar-dashboard-meta)
                  "\n"))
      (when (gh-radar-state-unread-items)
        (insert "  "
                (propertize "Tracked Repositories" 'face 'gh-radar-dashboard-section-header)
                "\n"
                "  "
                (propertize (make-string (gh-radar-dashboard-width) ?─) 'face 'gh-radar-dashboard-separator)
                "\n\n"))
      (dolist (item gh-radar-state-data)
        (gh-radar-dashboard--insert-row item)))
    (setq gh-radar-dashboard--rows (nreverse gh-radar-dashboard--rows))
    (goto-char (point-min))
    (forward-line (1- orig-line))
    (move-to-column orig-col)
    (when (and gh-radar-dashboard--rows (null (gh-radar-dashboard--row-at-point)))
      (goto-char (car (car gh-radar-dashboard--rows))))
    (when win (set-window-point win (point)))
    (gh-radar-dashboard--update-highlight)))

(defun gh-radar-dashboard-refresh-buffer ()
  "Trigger asynchronous radar query and re-render dashboard."
  (interactive)
  (message "[gh-radar] Refreshing...")
  (gh-radar-process-fetch
   (lambda (_data)
     (when-let* ((buf (get-buffer "*gh-radar*")))
       (when (buffer-live-p buf)
         (with-current-buffer buf
           (gh-radar-dashboard-render))))
     (message "[gh-radar] Refresh complete."))))

(defun gh-radar-dashboard-help ()
  "Display a popup side window listing dashboard key bindings."
  (interactive)
  (let ((buf (get-buffer-create "*gh-radar help*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (propertize "gh-radar dashboard keys\n" 'face 'gh-radar-dashboard-title))
        (insert (propertize "Press RET or action key on a repository row.\n\n"
                            'face 'gh-radar-dashboard-meta))
        (insert (propertize "Navigation\n" 'face 'gh-radar-dashboard-repo))
        (insert "  j, <down>    Next row\n")
        (insert "  k, <up>      Previous row\n\n")
        (insert (propertize "Actions\n" 'face 'gh-radar-dashboard-repo))
        (insert "  RET          Open repository page or unread item\n")
        (insert "  s            Open settings\n")
        (insert "  d, x         Dismiss unread item\n")
        (insert "  D, X         Dismiss all unread items\n")
        (insert "  i            Open repository issues\n")
        (insert "  p, P         Open repository pull requests\n")
        (insert "  n, N         Open GitHub notifications\n")
        (insert "  g, r         Refresh radar metrics\n\n")
        (insert (propertize "General\n" 'face 'gh-radar-dashboard-repo))
        (insert "  ?            Show this help\n")
        (insert "  q            Close window\n\n")
        (insert (propertize "Press q to close this window.\n"
                            'face 'gh-radar-dashboard-meta)))
      (special-mode)
      (local-set-key (kbd "q") #'quit-window)
      (local-set-key (kbd "?") #'quit-window)
      (goto-char (point-min)))
    (display-buffer buf
                    '((display-buffer-in-side-window)
                      (side . right)
                      (window-width . 46)))
    (select-window (get-buffer-window buf))))

(defvar gh-radar-dashboard-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "j") #'gh-radar-dashboard-next-row)
    (define-key map (kbd "k") #'gh-radar-dashboard-previous-row)
    (define-key map (kbd "<down>") #'gh-radar-dashboard-next-row)
    (define-key map (kbd "<up>") #'gh-radar-dashboard-previous-row)
    (define-key map (kbd "RET") #'gh-radar-dashboard-open-at-point)
    (define-key map [return] #'gh-radar-dashboard-open-at-point)
    (define-key map (kbd "s") #'gh-radar-settings)
    (define-key map (kbd "d") #'gh-radar-dashboard-dismiss)
    (define-key map (kbd "x") #'gh-radar-dashboard-dismiss)
    (define-key map (kbd "D") #'gh-radar-dashboard-dismiss-all)
    (define-key map (kbd "X") #'gh-radar-dashboard-dismiss-all)
    (define-key map (kbd "i") #'gh-radar-dashboard-open-issues)
    (define-key map (kbd "p") #'gh-radar-dashboard-open-pulls)
    (define-key map (kbd "P") #'gh-radar-dashboard-open-pulls)
    (define-key map (kbd "n") #'gh-radar-dashboard-open-notifications)
    (define-key map (kbd "N") #'gh-radar-dashboard-open-notifications)
    (define-key map (kbd "g") #'gh-radar-dashboard-refresh-buffer)
    (define-key map (kbd "r") #'gh-radar-dashboard-refresh-buffer)
    (define-key map (kbd "C-c g") #'gh-radar-dashboard-refresh-buffer)
    (define-key map (kbd "C-c C-g") #'gh-radar-dashboard-refresh-buffer)
    (define-key map (kbd "?") #'gh-radar-dashboard-help)
    (define-key map (kbd "q") #'gh-radar-dashboard-quit)
    (define-key map [mouse-1] #'gh-radar-dashboard-open-at-point)
    map)
  "Keymap for `gh-radar-dashboard-mode'.")

(define-derived-mode gh-radar-dashboard-mode special-mode "GH-Radar"
  "Major mode for the gh-radar repository dashboard."
  :group 'gh-radar
  (setq-local truncate-lines nil)
  (setq-local cursor-type nil)
  (setq-local display-line-numbers nil)
  (when (fboundp 'display-line-numbers-mode)
    (display-line-numbers-mode -1))
  (setq-local buffer-read-only t)
  (setq-local revert-buffer-function
              (lambda (&rest _) (gh-radar-dashboard-refresh-buffer)))
  (add-hook 'post-command-hook #'gh-radar-dashboard--update-highlight nil t)
  (add-hook 'kill-buffer-hook
            (lambda ()
              (when (overlayp gh-radar-dashboard--highlight)
                (delete-overlay gh-radar-dashboard--highlight)))
            nil t))

(with-eval-after-load 'evil
  (dolist (state '(normal motion))
    (evil-make-overriding-map gh-radar-dashboard-mode-map state)
    (evil-define-key state gh-radar-dashboard-mode-map
      (kbd "j") #'gh-radar-dashboard-next-row
      (kbd "k") #'gh-radar-dashboard-previous-row
      (kbd "<down>") #'gh-radar-dashboard-next-row
      (kbd "<up>") #'gh-radar-dashboard-previous-row
      (kbd "RET") #'gh-radar-dashboard-open-at-point
      (kbd "s") #'gh-radar-settings
      (kbd "d") #'gh-radar-dashboard-dismiss
      (kbd "x") #'gh-radar-dashboard-dismiss
      (kbd "D") #'gh-radar-dashboard-dismiss-all
      (kbd "X") #'gh-radar-dashboard-dismiss-all
      (kbd "i") #'gh-radar-dashboard-open-issues
      (kbd "p") #'gh-radar-dashboard-open-pulls
      (kbd "P") #'gh-radar-dashboard-open-pulls
      (kbd "n") #'gh-radar-dashboard-open-notifications
      (kbd "N") #'gh-radar-dashboard-open-notifications
      (kbd "w") nil
      (kbd "b") nil
      (kbd "g") #'gh-radar-dashboard-refresh-buffer
      (kbd "r") #'gh-radar-dashboard-refresh-buffer
      (kbd "?") #'gh-radar-dashboard-help
      (kbd "q") #'gh-radar-dashboard-quit)))

(defvar-local gh-radar-dashboard--prev-win-conf nil
  "Saved window configuration prior to opening dashboard fullscreen.")

(defun gh-radar-dashboard-quit ()
  "Quit the dashboard window and restore previous layout."
  (interactive)
  (let ((conf gh-radar-dashboard--prev-win-conf)
        (buf (current-buffer)))
    (if (and conf (window-configuration-p conf))
        (progn
          (set-window-configuration conf)
          (when (buffer-live-p buf)
            (bury-buffer buf)))
      (quit-window t))))

;;;###autoload
(defun gh-radar-dashboard ()
  "Open the interactive gh-radar dashboard buffer."
  (interactive)
  (let* ((buf (get-buffer-create "*gh-radar*"))
         (orig-conf (unless (eq (current-buffer) buf)
                      (current-window-configuration))))
    (with-current-buffer buf
      (unless (derived-mode-p 'gh-radar-dashboard-mode)
        (gh-radar-dashboard-mode))
      (when orig-conf
        (setq gh-radar-dashboard--prev-win-conf orig-conf))
      (gh-radar-dashboard-render))
    (pcase gh-radar-dashboard-display-style
      ('full-window
       (delete-other-windows)
       (switch-to-buffer buf))
      ('same-window
       (switch-to-buffer buf))
      ('pop-to-buffer
       (pop-to-buffer buf))
      (_
       (delete-other-windows)
       (switch-to-buffer buf)))))

(defun gh-radar-dashboard--auto-refresh-buffer (&rest _)
  "Update *gh-radar* buffer if currently alive."
  (when-let* ((buf (get-buffer "*gh-radar*")))
    (when (buffer-live-p buf)
      (with-current-buffer buf
        (gh-radar-dashboard-render)))))

(add-hook 'gh-radar-update-hook #'gh-radar-dashboard--auto-refresh-buffer)

(provide 'gh-radar-dashboard)
;;; gh-radar-dashboard.el ends here
