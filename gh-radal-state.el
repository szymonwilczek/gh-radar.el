;;; gh-radal-state.el --- State management and delta tracking -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Szymon Wilczek
;; Author: Szymon Wilczek <swilczek.lx@gmail.com>
;; License: GPL-3.0-or-later

;;; Commentary:
;; In-memory state cache, delta calculation, and subscriber hooks.

;;; Code:

(require 'gh-radal-config)

(defvar gh-radal-state-data nil
  "Current state alist mapping repository names to their radar metrics.
Each item is of the form:
  (REPO . (:owner STR :name STR :issues INT :pr INT
           :new-issues INT :new-pr INT :timestamp TIME))")

(defvar gh-radal-update-hook nil
  "Hook run after gh-radal finishes updating state.
Each function is called with the full `gh-radal-state-data` alist.")

(defun gh-radal-state-get (repo)
  "Retrieve cached metrics plist for REPO (\"owner/name\")."
  (cdr (assoc repo gh-radal-state-data)))

(defun gh-radal-state-update (new-records)
  "Update `gh-radal-state-data` with NEW-RECORDS and calculate deltas.
NEW-RECORDS is a list of plists containing :repo, :owner, :name, :issues, :pr."
  (let ((updated-alist nil)
        (total-new-issues 0)
        (total-new-prs 0))
    (dolist (item new-records)
      (let* ((repo (plist-get item :repo))
             (old-item (gh-radal-state-get repo))
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
                    (list :owner (plist-get item :owner)
                          :name (plist-get item :name)
                          :issues cur-issues
                          :pr cur-prs
                          :new-issues (if old-item new-issues 0)
                          :new-pr (if old-item new-prs 0)
                          :timestamp (current-time)))
              updated-alist)))
    (setq gh-radal-state-data (nreverse updated-alist))
    (when (and gh-radal-notify-on-new (> (+ total-new-issues total-new-prs) 0))
      (message "[gh-radal] New activity detected: +%d issues, +%d pull requests"
               total-new-issues total-new-prs))
    (run-hook-with-args 'gh-radal-update-hook gh-radal-state-data)))

(defun gh-radal-state-clear ()
  "Reset all cached radar metrics."
  (setq gh-radal-state-data nil))

(provide 'gh-radal-state)
;;; gh-radal-state.el ends here
