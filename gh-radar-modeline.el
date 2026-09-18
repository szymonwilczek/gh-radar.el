;;; gh-radar-modeline.el --- Mode-line presentation -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Szymon Wilczek
;; Author: Szymon Wilczek <swilczek.lx@gmail.com>
;; License: GPL-3.0-or-later

;;; Commentary:
;; Renders mode-line segments with GitHub issue and PR metrics.

;;; Code:

(require 'gh-radar-config)
(require 'gh-radar-cache)
(require 'gh-radar-state)

(declare-function nerd-icons-octicon "nerd-icons")
(declare-function gh-radar-refresh "gh-radar")
(declare-function gh-radar-dashboard "gh-radar-dashboard")

(defun gh-radar-modeline--icon (name fallback)
  "Resolve nerd-icon NAME or return FALLBACK string."
  (gh-radar-resolve-icon name fallback))

(defun gh-radar-modeline--target-enabled-p (target)
  "Return non-nil if TARGET (\"issues\" or \"pr\") is enabled in any repo."
  (let* ((str-target (if (symbolp target) (symbol-name target) target))
         (sym-target (intern (if (string-prefix-p ":" str-target)
                                 (substring str-target 1)
                               str-target)))
         (colon-sym-target (intern (concat ":" (symbol-name sym-target))))
         (repos (or (when (fboundp 'gh-radar-cache-get-repos)
                      (gh-radar-cache-get-repos))
                    gh-radar-repos)))
    (cl-some (lambda (entry)
               (let ((targets (cdr entry)))
                 (or (member (symbol-name sym-target) targets)
                     (member sym-target targets)
                     (member colon-sym-target targets))))
             repos)))

(defun gh-radar-modeline--repo-totals ()
  "Compute total issues, PRs, and new counts across repositories.
Returns a plist `(:issues I :prs P :new-issues NI :new-prs NP)'."
  (let ((tot-issues 0)
        (tot-prs 0)
        (tot-new-issues 0)
        (tot-new-prs 0)
        (repos (or (when (fboundp 'gh-radar-cache-get-repos)
                     (gh-radar-cache-get-repos))
                   gh-radar-repos)))
    (dolist (item gh-radar-state-data)
      (let* ((repo-name (car item))
             (entry (assoc repo-name repos))
             (targets (cdr entry))
             (track-issues
              (or (null entry)
                  (member "issues" targets)
                  (memq :issues targets)))
             (track-prs
              (or (null entry)
                  (member "pr" targets)
                  (memq :pr targets)))
             (data (cdr item)))
        (when track-issues
          (setq tot-issues (+ tot-issues (or (plist-get data :issues) 0)))
          (setq tot-new-issues
                (+ tot-new-issues (or (plist-get data :new-issues) 0))))
        (when track-prs
          (setq tot-prs (+ tot-prs (or (plist-get data :pr) 0)))
          (setq tot-new-prs (+ tot-new-prs (or (plist-get data :new-pr) 0))))))
    (list :issues tot-issues
          :prs tot-prs
          :new-issues tot-new-issues
          :new-prs tot-new-prs)))

(defun gh-radar-modeline--show-icon-p (type)
  "Check if icon for TYPE should be displayed.
TYPE can be `:inbox', `:issue', `:pr', or `:bell'."
  (if (eq type :bell)
      gh-radar-show-bell-icon
    (and (if (boundp 'gh-radar-modeline-icons)
             (let ((sym (pcase type
                          (:inbox 'inbox)
                          (:issue 'issues)
                          (:pr 'pr))))
               (or (memq sym gh-radar-modeline-icons)
                   (memq type gh-radar-modeline-icons)))
           t)
         (pcase type
           (:inbox gh-radar-show-inbox-icon)
           (:issue gh-radar-show-issue-icon)
           (:pr gh-radar-show-pr-icon)
           (_ t)))))

(defun gh-radar-modeline--hide-zero-p (type count)
  "Return non-nil if segment TYPE with COUNT should be hidden.
TYPE can be `:inbox', `:issue', `:pr', or `:bell'."
  (and (zerop count)
       (cond
        ((eq gh-radar-hide-zero-counts t) t)
        ((or (null gh-radar-hide-zero-counts)
             (eq gh-radar-hide-zero-counts 'never))
         nil)
        ((listp gh-radar-hide-zero-counts)
         (let ((sym (pcase type
                      (:inbox 'inbox)
                      (:issue 'issues)
                      (:pr 'pr)
                      (:bell 'bell))))
           (or (memq sym gh-radar-hide-zero-counts)
               (memq type gh-radar-hide-zero-counts))))
        (t nil))))

(defun gh-radar-modeline--format-segment (icon total new)
  "Format a mode-line metric segment with ICON, TOTAL count, and NEW delta."
  (let ((only-new (memq gh-radar-count-display '(new only-new))))
    (if only-new
        (format "%s%s"
                (if icon (format "%s " icon) "")
                (if (> new 0)
                    (propertize (format "+%d" new) 'face 'gh-radar-new-face)
                  "0"))
      (format "%s%d%s"
              (if icon (format "%s " icon) "")
              total
              (if (> new 0)
                  (propertize (format " (+%d)" new) 'face 'gh-radar-new-face)
                "")))))

(defun gh-radar-modeline-format ()
  "Format radar metrics and notifications into a mode-line string."
  (when (or gh-radar-state-data
            (and gh-radar-track-notifications gh-radar-state-notifications))
    (let ((parts nil))
      (if gh-radar-bell-modeline
          (let* ((inbox-cnt
                  (if (and gh-radar-track-notifications
                           gh-radar-state-notifications)
                      (or (plist-get gh-radar-state-notifications :count) 0)
                    0))
                 (inbox-new
                  (if (and gh-radar-track-notifications
                           gh-radar-state-notifications)
                      (or (plist-get gh-radar-state-notifications :new) 0)
                    0))
                 (totals (gh-radar-modeline--repo-totals))
                 (total-cnt (+ inbox-cnt
                               (plist-get totals :issues)
                               (plist-get totals :prs)))
                 (total-new (+ inbox-new
                               (plist-get totals :new-issues)
                               (plist-get totals :new-prs)))
                 (active-cnt (if (memq gh-radar-count-display '(new only-new))
                                 total-new
                               total-cnt)))
            (unless (gh-radar-modeline--hide-zero-p :bell active-cnt)
              (let ((bell-icon (when (gh-radar-modeline--show-icon-p :bell)
                                 (gh-radar-icon :bell))))
                (push (gh-radar-modeline--format-segment
                       bell-icon total-cnt total-new)
                      parts))))
        (when (and gh-radar-track-notifications gh-radar-state-notifications)
          (let* ((inbox-cnt
                  (or (plist-get gh-radar-state-notifications :count) 0))
                 (inbox-new
                  (or (plist-get gh-radar-state-notifications :new) 0))
                 (active-cnt (if (memq gh-radar-count-display '(new only-new))
                                 inbox-new
                               inbox-cnt)))
            (unless (gh-radar-modeline--hide-zero-p :inbox active-cnt)
              (let ((inbox-icon (when (gh-radar-modeline--show-icon-p :inbox)
                                  (gh-radar-icon :inbox))))
                (push (gh-radar-modeline--format-segment
                       inbox-icon inbox-cnt inbox-new)
                      parts)))))
        (when gh-radar-state-data
          (let* ((totals (gh-radar-modeline--repo-totals))
                 (tot-issues (plist-get totals :issues))
                 (tot-prs (plist-get totals :prs))
                 (tot-new-issues (plist-get totals :new-issues))
                 (tot-new-prs (plist-get totals :new-prs))
                 (act-issues
                  (if (memq gh-radar-count-display '(new only-new))
                      tot-new-issues
                    tot-issues))
                 (act-prs
                  (if (memq gh-radar-count-display '(new only-new))
                      tot-new-prs
                    tot-prs)))
            (when (and (gh-radar-modeline--target-enabled-p "issues")
                       (not (gh-radar-modeline--hide-zero-p :issue act-issues)))
              (let ((issue-icon (when (gh-radar-modeline--show-icon-p :issue)
                                  (gh-radar-icon :issues))))
                (push (gh-radar-modeline--format-segment
                       issue-icon tot-issues tot-new-issues)
                      parts)))
            (when (and (gh-radar-modeline--target-enabled-p "pr")
                       (not (gh-radar-modeline--hide-zero-p :pr act-prs)))
              (let ((pr-icon (when (gh-radar-modeline--show-icon-p :pr)
                               (gh-radar-icon :pr))))
                (push (gh-radar-modeline--format-segment
                       pr-icon tot-prs tot-new-prs)
                      parts))))))
      (when parts
        (let* ((prefix-str
                (when gh-radar-show-prefix
                  (format "%s  " (propertize (gh-radar-icon :prefix)
                                             'face 'gh-radar-prefix-face))))
               (map (let ((km (make-sparse-keymap)))
                      (define-key km [mode-line mouse-1] #'gh-radar-dashboard)
                      km))
               (str (format " %s%s"
                            (or prefix-str "")
                            (string-join (nreverse parts) " "))))
          (propertize str
                      'mouse-face 'mode-line-highlight
                      'local-map map))))))

(provide 'gh-radar-modeline)
;;; gh-radar-modeline.el ends here
