;;; gh-radar-cache.el --- Persistent disk cache for gh-radar -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Szymon Wilczek
;; Author: Szymon Wilczek <swilczek.lx@gmail.com>
;; License: GPL-3.0-or-later

;;; Commentary:
;; Disk persistence for repository configurations, tracking settings,
;; seen watermarks, and unread activity across sessions.

;;; Code:

(defcustom gh-radar-cache-file (locate-user-emacs-file "gh-radar-cache.eld")
  "File path for storing persistent configuration and unread activity."
  :type 'file
  :group 'gh-radar)

(defvar gh-radar-cache--data nil
  "In-memory representation of persisted cache and configuration.")

(defun gh-radar-cache--normalize (raw)
  "Normalize RAW loaded data into standard plist format."
  (cond
   ((null raw)
    (list :version 1 :settings (list :track-notifications t) :repos nil :items nil))
   ((and (consp raw) (keywordp (car raw)))
    raw)
   ((consp raw)
    (list :version 1 :settings (list :track-notifications t) :repos nil :items raw))
   (t
    (list :version 1 :settings (list :track-notifications t) :repos nil :items nil))))

(defun gh-radar-cache-load ()
  "Load persisted radar configuration and state from `gh-radar-cache-file`.
Returns the normalized cache plist."
  (if (and gh-radar-cache-file (file-exists-p gh-radar-cache-file))
      (condition-case err
          (with-temp-buffer
            (insert-file-contents gh-radar-cache-file)
            (goto-char (point-min))
            (setq gh-radar-cache--data (gh-radar-cache--normalize (read (current-buffer)))))
        (error
         (message "[gh-radar] Failed to read cache file: %s" err)
         (setq gh-radar-cache--data (gh-radar-cache--normalize nil))))
    (setq gh-radar-cache--data (gh-radar-cache--normalize nil)))
  gh-radar-cache--data)

(defun gh-radar-cache--get-data ()
  "Return active cache data, loading from disk if not yet loaded."
  (unless gh-radar-cache--data
    (gh-radar-cache-load))
  gh-radar-cache--data)

(defun gh-radar-cache-save (&optional data)
  "Save DATA (or current cache data) to `gh-radar-cache-file`."
  (when data
    (setq gh-radar-cache--data data))
  (let ((payload (gh-radar-cache--get-data)))
    (when gh-radar-cache-file
      (condition-case err
          (let ((dir (file-name-directory gh-radar-cache-file)))
            (when (and dir (not (file-directory-p dir)))
              (make-directory dir t))
            (with-temp-file gh-radar-cache-file
              (insert ";; gh-radar persistent configuration & cache -*- lisp-data -*-\n")
              (prin1 payload (current-buffer))
              (insert "\n")))
        (error
         (message "[gh-radar] Failed to write cache file: %s" err))))))

(defun gh-radar-cache-get-repos ()
  "Return configured repositories list from cache."
  (plist-get (gh-radar-cache--get-data) :repos))

(defun gh-radar-cache-set-repos (repos)
  "Set configured REPOS list in cache and persist to disk."
  (let ((data (gh-radar-cache--get-data)))
    (setq gh-radar-cache--data (plist-put data :repos repos))
    (gh-radar-cache-save)))

(defun gh-radar-cache-add-repo (repo-name &optional targets)
  "Add or update REPO-NAME with TARGETS in cache."
  (let* ((repos (copy-sequence (gh-radar-cache-get-repos)))
         (existing (assoc repo-name repos))
         (tgs (or targets '("issues" "pr"))))
    (if existing
        (setcdr existing tgs)
      (setq repos (append repos (list (cons repo-name tgs)))))
    (gh-radar-cache-set-repos repos)))

(defun gh-radar-cache-remove-repo (repo-name)
  "Remove REPO-NAME from configured repositories and cached items."
  (let* ((repos (cl-remove-if (lambda (r) (string= (car r) repo-name))
                              (gh-radar-cache-get-repos)))
         (items (cl-remove-if (lambda (i) (string= (car i) repo-name))
                              (plist-get (gh-radar-cache--get-data) :items)))
         (data (gh-radar-cache--get-data)))
    (setq data (plist-put data :repos repos))
    (setq data (plist-put data :items items))
    (setq gh-radar-cache--data data)
    (gh-radar-cache-save)))

(defun gh-radar-cache-toggle-target (repo-name target)
  "Toggle TARGET (\"issues\" or \"pr\") for REPO-NAME in cache."
  (let* ((repos (copy-sequence (gh-radar-cache-get-repos)))
         (entry (assoc repo-name repos)))
    (when entry
      (let* ((targets (cdr entry))
             (has-t (member target targets))
             (new-targets (if has-t
                              (delete target (copy-sequence targets))
                            (append targets (list target)))))
        (setcdr entry new-targets)
        (gh-radar-cache-set-repos repos)))))

(defun gh-radar-cache-get-setting (key &optional default)
  "Return value for setting KEY from cache, or DEFAULT if absent."
  (let ((settings (plist-get (gh-radar-cache--get-data) :settings)))
    (if (and settings (plist-member settings key))
        (plist-get settings key)
      default)))

(defun gh-radar-cache-set-setting (key val)
  "Store setting KEY with VAL in cache and persist to disk."
  (let* ((data (gh-radar-cache--get-data))
         (settings (copy-sequence (or (plist-get data :settings) nil))))
    (setq settings (plist-put settings key val))
    (setq data (plist-put data :settings settings))
    (setq gh-radar-cache--data data)
    (gh-radar-cache-save)))

(defun gh-radar-cache-get (repo)
  "Retrieve cached item metrics plist for REPO (\"owner/name\")."
  (let ((items (plist-get (gh-radar-cache--get-data) :items)))
    (cdr (assoc repo items))))

(defun gh-radar-cache-put (repo plist)
  "Store PLIST for REPO in cached items and persist to disk."
  (let* ((data (gh-radar-cache--get-data))
         (items (copy-sequence (or (plist-get data :items) nil)))
         (existing (assoc repo items)))
    (if existing
        (setcdr existing plist)
      (setq items (cons (cons repo plist) items)))
    (setq data (plist-put data :items items))
    (setq gh-radar-cache--data data)
    (gh-radar-cache-save)))

(provide 'gh-radar-cache)
;;; gh-radar-cache.el ends here
