;;; gh-radar-cache.el --- Persistent disk cache for gh-radar -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Szymon Wilczek
;; Author: Szymon Wilczek <swilczek.lx@gmail.com>
;; License: GPL-3.0-or-later

;;; Commentary:
;; Disk persistence for tracking seen and unread issues/PRs across sessions.

;;; Code:

(require 'gh-radar-config)

(defcustom gh-radar-cache-file (locate-user-emacs-file "gh-radar-cache.eld")
  "File path for storing persistent unread activity and high-water marks."
  :type 'file
  :group 'gh-radar)

(defvar gh-radar-cache--data nil
  "In-memory representation of persisted cache alist.")

(defun gh-radar-cache-load ()
  "Load persisted radar cache from `gh-radar-cache-file`.
Returns the loaded alist or nil on failure."
  (if (and gh-radar-cache-file (file-exists-p gh-radar-cache-file))
      (condition-case err
          (with-temp-buffer
            (insert-file-contents gh-radar-cache-file)
            (goto-char (point-min))
            (setq gh-radar-cache--data (read (current-buffer))))
        (error
         (message "[gh-radar] Failed to read cache file: %s" err)
         (setq gh-radar-cache--data nil)))
    (setq gh-radar-cache--data nil))
  gh-radar-cache--data)

(defun gh-radar-cache-save (data)
  "Save DATA alist to `gh-radar-cache-file`."
  (setq gh-radar-cache--data data)
  (when gh-radar-cache-file
    (condition-case err
        (let ((dir (file-name-directory gh-radar-cache-file)))
          (when (and dir (not (file-directory-p dir)))
            (make-directory dir t))
          (with-temp-file gh-radar-cache-file
            (insert ";; gh-radar persistent cache -*- lisp-data -*-\n")
            (prin1 data (current-buffer))
            (insert "\n")))
      (error
       (message "[gh-radar] Failed to write cache file: %s" err)))))

(defun gh-radar-cache-get (repo)
  "Retrieve cached plist for REPO (\"owner/name\")."
  (unless gh-radar-cache--data
    (gh-radar-cache-load))
  (cdr (assoc repo gh-radar-cache--data)))

(defun gh-radar-cache-put (repo plist)
  "Store PLIST for REPO in cache and persist to disk."
  (unless gh-radar-cache--data
    (gh-radar-cache-load))
  (let ((existing (assoc repo gh-radar-cache--data)))
    (if existing
        (setcdr existing plist)
      (push (cons repo plist) gh-radar-cache--data)))
  (gh-radar-cache-save gh-radar-cache--data))

(provide 'gh-radar-cache)
;;; gh-radar-cache.el ends here
