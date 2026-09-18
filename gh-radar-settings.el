;;; gh-radar-settings.el --- Settings sub-buffer -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Szymon Wilczek
;; Author: Szymon Wilczek <swilczek.lx@gmail.com>
;; License: GPL-3.0-or-later

;;; Commentary:
;; Dedicated settings buffer for managing monitored repositories
;; and tracking options.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'gh-radar-config)
(require 'gh-radar-cache)
(require 'gh-radar-state)
(require 'gh-radar-process)

(autoload 'gh-radar-dashboard-render "gh-radar-dashboard")
(autoload 'gh-radar-dashboard-width "gh-radar-dashboard")

(declare-function evil-define-key "evil-core"
                  (state keymap key def &rest bindings))
(declare-function evil-make-overriding-map "evil-core"
                  (keymap &optional state copy))

(defface gh-radar-settings-on
  '((t :inherit font-lock-keyword-face :weight bold))
  "Face for enabled setting states."
  :group 'gh-radar)

(defface gh-radar-settings-off
  '((t :inherit shadow))
  "Face for disabled setting states."
  :group 'gh-radar)

(defvar-local gh-radar-settings--rows nil
  "List of (BEG END TYPE PAYLOAD) describing interactive settings rows.")

(defvar-local gh-radar-settings--highlight nil
  "Overlay highlighting active settings row at point.")

(defvar-local gh-radar-settings--prev-win-conf nil
  "Saved window configuration prior to opening settings buffer.")

(defun gh-radar-settings--row-at-point ()
  "Return (BEG END TYPE PAYLOAD) row tuple containing point, or nil."
  (let ((pos (point)))
    (cl-find-if (lambda (row) (and (>= pos (nth 0 row)) (< pos (nth 1 row))))
                gh-radar-settings--rows)))

(defun gh-radar-settings--update-highlight ()
  "Move highlight overlay to row at point."
  (if-let* ((row (gh-radar-settings--row-at-point)))
      (let ((beg (nth 0 row))
            (end (nth 1 row)))
        (unless (overlayp gh-radar-settings--highlight)
          (setq gh-radar-settings--highlight (make-overlay beg end))
          (overlay-put gh-radar-settings--highlight
                       'face 'gh-radar-dashboard-row-highlight))
        (move-overlay gh-radar-settings--highlight beg end))
    (when (overlayp gh-radar-settings--highlight)
      (delete-overlay gh-radar-settings--highlight))))

(defun gh-radar-settings-next-row ()
  "Move point to the beginning of next settings row."
  (interactive)
  (let* ((cur (gh-radar-settings--row-at-point))
         (pos (point))
         (next (cl-find-if (lambda (r) (> (nth 0 r) (if cur (nth 0 cur) pos)))
                           gh-radar-settings--rows)))
    (when next
      (goto-char (nth 0 next))
      (gh-radar-settings--update-highlight))))

(defun gh-radar-settings-previous-row ()
  "Move point to the beginning of previous settings row."
  (interactive)
  (let* ((cur (gh-radar-settings--row-at-point))
         (pos (point))
         (prev (car (last (cl-remove-if-not
                           (lambda (r) (< (nth 0 r) (if cur (nth 0 cur) pos)))
                           gh-radar-settings--rows)))))
    (when prev
      (goto-char (nth 0 prev))
      (gh-radar-settings--update-highlight))))

(defun gh-radar-settings--insert-header ()
  "Insert title banner, file location, and key actions into settings buffer."
  (let ((width (if (fboundp 'gh-radar-dashboard-width)
                   (gh-radar-dashboard-width)
                 76)))
    (insert "  "
            (propertize "gh-radar Settings" 'face 'gh-radar-dashboard-title)
            "\n"
            "  "
            (propertize (format "Configuration stored in %s"
                                (abbreviate-file-name
                                 (or gh-radar-cache-file "cache")))
                        'face 'gh-radar-dashboard-meta)
            "\n\n"
            "  "
            (propertize
             "[a] Add repo          [d] Delete repo     [c] Display mode"
             'face 'gh-radar-dashboard-meta)
            "\n"
            "  "
            (propertize
             "[i] Toggle Issues    [p] Toggle PRs     [n] Toggle Notifications"
             'face 'gh-radar-dashboard-meta)
            "\n"
            "  "
            (propertize
             "[b] Bell mode         [z] Hide zeros      [h] GitHub host"
             'face 'gh-radar-dashboard-meta)
            "\n"
            "  "
            (propertize
             "[l] Items limit       [?] Help            [q] Return to dashboard"
             'face 'gh-radar-dashboard-meta)
            "\n"
            "  "
            (propertize (make-string width ?─)
                        'face 'gh-radar-dashboard-separator)
            "\n\n")))

(defun gh-radar-settings--insert-notifications ()
  "Insert notifications tracking toggle row."
  (let* ((enabled (gh-radar-cache-get-setting :track-notifications t))
         (beg (point)))
    (insert "  "
            (propertize "General Settings"
                        'face 'gh-radar-dashboard-section-header)
            "\n\n"
            "    [n]  "
            (propertize (format "%-30s" "GitHub Notifications Inbox:")
                        'face 'gh-radar-dashboard-unread-title)
            (if enabled
                (propertize "[ ENABLED ]" 'face 'gh-radar-settings-on)
              (propertize "[ DISABLED ]" 'face 'gh-radar-settings-off))
            "\n\n")
    (let ((end (point)))
      (push (list beg end :notifications nil) gh-radar-settings--rows))))

(defun gh-radar-settings--insert-count-display ()
  "Insert count display mode toggle row."
  (let* ((mode (gh-radar-cache-get-setting :count-display 'all))
         (is-new (memq mode '(new only-new)))
         (beg (point)))
    (insert "    [c]  "
            (propertize (format "%-30s" "Modeline Count Mode:")
                        'face 'gh-radar-dashboard-unread-title)
            (if is-new
                (propertize "[ ONLY NEW (+Delta) ]" 'face 'gh-radar-settings-on)
              (propertize "[ ALL (Total + New) ]" 'face 'gh-radar-settings-off))
            "\n\n")
    (let ((end (point)))
      (push (list beg end :count-display nil) gh-radar-settings--rows))))

(defun gh-radar-settings--insert-bell-modeline ()
  "Insert bell modeline style toggle row."
  (let* ((bell (gh-radar-cache-get-setting :bell-modeline
                                           gh-radar-bell-modeline))
         (beg (point)))
    (insert "    [b]  "
            (propertize (format "%-30s" "Modeline Bell Style:")
                        'face 'gh-radar-dashboard-unread-title)
            (if bell
                (propertize "[ ENABLED ]" 'face 'gh-radar-settings-on)
              (propertize "[ DISABLED ]" 'face 'gh-radar-settings-off))
            "\n\n")
    (let ((end (point)))
      (push (list beg end :bell-modeline nil) gh-radar-settings--rows))))

(defun gh-radar-settings--insert-hide-zero-counts ()
  "Insert hide-zero-counts toggle row."
  (let* ((mode (gh-radar-cache-get-setting :hide-zero-counts
                                           gh-radar-hide-zero-counts))
         (beg (point)))
    (insert "    [z]  "
            (propertize (format "%-30s" "Hide Zero Counts:")
                        'face 'gh-radar-dashboard-unread-title)
            (pcase mode
              ('t (propertize "[ ALL ]" 'face 'gh-radar-settings-on))
              ('(inbox)
               (propertize "[ INBOX ONLY ]" 'face 'gh-radar-settings-on))
              (_ (propertize "[ DISABLED ]" 'face 'gh-radar-settings-off)))
            "\n\n")
    (let ((end (point)))
      (push (list beg end :hide-zero-counts nil) gh-radar-settings--rows))))

(defun gh-radar-settings--insert-host ()
  "Insert GitHub host configuration row."
  (let* ((host (or gh-radar-github-host
                   (gh-radar-cache-get-setting :github-host "github.com")))
         (beg (point)))
    (insert "    [h]  "
            (propertize (format "%-30s" "GitHub Host:")
                        'face 'gh-radar-dashboard-unread-title)
            (propertize (format "[ %s ]" host) 'face 'gh-radar-dashboard-meta)
            "\n\n")
    (let ((end (point)))
      (push (list beg end :host nil) gh-radar-settings--rows))))

(defun gh-radar-settings--insert-limit ()
  "Insert recent items limit configuration row."
  (let* ((limit (or gh-radar-recent-items-limit
                    (gh-radar-cache-get-setting :recent-items-limit 10)))
         (beg (point)))
    (insert "    [l]  "
            (propertize (format "%-30s" "Recent Items Limit:")
                        'face 'gh-radar-dashboard-unread-title)
            (propertize (format "[ %d ]" limit)
                        'face 'gh-radar-dashboard-meta)
            "\n\n")
    (let ((end (point)))
      (push (list beg end :limit nil) gh-radar-settings--rows))))

(defun gh-radar-settings--insert-icons ()
  "Insert icon glyph configuration entries."
  (let ((types '((inbox . "Inbox Icon")
                 (issues . "Issues Icon")
                 (pr . "Pull Requests Icon")
                 (bell . "Modeline Bell Icon")
                 (repo . "Repository Icon")))
        (width (if (fboundp 'gh-radar-dashboard-width)
                   (gh-radar-dashboard-width)
                 76)))
    (insert "  "
            (propertize
             "Icon Glyphs (press RET or 'I' to customize)"
             'face 'gh-radar-dashboard-section-header)
            "\n"
            "  "
            (propertize (make-string width ?─)
                        'face 'gh-radar-dashboard-separator)
            "\n\n")
    (dolist (entry types)
      (let* ((sym (car entry))
             (label (cdr entry))
             (beg (point))
             (cur-val (cdr (or (assq sym
                                     (gh-radar-cache-get-setting :icons nil))
                               (assq sym gh-radar-icons)
                               '(nil . ""))))
             (glyph (gh-radar-icon sym)))
        (insert "    [RET]  "
                (propertize (format "%-24s" (concat label ":"))
                            'face 'gh-radar-dashboard-unread-title)
                (format "%s  "
                        (propertize glyph 'face 'gh-radar-dashboard-repo))
                (propertize (format "[ %s ]" cur-val)
                            'face 'gh-radar-dashboard-meta)
                "\n\n")
        (let ((end (point)))
          (push (list beg end :icon sym) gh-radar-settings--rows))))))

(defun gh-radar-settings--insert-repos ()
  "Insert repository configuration entries."
  (let* ((repos (gh-radar-cache-get-repos))
         (width (if (fboundp 'gh-radar-dashboard-width)
                    (gh-radar-dashboard-width)
                  76)))
    (insert "  "
            (propertize (format "Configured Repositories (%d)" (length repos))
                        'face 'gh-radar-dashboard-section-header)
            "\n"
            "  "
            (propertize (make-string width ?─)
                        'face 'gh-radar-dashboard-separator)
            "\n\n")
    (if (null repos)
        (insert "    "
                (propertize
                 "No repositories configured. Press 'a' to add a repository."
                 'face 'gh-radar-dashboard-meta)
                "\n\n")
      (dolist (entry repos)
        (let* ((repo (car entry))
               (targets (cdr entry))
               (has-issues (member "issues" targets))
               (has-pr (member "pr" targets))
               (beg (point)))
          (insert "    ●  "
                  (propertize repo 'face 'gh-radar-dashboard-repo) "\n"
                  "       [i] Issues: "
                  (if has-issues
                      (propertize "ON " 'face 'gh-radar-settings-on)
                    (propertize "OFF" 'face 'gh-radar-settings-off))
                  "    [p] PRs: "
                  (if has-pr
                      (propertize "ON " 'face 'gh-radar-settings-on)
                    (propertize "OFF" 'face 'gh-radar-settings-off))
                  "    "
                  (propertize "[d] Remove" 'face 'gh-radar-dashboard-meta)
                  "\n\n")
          (let ((end (point)))
            (push (list beg end :repo repo) gh-radar-settings--rows)))))))

(defun gh-radar-settings-render (&optional buffer)
  "Render the settings buffer content into BUFFER or *gh-radar settings*."
  (with-current-buffer (or buffer
                           (if (string= (buffer-name) "*gh-radar settings*")
                               (current-buffer)
                             (get-buffer-create "*gh-radar settings*")))
    (let ((inhibit-read-only t)
          (orig-line (line-number-at-pos (point)))
          (orig-col (current-column)))
      (setq gh-radar-settings--rows nil)
      (when (overlayp gh-radar-settings--highlight)
        (delete-overlay gh-radar-settings--highlight))
      (erase-buffer)
      (gh-radar-settings--insert-header)
      (gh-radar-settings--insert-notifications)
      (gh-radar-settings--insert-count-display)
      (gh-radar-settings--insert-bell-modeline)
      (gh-radar-settings--insert-hide-zero-counts)
      (gh-radar-settings--insert-host)
      (gh-radar-settings--insert-limit)
      (gh-radar-settings--insert-icons)
      (gh-radar-settings--insert-repos)
      (setq gh-radar-settings--rows (nreverse gh-radar-settings--rows))
      (goto-char (point-min))
      (forward-line (1- orig-line))
      (move-to-column orig-col)
      (when (and gh-radar-settings--rows
                 (null (gh-radar-settings--row-at-point)))
        (goto-char (car (car gh-radar-settings--rows))))
      (gh-radar-settings--update-highlight))))

(defun gh-radar-settings-add-repo (repo-name)
  "Prompt and add REPO-NAME (format \"owner/name\") to tracked repositories."
  (interactive
   (list (read-string "Add repository to track (owner/name): ")))
  (let ((cleaned (string-trim repo-name)))
    (unless (string-match-p "^[^/ \t\n\r]+/[^/ \t\n\r]+$" cleaned)
      (user-error
       "Invalid repository format '%s'. Must be 'owner/name'" cleaned))
    (when (assoc cleaned (gh-radar-cache-get-repos))
      (user-error "Repository '%s' is already configured" cleaned))
    (message "[gh-radar] Verifying repository %s on GitHub..." cleaned)
    (let* ((output (with-temp-buffer
                     (let* ((process-environment
                             (cons (format "GH_HOST=%s"
                                           (or gh-radar-github-host
                                               "github.com"))
                                   process-environment))
                            (code (call-process
                                   gh-radar-gh-executable nil t nil
                                   "repo" "view" cleaned "--json" "name")))
                       (cons code (string-trim (buffer-string))))))
           (exit-code (car output))
           (err-msg (cdr output)))
      (unless (zerop exit-code)
        (user-error "Repository '%s' does not exist or is inaccessible: %s"
                    cleaned (if (string-empty-p err-msg) "not found" err-msg)))
      (gh-radar-cache-add-repo cleaned '("issues" "pr"))
      (gh-radar-settings-render)
      (message "[gh-radar] Added %s (issues & PRs enabled)" cleaned)
      (gh-radar-process-fetch))))

(defun gh-radar-settings-delete-repo ()
  "Remove the repository at point from radar tracking."
  (interactive)
  (if-let* ((row (gh-radar-settings--row-at-point)))
      (if (eq (nth 2 row) :repo)
          (let ((repo (nth 3 row)))
            (when (y-or-n-p (format "Remove '%s' from radar tracking? " repo))
              (gh-radar-cache-remove-repo repo)
              (setq gh-radar-state-data
                    (cl-remove-if (lambda (entry) (string= (car entry) repo))
                                  gh-radar-state-data))
              (gh-radar-settings-render)
              (run-hook-with-args 'gh-radar-update-hook gh-radar-state-data)
              (force-mode-line-update t)
              (message "[gh-radar] Removed %s from tracking" repo)))
        (user-error "Move point to a repository row to delete"))
    (user-error "No item at point")))

(defun gh-radar-settings-toggle-issues ()
  "Toggle issues tracking for the repository at point."
  (interactive)
  (if-let* ((row (gh-radar-settings--row-at-point)))
      (if (eq (nth 2 row) :repo)
          (let ((repo (nth 3 row)))
            (gh-radar-cache-toggle-target repo "issues")
            (gh-radar-settings-render)
            (force-mode-line-update t)
            (let* ((entry (assoc repo (gh-radar-cache-get-repos)))
                   (state (if (member "issues" (cdr entry))
                              "enabled"
                            "disabled")))
              (message "[gh-radar] %s: issues tracking %s" repo state)))
        (user-error "Move point to a repository row to toggle issues"))
    (user-error "No item at point")))

(defun gh-radar-settings-toggle-prs ()
  "Toggle pull requests tracking for the repository at point."
  (interactive)
  (if-let* ((row (gh-radar-settings--row-at-point)))
      (if (eq (nth 2 row) :repo)
          (let ((repo (nth 3 row)))
            (gh-radar-cache-toggle-target repo "pr")
            (gh-radar-settings-render)
            (force-mode-line-update t)
            (let* ((entry (assoc repo (gh-radar-cache-get-repos)))
                   (state (if (member "pr" (cdr entry)) "enabled" "disabled")))
              (message "[gh-radar] %s: PR tracking %s" repo state)))
        (user-error "Move point to a repository row to toggle PRs"))
    (user-error "No item at point")))

(defun gh-radar-settings-toggle-notifications ()
  "Toggle GitHub notifications inbox tracking."
  (interactive)
  (let* ((cur (gh-radar-cache-get-setting :track-notifications t))
         (new (not cur)))
    (gh-radar-cache-set-setting :track-notifications new)
    (gh-radar-settings-render)
    (run-hook-with-args 'gh-radar-update-hook gh-radar-state-data)
    (force-mode-line-update t)
    (message "[gh-radar] Notifications tracking %s"
             (if new "enabled" "disabled"))))

;;;###autoload
(defun gh-radar-settings-toggle-count-display ()
  "Toggle between displaying all counts vs only new delta counts."
  (interactive)
  (let* ((cur (gh-radar-cache-get-setting :count-display 'all))
         (new (if (memq cur '(new only-new)) 'all 'only-new)))
    (gh-radar-cache-set-setting :count-display new)
    (gh-radar-settings-render)
    (force-mode-line-update t)
    (when (fboundp 'gh-radar-dashboard-render)
      (when-let* ((dash (get-buffer "*gh-radar*")))
        (when (buffer-live-p dash)
          (with-current-buffer dash
            (gh-radar-dashboard-render)))))
    (message "[gh-radar] Modeline count mode set to: %s"
             (if (eq new 'only-new) "ONLY NEW (+Delta)" "ALL (Total + New)"))))

;;;###autoload
(defalias 'gh-radar-toggle-count-display
  #'gh-radar-settings-toggle-count-display)

;;;###autoload
(defun gh-radar-settings-toggle-bell ()
  "Toggle mode-line aggregate bell display."
  (interactive)
  (let* ((cur (gh-radar-cache-get-setting :bell-modeline
                                          gh-radar-bell-modeline))
         (new (not cur)))
    (gh-radar-cache-set-setting :bell-modeline new)
    (gh-radar-settings-render)
    (force-mode-line-update t)
    (message "[gh-radar] Modeline bell style %s"
             (if new "enabled" "disabled"))))

;;;###autoload
(defalias 'gh-radar-toggle-bell #'gh-radar-settings-toggle-bell)

;;;###autoload
(defun gh-radar-settings-toggle-hide-zeros ()
  "Cycle zero counts hiding mode (disabled -> all -> inbox only -> disabled)."
  (interactive)
  (let* ((cur (gh-radar-cache-get-setting :hide-zero-counts
                                          gh-radar-hide-zero-counts))
         (new (pcase cur
                ('nil t)
                ('t '(inbox))
                (_ nil))))
    (gh-radar-cache-set-setting :hide-zero-counts new)
    (gh-radar-settings-render)
    (force-mode-line-update t)
    (message "[gh-radar] Hide zero counts: %s"
             (pcase new
               ('t "ALL")
               ('(inbox) "INBOX ONLY")
               (_ "DISABLED")))))

;;;###autoload
(defalias 'gh-radar-toggle-hide-zeros #'gh-radar-settings-toggle-hide-zeros)

;;;###autoload
(defun gh-radar-settings-set-icon (&optional icon-type)
  "Prompt to customize icon glyph for ICON-TYPE."
  (interactive)
  (let* ((row (gh-radar-settings--row-at-point))
         (type (or icon-type
                   (when (and row (eq (nth 2 row) :icon)) (nth 3 row))
                   (intern (completing-read "Configure icon for: "
                                            '("inbox" "issues" "pr"
                                              "bell" "repo")
                                            nil t))))
         (type-sym (if (keywordp type)
                       (intern (substring (symbol-name type) 1))
                     type))
         (cur-val (cdr (or (assq type-sym
                                 (gh-radar-cache-get-setting :icons nil))
                           (assq type-sym gh-radar-icons)
                           '(nil . ""))))
         (candidates (when (fboundp 'nerd-icons--read-candidates)
                       (ignore-errors (nerd-icons--read-candidates))))
         (prompt (format "Icon for %s (current: %s): " type-sym cur-val))
         (input (if candidates
                    (completing-read prompt candidates nil nil nil nil cur-val)
                  (read-string prompt cur-val)))
         (clean-name
          (if (and input (string-match "\t+\\(nf-[^ \t\n\r]+\\)" input))
              (match-string 1 input)
            (string-trim (or input "")))))
    (when (> (length clean-name) 0)
      (gh-radar-cache-set-icon type-sym clean-name)
      (gh-radar-settings-render)
      (force-mode-line-update t)
      (when (fboundp 'gh-radar-dashboard-render)
        (when-let* ((dash (get-buffer "*gh-radar*")))
          (when (buffer-live-p dash)
            (with-current-buffer dash
              (gh-radar-dashboard-render)))))
      (message "[gh-radar] Icon for %s set to: %s" type-sym clean-name))))

;;;###autoload
(defun gh-radar-settings-set-host ()
  "Prompt to configure GitHub host domain."
  (interactive)
  (let* ((cur (or gh-radar-github-host
                  (gh-radar-cache-get-setting :github-host "github.com")))
         (new (string-trim
               (read-string (format "GitHub host (current: %s): " cur)
                            nil nil cur))))
    (when (> (length new) 0)
      (setq gh-radar-github-host new)
      (gh-radar-cache-set-setting :github-host new)
      (gh-radar-settings-render)
      (message "[gh-radar] GitHub host set to: %s" new))))

;;;###autoload
(defun gh-radar-settings-set-limit ()
  "Prompt to configure recent items limit per repository."
  (interactive)
  (let* ((cur (or gh-radar-recent-items-limit
                  (gh-radar-cache-get-setting :recent-items-limit 10)))
         (input (string-trim
                 (read-string
                  (format "Recent items limit (current: %d): " cur)
                  nil nil (number-to-string cur))))
         (val (string-to-number input)))
    (if (> val 0)
        (progn
          (setq gh-radar-recent-items-limit val)
          (gh-radar-cache-set-setting :recent-items-limit val)
          (gh-radar-settings-render)
          (message "[gh-radar] Recent items limit set to: %d" val))
      (user-error "Limit must be a positive integer"))))

(defun gh-radar-settings-smart-action ()
  "Execute the appropriate action for row at point on RET."
  (interactive)
  (if-let* ((row (gh-radar-settings--row-at-point)))
      (pcase (nth 2 row)
        (:notifications (gh-radar-settings-toggle-notifications))
        (:count-display (gh-radar-settings-toggle-count-display))
        (:bell-modeline (gh-radar-settings-toggle-bell))
        (:hide-zero-counts (gh-radar-settings-toggle-hide-zeros))
        (:host (gh-radar-settings-set-host))
        (:limit (gh-radar-settings-set-limit))
        (:icon (gh-radar-settings-set-icon (nth 3 row)))
        (:repo (gh-radar-settings-toggle-issues)))
    (gh-radar-settings-add-repo (read-string "Add repository (owner/name): "))))

(defun gh-radar-settings-quit ()
  "Close settings buffer and return to dashboard."
  (interactive)
  (let ((conf gh-radar-settings--prev-win-conf)
        (buf (current-buffer)))
    (when (fboundp 'gh-radar-dashboard-render)
      (when-let* ((dash (get-buffer "*gh-radar*")))
        (when (buffer-live-p dash)
          (with-current-buffer dash
            (gh-radar-dashboard-render)))))
    (if (and conf (window-configuration-p conf))
        (progn
          (set-window-configuration conf)
          (when (buffer-live-p buf)
            (bury-buffer buf)))
      (quit-window t))
    (message "[gh-radar] Settings saved.")))

(defun gh-radar-settings-help ()
  "Display a popup side window listing settings key bindings."
  (interactive)
  (let ((buf (get-buffer-create "*gh-radar settings help*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (propertize "gh-radar settings keys\n"
                            'face 'gh-radar-dashboard-title))
        (insert (propertize "Press RET or action key on a settings row.\n\n"
                            'face 'gh-radar-dashboard-meta))
        (insert (propertize "Navigation\n" 'face 'gh-radar-dashboard-repo))
        (insert "  j, <down>    Next row\n")
        (insert "  k, <up>      Previous row\n\n")
        (insert (propertize "General Settings\n"
                            'face 'gh-radar-dashboard-repo))
        (insert "  n, N         Toggle notifications inbox\n")
        (insert "  c, C         Cycle modeline count mode\n")
        (insert "  b, B         Toggle aggregate bell mode\n")
        (insert "  z, Z         Cycle hide zero counts\n")
        (insert "  h, H         Configure GitHub host\n")
        (insert "  l, L         Configure recent items limit\n")
        (insert "  I            Customize icon glyphs\n\n")
        (insert (propertize "Repository Management\n"
                            'face 'gh-radar-dashboard-repo))
        (insert "  a            Add repository\n")
        (insert "  d, x         Delete repository at point\n")
        (insert "  i            Toggle issues tracking for repo\n")
        (insert "  p, P         Toggle PRs tracking for repo\n\n")
        (insert (propertize "General\n" 'face 'gh-radar-dashboard-repo))
        (insert "  RET          Execute smart action on row\n")
        (insert "  g, r         Rerender settings\n")
        (insert "  ?            Show this help\n")
        (insert "  q, s         Return to dashboard\n\n")
        (insert (propertize "Press q to close this window.\n"
                            'face 'gh-radar-dashboard-meta)))
      (special-mode)
      (local-set-key (kbd "q") #'quit-window)
      (local-set-key (kbd "?") #'quit-window)
      (goto-char (point-min)))
    (display-buffer buf
                    '((display-buffer-in-side-window)
                      (side . right)
                      (window-width . 60)))
    (select-window (get-buffer-window buf))))

(defvar gh-radar-settings-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "j") #'gh-radar-settings-next-row)
    (define-key map (kbd "k") #'gh-radar-settings-previous-row)
    (define-key map (kbd "<down>") #'gh-radar-settings-next-row)
    (define-key map (kbd "<up>") #'gh-radar-settings-previous-row)
    (define-key map (kbd "a") #'gh-radar-settings-add-repo)
    (define-key map (kbd "d") #'gh-radar-settings-delete-repo)
    (define-key map (kbd "x") #'gh-radar-settings-delete-repo)
    (define-key map (kbd "i") #'gh-radar-settings-toggle-issues)
    (define-key map (kbd "p") #'gh-radar-settings-toggle-prs)
    (define-key map (kbd "P") #'gh-radar-settings-toggle-prs)
    (define-key map (kbd "n") #'gh-radar-settings-toggle-notifications)
    (define-key map (kbd "N") #'gh-radar-settings-toggle-notifications)
    (define-key map (kbd "c") #'gh-radar-settings-toggle-count-display)
    (define-key map (kbd "C") #'gh-radar-settings-toggle-count-display)
    (define-key map (kbd "b") #'gh-radar-settings-toggle-bell)
    (define-key map (kbd "B") #'gh-radar-settings-toggle-bell)
    (define-key map (kbd "z") #'gh-radar-settings-toggle-hide-zeros)
    (define-key map (kbd "Z") #'gh-radar-settings-toggle-hide-zeros)
    (define-key map (kbd "h") #'gh-radar-settings-set-host)
    (define-key map (kbd "H") #'gh-radar-settings-set-host)
    (define-key map (kbd "l") #'gh-radar-settings-set-limit)
    (define-key map (kbd "L") #'gh-radar-settings-set-limit)
    (define-key map (kbd "I") #'gh-radar-settings-set-icon)
    (define-key map (kbd "RET") #'gh-radar-settings-smart-action)
    (define-key map [return] #'gh-radar-settings-smart-action)
    (define-key map (kbd "?") #'gh-radar-settings-help)
    (define-key map (kbd "q") #'gh-radar-settings-quit)
    (define-key map (kbd "s") #'gh-radar-settings-quit)
    (define-key map (kbd "g") #'gh-radar-settings-render)
    (define-key map (kbd "r") #'gh-radar-settings-render)
    map)
  "Keymap for `gh-radar-settings-mode'.")

(define-derived-mode gh-radar-settings-mode special-mode "GH-Radar-Settings"
  "Major mode for the gh-radar settings buffer."
  :group 'gh-radar
  (setq-local truncate-lines nil)
  (setq-local cursor-type nil)
  (setq-local display-line-numbers nil)
  (when (fboundp 'display-line-numbers-mode)
    (display-line-numbers-mode -1))
  (setq-local buffer-read-only t)
  (add-hook 'post-command-hook #'gh-radar-settings--update-highlight nil t)
  (add-hook 'kill-buffer-hook
            (lambda ()
              (when (overlayp gh-radar-settings--highlight)
                (delete-overlay gh-radar-settings--highlight)))
            nil t))

(with-eval-after-load 'evil
  (dolist (state '(normal motion))
    (evil-make-overriding-map gh-radar-settings-mode-map state)
    (evil-define-key state gh-radar-settings-mode-map
      (kbd "j") #'gh-radar-settings-next-row
      (kbd "k") #'gh-radar-settings-previous-row
      (kbd "<down>") #'gh-radar-settings-next-row
      (kbd "<up>") #'gh-radar-settings-previous-row
      (kbd "a") #'gh-radar-settings-add-repo
      (kbd "d") #'gh-radar-settings-delete-repo
      (kbd "x") #'gh-radar-settings-delete-repo
      (kbd "i") #'gh-radar-settings-toggle-issues
      (kbd "p") #'gh-radar-settings-toggle-prs
      (kbd "P") #'gh-radar-settings-toggle-prs
      (kbd "n") #'gh-radar-settings-toggle-notifications
      (kbd "N") #'gh-radar-settings-toggle-notifications
      (kbd "c") #'gh-radar-settings-toggle-count-display
      (kbd "C") #'gh-radar-settings-toggle-count-display
      (kbd "b") #'gh-radar-settings-toggle-bell
      (kbd "B") #'gh-radar-settings-toggle-bell
      (kbd "z") #'gh-radar-settings-toggle-hide-zeros
      (kbd "Z") #'gh-radar-settings-toggle-hide-zeros
      (kbd "h") #'gh-radar-settings-set-host
      (kbd "H") #'gh-radar-settings-set-host
      (kbd "l") #'gh-radar-settings-set-limit
      (kbd "L") #'gh-radar-settings-set-limit
      (kbd "I") #'gh-radar-settings-set-icon
      (kbd "RET") #'gh-radar-settings-smart-action
      (kbd "?") #'gh-radar-settings-help
      (kbd "q") #'gh-radar-settings-quit
      (kbd "s") #'gh-radar-settings-quit
      (kbd "g") #'gh-radar-settings-render
      (kbd "r") #'gh-radar-settings-render)))

;;;###autoload
(defun gh-radar-settings ()
  "Open the interactive gh-radar settings buffer."
  (interactive)
  (let* ((buf (get-buffer-create "*gh-radar settings*"))
         (orig-conf (unless (eq (current-buffer) buf)
                      (current-window-configuration))))
    (with-current-buffer buf
      (unless (derived-mode-p 'gh-radar-settings-mode)
        (gh-radar-settings-mode))
      (when orig-conf
        (setq gh-radar-settings--prev-win-conf orig-conf))
      (gh-radar-settings-render))
    (pcase (bound-and-true-p gh-radar-dashboard-display-style)
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

(provide 'gh-radar-settings)
;;; gh-radar-settings.el ends here
