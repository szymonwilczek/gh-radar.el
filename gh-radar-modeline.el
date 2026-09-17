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
(declare-function gh-radar-dashboard "gh-radar-dashboard")

(defun gh-radar-modeline--icon (name fallback)
  "Resolve nerd-icon NAME or return FALLBACK string."
  (if (and (fboundp 'nerd-icons-octicon) (display-graphic-p))
      (nerd-icons-octicon name)
    fallback))

(defun gh-radar-modeline--tooltip ()
  "Construct detailed tooltip text for current radar state."
  (if (and (null gh-radar-state-data) (null gh-radar-state-notifications))
      "gh-radar: No data (click to refresh)"
    (let ((lines nil))
      (when (and gh-radar-track-notifications gh-radar-state-notifications)
        (let* ((cnt (or (plist-get gh-radar-state-notifications :count) 0))
               (new-cnt (or (plist-get gh-radar-state-notifications :new) 0)))
          (push (format "Inbox: %d unread%s"
                        cnt
                        (if (> new-cnt 0) (format " (+%d)" new-cnt) ""))
                lines)))
      (when gh-radar-state-data
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
                  lines))))
      (concat "gh-radar\n---------------------------------\n"
              (string-join (nreverse lines) "\n")))))

(defun gh-radar-modeline--show-icon-p (type)
  "Check if icon for TYPE (`:inbox', `:issue', or `:pr') should be displayed."
  (and (if (boundp 'gh-radar-modeline-icons)
           (let ((sym (pcase type (:inbox 'inbox) (:issue 'issues) (:pr 'pr))))
             (or (memq sym gh-radar-modeline-icons)
                 (memq type gh-radar-modeline-icons)))
         t)
       (pcase type
         (:inbox gh-radar-show-inbox-icon)
         (:issue gh-radar-show-issue-icon)
         (:pr gh-radar-show-pr-icon)
         (_ t))))

(defun gh-radar-modeline-format ()
  "Format radar metrics and notifications into a mode-line string."
  (when (or gh-radar-state-data
            (and gh-radar-track-notifications gh-radar-state-notifications))
    (let ((parts nil))
      (when (and gh-radar-track-notifications gh-radar-state-notifications)
        (let* ((inbox-icon (when (gh-radar-modeline--show-icon-p :inbox)
                             (gh-radar-modeline--icon "nf-oct-inbox" "@")))
               (inbox-cnt (or (plist-get gh-radar-state-notifications :count) 0))
               (inbox-new (or (plist-get gh-radar-state-notifications :new) 0)))
          (push (format "%s%d%s"
                        (if inbox-icon (format "%s " inbox-icon) "")
                        inbox-cnt
                        (if (> inbox-new 0)
                            (propertize (format " (+%d)" inbox-new) 'face 'gh-radar-new-face)
                          ""))
                parts)))
      (when gh-radar-state-data
        (let ((tot-issues 0)
              (tot-prs 0)
              (tot-new-issues 0)
              (tot-new-prs 0))
          (dolist (item gh-radar-state-data)
            (let ((data (cdr item)))
              (setq tot-issues (+ tot-issues (or (plist-get data :issues) 0)))
              (setq tot-prs (+ tot-prs (or (plist-get data :pr) 0)))
              (setq tot-new-issues (+ tot-new-issues (or (plist-get data :new-issues) 0)))
              (setq tot-new-prs (+ tot-new-prs (or (plist-get data :new-pr) 0)))))
          (let* ((issue-icon (when (gh-radar-modeline--show-icon-p :issue)
                               (gh-radar-modeline--icon "nf-oct-issue_opened" "#")))
                 (pr-icon (when (gh-radar-modeline--show-icon-p :pr)
                            (gh-radar-modeline--icon "nf-oct-git_pull_request" "PR"))))
            (push (format "%s%d%s"
                          (if issue-icon (format "%s " issue-icon) "")
                          tot-issues
                          (if (> tot-new-issues 0)
                              (propertize (format " (+%d)" tot-new-issues) 'face 'gh-radar-new-face)
                            ""))
                  parts)
            (push (format "%s%d%s"
                          (if pr-icon (format "%s " pr-icon) "")
                          tot-prs
                          (if (> tot-new-prs 0)
                              (propertize (format " (+%d)" tot-new-prs) 'face 'gh-radar-new-face)
                            ""))
                  parts))))
      (when parts
        (let* ((prefix-str (when gh-radar-show-prefix
                             (format "%s  " (propertize (gh-radar-modeline--icon "nf-oct-mark_github" "GH")
                                                        'face 'gh-radar-prefix-face))))
               (map (let ((km (make-sparse-keymap)))
                      (define-key km [mode-line mouse-1] #'gh-radar-dashboard)
                      km))
               (str (format " %s%s"
                            (or prefix-str "")
                            (string-join (nreverse parts) " "))))
          (propertize str
                      'mouse-face 'mode-line-highlight
                      'local-map map
                      'help-echo (gh-radar-modeline--tooltip)))))))

(provide 'gh-radar-modeline)
;;; gh-radar-modeline.el ends here
