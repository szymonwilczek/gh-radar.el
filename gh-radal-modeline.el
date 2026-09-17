;;; gh-radal-modeline.el --- Mode-line presentation for gh-radal -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Szymon Wilczek
;; Author: Szymon Wilczek <swilczek.lx@gmail.com>
;; License: GPL-3.0-or-later

;;; Commentary:
;; Renders interactive mode-line segments with GitHub issue and PR metrics.

;;; Code:

(require 'gh-radal-config)
(require 'gh-radal-state)

(declare-function nerd-icons-octicon "nerd-icons")
(declare-function gh-radal-refresh "gh-radal")

(defun gh-radal-modeline--icon (name fallback)
  "Resolve nerd-icon NAME or return FALLBACK string."
  (if (and (fboundp 'nerd-icons-octicon) (display-graphic-p))
      (nerd-icons-octicon name)
    fallback))

(defun gh-radal-modeline--tooltip ()
  "Construct detailed tooltip text for current radar state."
  (if (null gh-radal-state-data)
      "gh-radal: No data (click to refresh)"
    (let ((lines '("gh-radal: Monitored Repositories\n---------------------------------")))
      (dolist (item gh-radal-state-data)
        (let* ((repo (car item))
               (data (cdr item))
               (issues (or (plist-get data :issues) 0))
               (prs (or (plist-get data :pr) 0))
               (new-i (or (plist-get data :new-issues) 0))
               (new-p (or (plist-get data :new-pr) 0)))
          (push (format "%s: %d issues%s, %d PRs%s"
                        repo issues (if (> new-i 0) (format " (+%d)" new-i) "")
                        prs (if (> new-p 0) (format " (+%d)" new-p) ""))
                lines)))
      (string-join (nreverse lines) "\n"))))

(defun gh-radal-modeline-format ()
  "Format `gh-radal-state-data` into a propertized string for the mode-line."
  (when gh-radal-state-data
    (let* ((tot-issues 0)
           (tot-prs 0)
           (tot-new-issues 0)
           (tot-new-prs 0))
      (dolist (item gh-radal-state-data)
        (let ((data (cdr item)))
          (setq tot-issues (+ tot-issues (or (plist-get data :issues) 0)))
          (setq tot-prs (+ tot-prs (or (plist-get data :pr) 0)))
          (setq tot-new-issues (+ tot-new-issues (or (plist-get data :new-issues) 0)))
          (setq tot-new-prs (+ tot-new-prs (or (plist-get data :new-pr) 0)))))
      (let* ((icon (gh-radal-modeline--icon "nf-oct-mark_github" "GH"))
             (issue-icon (gh-radal-modeline--icon "nf-oct-issue_opened" "#"))
             (pr-icon (gh-radal-modeline--icon "nf-oct-git_pull_request" "PR"))
             (map (let ((km (make-sparse-keymap)))
                    (define-key km [mode-line mouse-1] (lambda () (interactive) (message (gh-radal-modeline--tooltip))))
                    km))
             (str (format " %s %s%d%s %s%d%s"
                          (propertize icon 'face 'gh-radal-prefix-face)
                          issue-icon tot-issues
                          (if (> tot-new-issues 0)
                              (propertize (format "(+%d)" tot-new-issues) 'face 'gh-radal-new-face)
                            "")
                          pr-icon tot-prs
                          (if (> tot-new-prs 0)
                              (propertize (format "(+%d)" tot-new-prs) 'face 'gh-radal-new-face)
                            ""))))
        (propertize str
                    'mouse-face 'mode-line-highlight
                    'local-map map
                    'help-echo (gh-radal-modeline--tooltip))))))

(provide 'gh-radal-modeline)
;;; gh-radal-modeline.el ends here
