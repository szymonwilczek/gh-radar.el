;;; gh-radar-process.el --- Asynchronous gh CLI invocation -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Szymon Wilczek
;; Author: Szymon Wilczek <swilczek.lx@gmail.com>
;; License: GPL-3.0-or-later

;;; Commentary:
;; Spawns asynchronous gh api processes, parses responses, and updates state.

;;; Code:

(require 'json)
(require 'gh-radar-config)
(require 'gh-radar-query)
(require 'gh-radar-state)

(defvar gh-radar-process--current nil
  "Current active gh-radar process instance.")

(defun gh-radar-process--parse-response (raw-json alias-map)
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
     (message "[gh-radar] Failed to parse API response: %s" err)
     nil)))

(defun gh-radar-process-fetch (&optional callback)
  "Trigger asynchronous fetch for `gh-radar-repos`.
Calls optional CALLBACK with updated state data on success."
  (when (and gh-radar-process--current (process-live-p gh-radar-process--current))
    (delete-process gh-radar-process--current))
  (when-let* ((built (gh-radar-query-build gh-radar-repos)))
    (let* ((default-directory (expand-file-name "~/"))
           (query-str (car built))
           (alias-map (cdr built))
           (stdout-buf (generate-new-buffer " *gh-radar-output*"))
           (stderr-buf (generate-new-buffer " *gh-radar-stderr*"))
           (cmd (list gh-radar-gh-executable "api" "graphql" "-f" (concat "query=" query-str)))
           (process-environment (append '("NO_COLOR=1" "CLICOLOR=0") process-environment)))
      (setq gh-radar-process--current
            (make-process
             :name "gh-radar"
             :buffer stdout-buf
             :stderr stderr-buf
             :connection-type 'pipe
             :command cmd
             :noquery t
             :sentinel
             (lambda (proc event)
               (when (memq (process-status proc) '(exit signal))
                 (let ((status (process-exit-status proc)))
                   (if (zerop status)
                       (with-current-buffer (process-buffer proc)
                         (let* ((output (buffer-string))
                                (records (gh-radar-process--parse-response output alias-map)))
                           (when records
                             (gh-radar-state-update records)
                             (when callback (funcall callback gh-radar-state-data)))))
                     (let ((err-msg (when (buffer-live-p stderr-buf)
                                      (with-current-buffer stderr-buf
                                        (string-trim (buffer-string))))))
                       (message "[gh-radar] gh api failed (code %d): %s %s"
                                status (string-trim event) (or err-msg "")))))
                 (when (buffer-live-p (process-buffer proc))
                   (kill-buffer (process-buffer proc)))
                 (when (buffer-live-p stderr-buf)
                   (kill-buffer stderr-buf))
                 (setq gh-radar-process--current nil))))))))

(provide 'gh-radar-process)
;;; gh-radar-process.el ends here
