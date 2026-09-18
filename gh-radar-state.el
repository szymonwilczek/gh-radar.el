;;; gh-radar-state.el --- State management and delta tracking -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Szymon Wilczek
;; Author: Szymon Wilczek <swilczek.lx@gmail.com>
;; License: GPL-3.0-or-later

;;; Commentary:
;; In-memory state cache, persistent unread queue tracking, and subscriber hooks.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'gh-radar-config)
(require 'gh-radar-cache)

(defvar gh-radar-state-data nil
  "Current state alist mapping repository names to their radar metrics.
Each item is of the form:
  (REPO . (:owner STR :name STR :issues INT :pr INT
           :last-seen-issue INT :last-seen-pr INT
           :unread-issues LIST :unread-prs LIST
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

(defun gh-radar-state-load-cache ()
  "Initialize `gh-radar-state-data`, repos, and settings from disk cache."
  (when-let* ((cached (gh-radar-cache-load)))
    (when-let* ((repos (plist-get cached :repos)))
      (setq gh-radar-repos repos))
    (let ((notif (gh-radar-cache-get-setting :track-notifications :unspecified)))
      (unless (eq notif :unspecified)
        (setq gh-radar-track-notifications notif)))
    (let ((cd (gh-radar-cache-get-setting :count-display :unspecified)))
      (unless (eq cd :unspecified)
        (setq gh-radar-count-display cd)))
    (let ((bell (gh-radar-cache-get-setting :bell-modeline :unspecified)))
      (unless (eq bell :unspecified)
        (setq gh-radar-bell-modeline bell)))
    (let ((hz (gh-radar-cache-get-setting :hide-zero-counts :unspecified)))
      (unless (eq hz :unspecified)
        (setq gh-radar-hide-zero-counts hz)))
    (when-let* ((icons (gh-radar-cache-get-setting :icons nil)))
      (dolist (entry icons)
        (let ((existing (assq (car entry) gh-radar-icons)))
          (if existing
              (setcdr existing (cdr entry))
            (push entry gh-radar-icons)))))
    (let ((records nil)
          (items (plist-get cached :items)))
      (dolist (item items)
        (let* ((repo (car item))
               (data (cdr item))
               (parts (split-string repo "/"))
               (owner (car parts))
               (name (cadr parts))
               (ui (plist-get data :unread-issues))
               (up (plist-get data :unread-prs)))
          (push (cons repo
                      (list :repo repo
                            :owner owner
                            :name name
                            :issues (or (plist-get data :issues) 0)
                            :pr (or (plist-get data :pr) 0)
                            :last-seen-issue (plist-get data :last-seen-issue)
                            :last-seen-pr (plist-get data :last-seen-pr)
                            :unread-issues ui
                            :unread-prs up
                            :new-issues (length ui)
                            :new-pr (length up)
                            :timestamp nil))
                records)))
      (setq gh-radar-state-data (nreverse records)))))

(defun gh-radar-state-update (new-records)
  "Update `gh-radar-state-data` with NEW-RECORDS and update unread queue."
  (let ((updated-alist nil)
        (newly-detected-issues 0)
        (newly-detected-prs 0))
    (dolist (item new-records)
      (let* ((repo (plist-get item :repo))
             (cached (gh-radar-cache-get repo))
             (mem (gh-radar-state-get repo))
             (reference (or mem cached))
             (cur-issues (or (plist-get item :issues) 0))
             (cur-prs (or (plist-get item :pr) 0))
             (incoming-issues (plist-get item :recent-issues))
             (incoming-prs (plist-get item :recent-prs))
             last-issue
             last-pr
             unread-issues
             unread-prs)
        (if (null reference)
            ;; first time seeing this repository: establish baseline
            (let ((max-i (if incoming-issues
                             (apply #'max (mapcar (lambda (x) (plist-get x :number)) incoming-issues))
                           0))
                  (max-p (if incoming-prs
                             (apply #'max (mapcar (lambda (x) (plist-get x :number)) incoming-prs))
                           0)))
              (setq last-issue max-i
                    last-pr max-p
                    unread-issues nil
                    unread-prs nil))
          ;; existing repository: compute unread additions
          (let ((baseline-issue (or (plist-get reference :last-seen-issue) 0))
                (baseline-pr (or (plist-get reference :last-seen-pr) 0)))
            (setq last-issue baseline-issue
                  last-pr baseline-pr
                  unread-issues (copy-sequence
                                 (or (plist-get reference :unread-issues) nil))
                  unread-prs (copy-sequence
                              (or (plist-get reference :unread-prs) nil)))
            (dolist (issue incoming-issues)
              (let ((num (plist-get issue :number)))
                (when (and (> num baseline-issue)
                           (not (cl-some (lambda (x)
                                           (= (plist-get x :number) num))
                                         unread-issues)))
                  (push issue unread-issues)
                  (setq last-issue (max last-issue num))
                  (setq newly-detected-issues (1+ newly-detected-issues)))))
            (dolist (pr incoming-prs)
              (let ((num (plist-get pr :number)))
                (when (and (> num baseline-pr)
                           (not (cl-some (lambda (x)
                                           (= (plist-get x :number) num))
                                         unread-prs)))
                  (push pr unread-prs)
                  (setq last-pr (max last-pr num))
                  (setq newly-detected-prs (1+ newly-detected-prs)))))))

        ;; keep unread items sorted descending by number
        (setq unread-issues (sort unread-issues (lambda (a b) (> (plist-get a :number) (plist-get b :number))))
              unread-prs (sort unread-prs (lambda (a b) (> (plist-get a :number) (plist-get b :number)))))

        ;; persist to disk cache
        (gh-radar-cache-put repo
                            (list :issues cur-issues
                                  :pr cur-prs
                                  :last-seen-issue last-issue
                                  :last-seen-pr last-pr
                                  :unread-issues unread-issues
                                  :unread-prs unread-prs))

        (push (cons repo
                    (list :repo repo
                          :owner (plist-get item :owner)
                          :name (plist-get item :name)
                          :issues cur-issues
                          :pr cur-prs
                          :last-seen-issue last-issue
                          :last-seen-pr last-pr
                          :unread-issues unread-issues
                          :unread-prs unread-prs
                          :new-issues (length unread-issues)
                          :new-pr (length unread-prs)
                          :timestamp (current-time)))
              updated-alist)))
    (setq gh-radar-state-data (nreverse updated-alist))
    (when (and gh-radar-notify-on-new (> (+ newly-detected-issues newly-detected-prs) 0))
      (let ((msg (format "New activity detected: +%d issues, +%d pull requests"
                         newly-detected-issues newly-detected-prs)))
        (message "[gh-radar] %s" msg)
        (gh-radar-notify-desktop "GitHub Radar" msg)))
    (run-hook-with-args 'gh-radar-update-hook gh-radar-state-data)
    (force-mode-line-update t)))

(defun gh-radar-state-unread-items ()
  "Return a flat list of all unread items across all monitored repositories."
  (let ((items nil))
    (dolist (entry gh-radar-state-data)
      (let* ((repo (car entry))
             (data (cdr entry))
             (owner (plist-get data :owner))
             (name (plist-get data :name)))
        (dolist (issue (plist-get data :unread-issues))
          (push (append (list :repo repo :owner owner :name name) issue) items))
        (dolist (pr (plist-get data :unread-prs))
          (push (append (list :repo repo :owner owner :name name) pr) items))))
    (nreverse items)))

(defun gh-radar-state-dismiss-item (repo type number)
  "Dismiss a single unread item of TYPE (:issue or :pr) with NUMBER in REPO."
  (when-let* ((entry (assoc repo gh-radar-state-data)))
    (let* ((data (cdr entry))
           (ui (plist-get data :unread-issues))
           (up (plist-get data :unread-prs)))
      (if (eq type :issue)
          (setq ui (cl-remove-if (lambda (x) (= (plist-get x :number) number)) ui))
        (setq up (cl-remove-if (lambda (x) (= (plist-get x :number) number)) up)))
      (setcdr entry (plist-put data :unread-issues ui))
      (setcdr entry (plist-put (cdr entry) :unread-prs up))
      (setcdr entry (plist-put (cdr entry) :new-issues (length ui)))
      (setcdr entry (plist-put (cdr entry) :new-pr (length up)))
      (gh-radar-cache-put repo
                          (list :issues (plist-get data :issues)
                                :pr (plist-get data :pr)
                                :last-seen-issue (plist-get data :last-seen-issue)
                                :last-seen-pr (plist-get data :last-seen-pr)
                                :unread-issues ui
                                :unread-prs up))
      (run-hook-with-args 'gh-radar-update-hook gh-radar-state-data)
      (force-mode-line-update t))))

(defun gh-radar-state-dismiss-repo (repo)
  "Dismiss all unread items for REPO."
  (when-let* ((entry (assoc repo gh-radar-state-data)))
    (let ((data (cdr entry)))
      (setcdr entry (plist-put data :unread-issues nil))
      (setcdr entry (plist-put (cdr entry) :unread-prs nil))
      (setcdr entry (plist-put (cdr entry) :new-issues 0))
      (setcdr entry (plist-put (cdr entry) :new-pr 0))
      (gh-radar-cache-put repo
                          (list :issues (plist-get data :issues)
                                :pr (plist-get data :pr)
                                :last-seen-issue (plist-get data :last-seen-issue)
                                :last-seen-pr (plist-get data :last-seen-pr)
                                :unread-issues nil
                                :unread-prs nil))
      (run-hook-with-args 'gh-radar-update-hook gh-radar-state-data)
      (force-mode-line-update t))))

(defun gh-radar-state-dismiss-all ()
  "Dismiss all unread items across all monitored repositories."
  (dolist (entry gh-radar-state-data)
    (let* ((repo (car entry))
           (data (cdr entry)))
      (setcdr entry (plist-put data :unread-issues nil))
      (setcdr entry (plist-put (cdr entry) :unread-prs nil))
      (setcdr entry (plist-put (cdr entry) :new-issues 0))
      (setcdr entry (plist-put (cdr entry) :new-pr 0))
      (gh-radar-cache-put repo
                          (list :issues (plist-get data :issues)
                                :pr (plist-get data :pr)
                                :last-seen-issue (plist-get data :last-seen-issue)
                                :last-seen-pr (plist-get data :last-seen-pr)
                                :unread-issues nil
                                :unread-prs nil))))
  (when gh-radar-state-notifications
    (setq gh-radar-state-notifications
          (plist-put gh-radar-state-notifications :new 0)))
  (run-hook-with-args 'gh-radar-update-hook gh-radar-state-data)
  (force-mode-line-update t))

(defun gh-radar-state-update-notifications (count &optional items)
  "Update `gh-radar-state-notifications` with COUNT and optional ITEMS list."
  (let* ((old-count (or (plist-get gh-radar-state-notifications :count) 0))
         (cur-count (or count 0))
         (new-count (if gh-radar-state-notifications (max 0 (- cur-count old-count)) 0)))
    (setq gh-radar-state-notifications
          (list :count cur-count
                :new new-count
                :timestamp (current-time)
                :items items))
    (when (and gh-radar-notify-on-new (> new-count 0))
      (let ((msg (format "New notifications detected: +%d unread" new-count)))
        (message "[gh-radar] %s" msg)
        (gh-radar-notify-desktop "GitHub Notifications" msg)))
    (run-hook-with-args 'gh-radar-update-hook gh-radar-state-data)
    (force-mode-line-update t)))

(defun gh-radar-state-clear ()
  "Reset all cached radar metrics and notifications."
  (setq gh-radar-state-data nil)
  (setq gh-radar-state-notifications nil)
  (force-mode-line-update t))

(gh-radar-state-load-cache)

(provide 'gh-radar-state)
;;; gh-radar-state.el ends here
