;;; gh-radar-dashboard.el --- Dashboard for gh-radar -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Szymon Wilczek
;; Author: Szymon Wilczek <swilczek.lx@gmail.com>
;; License: GPL-3.0-or-later

;;; Commentary:
;; Dashboard buffer displaying monitored repositories, issues,
;; and pull requests metrics with keyboard navigation and actions.

;;; Code:

(require 'cl-lib)
(require 'gh-radar-config)
(require 'gh-radar-state)

(declare-function evil-define-key "evil-core" (state keymap key def &rest bindings))
(declare-function evil-make-overriding-map "evil-core" (keymap &optional state copy))
(declare-function octo-dashboard-open "octo-dashboard" (owner repo &optional tab))

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

(provide 'gh-radar-dashboard)
;;; gh-radar-dashboard.el ends here
