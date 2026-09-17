;;; gh-radar-state.el --- State management and delta tracking -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Szymon Wilczek
;; Author: Szymon Wilczek <swilczek.lx@gmail.com>
;; License: GPL-3.0-or-later

;;; Commentary:
;; In-memory state cache, delta calculation, and subscriber hooks.

;;; Code:

(require 'gh-radar-config)

(defvar gh-radar-state-data nil
  "Current state alist mapping repository names to their radar metrics.
Each item is of the form:
  (REPO . (:owner STR :name STR :issues INT :pr INT
           :new-issues INT :new-pr INT :timestamp TIME))")

(defvar gh-radar-state-notifications nil
  "Current state plist for GitHub notifications inbox.
Format:
  (:count INT :new INT :timestamp TIME :items LIST)")

(defvar gh-radar-update-hook nil
  "Hook run after gh-radar finishes updating state.
Each function is called with the full `gh-radar-state-data` alist.")

(defun gh-radar-state-get (repo)
  "Retrieve cached metrics plist for REPO (\"owner/name\")."
  (cdr (assoc repo gh-radar-state-data)))

(defun gh-radar-state-update (new-records)
  "Update `gh-radar-state-data` with NEW-RECORDS and calculate deltas.
NEW-RECORDS is a list of plists containing :repo, :owner, :name, :issues, :pr."
  (let ((updated-alist nil)
        (total-new-issues 0)
        (total-new-prs 0))
    (dolist (item new-records)
      (let* ((repo (plist-get item :repo))
             (old-item (gh-radar-state-get repo))
             (old-issues (or (plist-get old-item :issues) 0))
             (old-prs (or (plist-get old-item :pr) 0))
             (cur-issues (or (plist-get item :issues) 0))
             (cur-prs (or (plist-get item :pr) 0))
             (new-issues (max 0 (- cur-issues old-issues)))
             (new-prs (max 0 (- cur-prs old-prs))))
        (when old-item
          (setq total-new-issues (+ total-new-issues new-issues))
          (setq total-new-prs (+ total-new-prs new-prs)))
        (push (cons repo
                    (list :repo repo
                          :owner (plist-get item :owner)
                          :name (plist-get item :name)
                          :issues cur-issues
                          :pr cur-prs
                          :new-issues (if old-item new-issues 0)
                          :new-pr (if old-item new-prs 0)
                          :timestamp (current-time)))
              updated-alist)))
    (setq gh-radar-state-data (nreverse updated-alist))
    (when (and gh-radar-notify-on-new (> (+ total-new-issues total-new-prs) 0))
      (message "[gh-radar] New activity detected: +%d issues, +%d pull requests"
               total-new-issues total-new-prs))
    (run-hook-with-args 'gh-radar-update-hook gh-radar-state-data)
    (force-mode-line-update t)))

(defun gh-radar-state-update-notifications (count &optional items)
  "Update `gh-radar-state-notifications` with COUNT and optional ITEMS list.
Calculates delta since previous update and alerts when new notifications arrive."
  (let* ((old-count (or (plist-get gh-radar-state-notifications :count) 0))
         (cur-count (or count 0))
         (new-count (if gh-radar-state-notifications (max 0 (- cur-count old-count)) 0)))
    (setq gh-radar-state-notifications
          (list :count cur-count
                :new new-count
                :timestamp (current-time)
                :items items))
    (when (and gh-radar-notify-on-new (> new-count 0))
      (message "[gh-radar] New notifications detected: +%d unread" new-count))
    (run-hook-with-args 'gh-radar-update-hook gh-radar-state-data)
    (force-mode-line-update t)))

(defun gh-radar-state-clear ()
  "Reset all cached radar metrics and notifications."
  (setq gh-radar-state-data nil)
  (setq gh-radar-state-notifications nil)
  (force-mode-line-update t))

(provide 'gh-radar-state)
;;; gh-radar-state.el ends here
