;;; gh-radar.el --- GitHub issues and pull requests radar -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Szymon Wilczek
;; Author: Szymon Wilczek <swilczek.lx@gmail.com>
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1"))
;; Keywords: tools, vc, github
;; URL: https://github.com/szymonwilczek/gh-radar.el
;; License: GPL-3.0-or-later

;;; Commentary:
;; Tracks open issue and pull request counts for specified GitHub repositories
;; using the gh CLI and single-shot batched GraphQL queries.

;;; Code:

(require 'gh-radar-config)
(require 'gh-radar-query)
(require 'gh-radar-state)
(require 'gh-radar-process)
(require 'gh-radar-modeline)
(require 'gh-radar-dashboard)

(defvar gh-radar--timer nil
  "Internal repeating timer for polling GitHub metrics.")

(defun gh-radar-start-timer ()
  "Start or restart the periodic background fetch timer."
  (gh-radar-stop-timer)
  (when (and (or gh-radar-repos gh-radar-track-notifications) (> gh-radar-interval 0))
    (run-with-idle-timer 1.5 nil #'gh-radar-process-fetch)
    (setq gh-radar--timer
          (run-at-time gh-radar-interval gh-radar-interval #'gh-radar-process-fetch))))

(defun gh-radar-stop-timer ()
  "Cancel the active background fetch timer if running."
  (when (and gh-radar--timer (timerp gh-radar--timer))
    (cancel-timer gh-radar--timer)
    (setq gh-radar--timer nil)))

;;;###autoload
(define-minor-mode gh-radar-mode
  "Global minor mode to monitor GitHub issues and pull requests in the background."
  :global t
  :group 'gh-radar
  (if gh-radar-mode
      (gh-radar-start-timer)
    (gh-radar-stop-timer)
    (gh-radar-state-clear)))

;;;###autoload
(defun gh-radar-refresh ()
  "Manually trigger an asynchronous GitHub radar refresh."
  (interactive)
  (message "[gh-radar] Refreshing monitored repositories...")
  (gh-radar-process-fetch
   (lambda (_data)
     (message "[gh-radar] Refresh complete."))))

;;;###autoload
(defun gh-radar-browse ()
  "Select a monitored repository and open its issues or PRs in browser."
  (interactive)
  (unless gh-radar-repos
    (user-error "No repositories configured in `gh-radar-repos`"))
  (let* ((repo-names (mapcar #'car gh-radar-repos))
         (repo (completing-read "Open in browser: " repo-names nil t))
         (target (completing-read (format "Open for %s: " repo) '("issues" "pulls" "repo") nil t "issues"))
         (url (cond
               ((string= target "issues") (format "https://github.com/%s/issues" repo))
               ((string= target "pulls") (format "https://github.com/%s/pulls" repo))
               (t (format "https://github.com/%s" repo)))))
    (browse-url url)))

(provide 'gh-radar)
;;; gh-radar.el ends here
