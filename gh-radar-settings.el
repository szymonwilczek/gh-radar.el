;;; gh-radar-settings.el --- Settings sub-buffer for gh-radar -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Szymon Wilczek
;; Author: Szymon Wilczek <swilczek.lx@gmail.com>
;; License: GPL-3.0-or-later

;;; Commentary:
;; Dedicated settings buffer for managing monitored repositories
;; and tracking options.

;;; Code:

(require 'cl-lib)
(require 'gh-radar-config)
(require 'gh-radar-cache)
(require 'gh-radar-state)

(declare-function evil-define-key "evil-core" (state keymap key def &rest bindings))
(declare-function evil-make-overriding-map "evil-core" (keymap &optional state copy))
(declare-function gh-radar-process-fetch "gh-radar-process" (&optional callback))
(declare-function gh-radar-dashboard-render "gh-radar-dashboard" ())
(declare-function gh-radar-dashboard-width "gh-radar-dashboard" ())

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
          (overlay-put gh-radar-settings--highlight 'face 'gh-radar-dashboard-row-highlight))
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
  (let ((width (if (fboundp 'gh-radar-dashboard-width) (gh-radar-dashboard-width) 76)))
    (insert "  "
            (propertize "gh-radar Settings" 'face 'gh-radar-dashboard-title)
            "\n"
            "  "
            (propertize (format "Configuration stored in %s"
                                (abbreviate-file-name (or gh-radar-cache-file "cache")))
                        'face 'gh-radar-dashboard-meta)
            "\n\n"
            "  "
            (propertize "[a] Add repo   [i] Toggle issues   [p] Toggle PRs   [d/x] Delete repo   [n] Toggle inbox   [q] Return"
                        'face 'gh-radar-dashboard-meta)
            "\n"
            "  "
            (propertize (make-string width ?─) 'face 'gh-radar-dashboard-separator)
            "\n\n")))

(defun gh-radar-settings--insert-notifications ()
  "Insert notifications tracking toggle row."
  (let* ((enabled (gh-radar-cache-get-setting :track-notifications t))
         (beg (point)))
    (insert "  "
            (propertize "General Settings" 'face 'gh-radar-dashboard-section-header)
            "\n\n"
            "    [n]  "
            (propertize "GitHub Notifications Inbox: " 'face 'gh-radar-dashboard-unread-title)
            (if enabled
                (propertize "[ ENABLED ]" 'face 'gh-radar-settings-on)
              (propertize "[ DISABLED ]" 'face 'gh-radar-settings-off))
            "\n\n")
    (let ((end (point)))
      (push (list beg end :notifications nil) gh-radar-settings--rows))))

(defun gh-radar-settings--insert-repos ()
  "Insert repository configuration entries."
  (let* ((repos (gh-radar-cache-get-repos))
         (width (if (fboundp 'gh-radar-dashboard-width) (gh-radar-dashboard-width) 76)))
    (insert "  "
            (propertize (format "Configured Repositories (%d)" (length repos))
                        'face 'gh-radar-dashboard-section-header)
            "\n"
            "  "
            (propertize (make-string width ?─) 'face 'gh-radar-dashboard-separator)
            "\n\n")
    (if (null repos)
        (insert "    "
                (propertize "No repositories configured. Press 'a' to add a repository."
                            'face 'gh-radar-dashboard-meta)
                "\n\n")
      (dolist (entry repos)
        (let* ((repo (car entry))
               (targets (cdr entry))
               (has-issues (member "issues" targets))
               (has-pr (member "pr" targets))
               (beg (point)))
          (insert "    ●  " (propertize repo 'face 'gh-radar-dashboard-repo) "\n"
                  "       [i] Issues: "
                  (if has-issues
                      (propertize "ON " 'face 'gh-radar-settings-on)
                    (propertize "OFF" 'face 'gh-radar-settings-off))
                  "    [p] PRs: "
                  (if has-pr
                      (propertize "ON " 'face 'gh-radar-settings-on)
                    (propertize "OFF" 'face 'gh-radar-settings-off))
                  "    "
                  (propertize "[d/x] Remove" 'face 'gh-radar-dashboard-meta)
                  "\n\n")
          (let ((end (point)))
            (push (list beg end :repo repo) gh-radar-settings--rows)))))))

(defun gh-radar-settings-render ()
  "Render the settings buffer content."
  (let ((inhibit-read-only t)
        (orig-line (line-number-at-pos (point)))
        (orig-col (current-column)))
    (setq gh-radar-settings--rows nil)
    (when (overlayp gh-radar-settings--highlight)
      (delete-overlay gh-radar-settings--highlight))
    (erase-buffer)
    (gh-radar-settings--insert-header)
    (gh-radar-settings--insert-notifications)
    (gh-radar-settings--insert-repos)
    (setq gh-radar-settings--rows (nreverse gh-radar-settings--rows))
    (goto-char (point-min))
    (forward-line (1- orig-line))
    (move-to-column orig-col)
    (when (and gh-radar-settings--rows (null (gh-radar-settings--row-at-point)))
      (goto-char (car (car gh-radar-settings--rows))))
    (gh-radar-settings--update-highlight)))

(defun gh-radar-settings-add-repo (repo-name)
  "Prompt and add REPO-NAME (format \"owner/name\") to tracked repositories."
  (interactive
   (list (read-string "Add repository to track (owner/name): ")))
  (let ((cleaned (string-trim repo-name)))
    (unless (string-match-p "^[^/ \t\n\r]+/[^/ \t\n\r]+$" cleaned)
      (user-error "Invalid repository format '%s'. Must be 'owner/name'" cleaned))
    (when (assoc cleaned (gh-radar-cache-get-repos))
      (user-error "Repository '%s' is already configured" cleaned))
    (gh-radar-cache-add-repo cleaned '("issues" "pr"))
    (gh-radar-settings-render)
    (message "[gh-radar] Added %s (issues & PRs enabled)" cleaned)
    (gh-radar-process-fetch)))

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
            (let* ((entry (assoc repo (gh-radar-cache-get-repos)))
                   (state (if (member "issues" (cdr entry)) "enabled" "disabled")))
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
    (message "[gh-radar] Notifications tracking %s" (if new "enabled" "disabled"))))

(defun gh-radar-settings-smart-action ()
  "Execute the appropriate action for row at point on RET."
  (interactive)
  (if-let* ((row (gh-radar-settings--row-at-point)))
      (pcase (nth 2 row)
        (:notifications (gh-radar-settings-toggle-notifications))
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
    (define-key map (kbd "RET") #'gh-radar-settings-smart-action)
    (define-key map [return] #'gh-radar-settings-smart-action)
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
      (kbd "RET") #'gh-radar-settings-smart-action
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
