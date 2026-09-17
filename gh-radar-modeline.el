;;; gh-radar-modeline.el --- Mode-line presentation for gh-radar -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Szymon Wilczek
;; Author: Szymon Wilczek <swilczek.lx@gmail.com>
;; License: GPL-3.0-or-later

;;; Commentary:
;; Renders mode-line segments with GitHub issue and PR metrics.

;;; Code:

(require 'gh-radar-config)
(require 'gh-radar-state)

(declare-function nerd-icons-octicon "nerd-icons")
(declare-function gh-radar-refresh "gh-radar")

(defun gh-radar-modeline--icon (name fallback)
  "Resolve nerd-icon NAME or return FALLBACK string."
  (if (and (fboundp 'nerd-icons-octicon) (display-graphic-p))
      (nerd-icons-octicon name)
    fallback))

(defun gh-radar-modeline--tooltip ()
  "Construct detailed tooltip text for current radar state."
  (if (null gh-radar-state-data)
      "gh-radar: No data (click to refresh)"
    (let ((lines nil))
      (dolist (item gh-radar-state-data)
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
      (concat "gh-radar: Monitored Repositories\n---------------------------------\n"
              (string-join (nreverse lines) "\n")))))

(defun gh-radar-modeline-format ()
  "Format `gh-radar-state-data` into a propertized string for the mode-line."
  (when gh-radar-state-data
    (let* ((tot-issues 0)
           (tot-prs 0)
           (tot-new-issues 0)
           (tot-new-prs 0))
      (dolist (item gh-radar-state-data)
        (let ((data (cdr item)))
          (setq tot-issues (+ tot-issues (or (plist-get data :issues) 0)))
          (setq tot-prs (+ tot-prs (or (plist-get data :pr) 0)))
          (setq tot-new-issues (+ tot-new-issues (or (plist-get data :new-issues) 0)))
          (setq tot-new-prs (+ tot-new-prs (or (plist-get data :new-pr) 0)))))
      (let* ((prefix-str (when gh-radar-show-prefix
                           (format "%s  " (propertize (gh-radar-modeline--icon "nf-oct-mark_github" "GH")
                                                      'face 'gh-radar-prefix-face))))
             (issue-icon (gh-radar-modeline--icon "nf-oct-issue_opened" "#"))
             (pr-icon (gh-radar-modeline--icon "nf-oct-git_pull_request" "PR"))
             (map (let ((km (make-sparse-keymap)))
                    (define-key km [mode-line mouse-1] (lambda () (interactive) (message (gh-radar-modeline--tooltip))))
                    km))
             (str (format " %s%s %d%s %s %d%s"
                          (or prefix-str "")
                          issue-icon tot-issues
                          (if (> tot-new-issues 0)
                              (propertize (format " (+%d)" tot-new-issues) 'face 'gh-radar-new-face)
                            "")
                          pr-icon tot-prs
                          (if (> tot-new-prs 0)
                              (propertize (format " (+%d)" tot-new-prs) 'face 'gh-radar-new-face)
                            ""))))
        (propertize str
                    'mouse-face 'mode-line-highlight
                    'local-map map
                    'help-echo (gh-radar-modeline--tooltip))))))

(provide 'gh-radar-modeline)
;;; gh-radar-modeline.el ends here
