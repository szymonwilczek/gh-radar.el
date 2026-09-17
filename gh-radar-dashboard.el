;;; gh-radar-dashboard.el --- Dashboard for gh-radar -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Szymon Wilczek
;; Author: Szymon Wilczek <swilczek.lx@gmail.com>
;; License: GPL-3.0-or-later

;;; Commentary:
;; Dashboard buffer displaying monitored repositories, issues,
;; and pull requests metrics with keyboard navigation and actions.

;;; Code:

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

(provide 'gh-radar-dashboard)
;;; gh-radar-dashboard.el ends here
