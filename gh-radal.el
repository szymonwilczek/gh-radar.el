;;; gh-radal.el --- GitHub issues and pull requests radar -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Szymon Wilczek
;; Author: Szymon Wilczek <swilczek.lx@gmail.com>
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1"))
;; Keywords: tools, vc, github
;; URL: https://github.com/szymonwilczek/gh-radal.el
;; License: GPL-3.0-or-later

;;; Commentary:
;; Tracks open issue and pull request counts for specified GitHub repositories
;; using the gh CLI and single-shot batched GraphQL queries.

;;; Code:

(require 'gh-radal-config)
(require 'gh-radal-query)
(require 'gh-radal-state)
(require 'gh-radal-process)
(require 'gh-radal-modeline)

(defvar gh-radal--timer nil
  "Internal repeating timer for polling GitHub metrics.")

(defun gh-radal-start-timer ()
  "Start or restart the periodic background fetch timer."
  (gh-radal-stop-timer)
  (when (and gh-radal-repos (> gh-radal-interval 0))
    ;; Run initial fetch shortly after activation, then repeat every interval
    (run-with-idle-timer 1.5 nil #'gh-radal-process-fetch)
    (setq gh-radal--timer
          (run-at-time gh-radal-interval gh-radal-interval #'gh-radal-process-fetch))))

(defun gh-radal-stop-timer ()
  "Cancel the active background fetch timer if running."
  (when (and gh-radal--timer (timerp gh-radal--timer))
    (cancel-timer gh-radal--timer)
    (setq gh-radal--timer nil)))

;;;###autoload
(define-minor-mode gh-radal-mode
  "Global minor mode to monitor GitHub issues and pull requests in the background."
  :global t
  :group 'gh-radal
  (if gh-radal-mode
      (gh-radal-start-timer)
    (gh-radal-stop-timer)
    (gh-radal-state-clear)))

;;;###autoload
(defun gh-radal-refresh ()
  "Manually trigger an asynchronous GitHub radar refresh."
  (interactive)
  (message "[gh-radal] Refreshing monitored repositories...")
  (gh-radal-process-fetch
   (lambda (_data)
     (message "[gh-radal] Refresh complete."))))

;;;###autoload
(defun gh-radal-browse ()
  "Select a monitored repository and open its issues or PRs in browser."
  (interactive)
  (unless gh-radal-repos
    (user-error "No repositories configured in `gh-radal-repos`"))
  (let* ((repo-names (mapcar #'car gh-radal-repos))
         (repo (completing-read "Open in browser: " repo-names nil t))
         (target (completing-read (format "Open for %s: " repo) '("issues" "pulls" "repo") nil t "issues"))
         (url (cond
               ((string= target "issues") (format "https://github.com/%s/issues" repo))
               ((string= target "pulls") (format "https://github.com/%s/pulls" repo))
               (t (format "https://github.com/%s" repo)))))
    (browse-url url)))

(provide 'gh-radal)
;;; gh-radal.el ends here
