;;; gh-radal-process.el --- Asynchronous gh CLI invocation -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Szymon Wilczek
;; Author: Szymon Wilczek <swilczek.lx@gmail.com>
;; License: GPL-3.0-or-later

;;; Commentary:
;; Spawns asynchronous gh api processes, parses responses, and updates state.

;;; Code:

(require 'json)
(require 'gh-radal-config)
(require 'gh-radal-query)
(require 'gh-radal-state)

(defvar gh-radal-process--current nil
  "Current active gh-radal process instance.")

(defun gh-radal-process--parse-response (raw-json alias-map)
  "Parse RAW-JSON string from GitHub API according to ALIAS-MAP."
  (condition-case err
      (let* ((parsed (if (fboundp 'json-parse-string)
                         (json-parse-string raw-json :object-type 'hash-table)
                       (let ((json-object-type 'hash-table))
                         (json-read-from-string raw-json))))
             (data (when (hash-table-p parsed) (gethash "data" parsed)))
             (records nil))
        (when (hash-table-p data)
          (dolist (mapping alias-map)
            (let* ((alias (car mapping))
                   (meta (cdr mapping))
                   (node (gethash alias data)))
              (when (hash-table-p node)
                (let* ((issues-node (gethash "issues" node))
                       (pr-node (gethash "pullRequests" node))
                       (issues-cnt (when (hash-table-p issues-node) (gethash "totalCount" issues-node)))
                       (pr-cnt (when (hash-table-p pr-node) (gethash "totalCount" pr-node))))
                  (push (list :repo (plist-get meta :repo)
                              :owner (plist-get meta :owner)
                              :name (plist-get meta :name)
                              :issues issues-cnt
                              :pr pr-cnt)
                        records))))))
        (nreverse records))
    (error
     (message "[gh-radal] Failed to parse API response: %s" err)
     nil)))

(defun gh-radal-process-fetch (&optional callback)
  "Trigger asynchronous fetch for `gh-radal-repos`.
Calls optional CALLBACK with updated state data on success."
  (when (and gh-radal-process--current (process-live-p gh-radal-process--current))
    (delete-process gh-radal-process--current))
  (when-let* ((built (gh-radal-query-build gh-radal-repos)))
    (let* ((query-str (car built))
           (alias-map (cdr built))
           (stdout-buf (generate-new-buffer " *gh-radal-output*"))
           (cmd (list gh-radal-gh-executable "api" "graphql" "-f" (concat "query=" query-str))))
      (setq gh-radal-process--current
            (make-process
             :name "gh-radal"
             :buffer stdout-buf
             :command cmd
             :noquery t
             :sentinel
             (lambda (proc event)
               (when (memq (process-status proc) '(exit signal))
                 (let ((status (process-exit-status proc)))
                   (if (zerop status)
                       (with-current-buffer (process-buffer proc)
                         (let* ((output (buffer-string))
                                (records (gh-radal-process--parse-response output alias-map)))
                           (when records
                             (gh-radal-state-update records)
                             (when callback (funcall callback gh-radal-state-data)))))
                     (message "[gh-radal] gh api failed (code %d): %s" status (string-trim event))))
                 (kill-buffer (process-buffer proc))
                 (setq gh-radal-process--current nil))))))))

(provide 'gh-radal-process)
;;; gh-radal-process.el ends here
