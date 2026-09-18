;;; gh-radar-process.el --- Asynchronous gh CLI -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Szymon Wilczek
;; Author: Szymon Wilczek <swilczek.lx@gmail.com>
;; License: GPL-3.0-or-later

;;; Commentary:
;; Subprocess management for invoking GitHub CLI asynchronously.

;;; Code:

(require 'json)
(require 'seq)
(require 'subr-x)
(require 'gh-radar-config)
(require 'gh-radar-query)
(require 'gh-radar-state)

(defvar gh-radar-process--current nil
  "Current active gh-radar repository process instance.")

(defun gh-radar-process--extract-nodes (connection type)
  "Extract issue/PR node plists from CONNECTION hash-table for TYPE.
TYPE is either `:issue' or `:pr'."
  (when (hash-table-p connection)
    (let* ((nodes (gethash "nodes" connection))
           (node-list (if (vectorp nodes) (append nodes nil) nodes)))
      (delq nil
            (mapcar
             (lambda (node)
               (when (hash-table-p node)
                 (let* ((author (gethash "author" node))
                        (author-login (when (hash-table-p author)
                                        (gethash "login" author))))
                   (list :number (gethash "number" node)
                         :title (gethash "title" node)
                         :url (gethash "url" node)
                         :created-at (gethash "createdAt" node)
                         :author (or author-login "ghost")
                         :type type))))
             node-list)))))

(defun gh-radar-process--parse-response (raw-json alias-map)
  "Parse RAW-JSON string from GraphQL response using ALIAS-MAP.
Returns a list of repository metric plists."
  (condition-case err
      (let* ((parsed (if (fboundp 'json-parse-string)
                         (json-parse-string raw-json :object-type 'hash-table)
                       (let ((json-object-type 'hash-table))
                         (json-read-from-string raw-json))))
             (data (when (hash-table-p parsed) (gethash "data" parsed)))
             (errors (when (hash-table-p parsed) (gethash "errors" parsed)))
             (records nil))
        (when errors
          (let ((err-msgs
                 (mapconcat
                  (lambda (e)
                    (if (hash-table-p e)
                        (or (gethash "message" e) "Unknown GraphQL error")
                      (format "%s" e)))
                  (if (vectorp errors) (append errors nil) errors)
                  "; ")))
            (message "[gh-radar] GraphQL error: %s" err-msgs)))
        (when (hash-table-p data)
          (dolist (mapping alias-map)
            (let* ((alias (car mapping))
                   (meta (cdr mapping))
                   (node (gethash alias data)))
              (when (hash-table-p node)
                (let* ((issues-node (gethash "issues" node))
                       (pr-node (gethash "pullRequests" node))
                       (issues-cnt
                        (when (hash-table-p issues-node)
                          (gethash "totalCount" issues-node)))
                       (pr-cnt
                        (when (hash-table-p pr-node)
                          (gethash "totalCount" pr-node)))
                       (recent-issues
                        (gh-radar-process--extract-nodes issues-node :issue))
                       (recent-prs
                        (gh-radar-process--extract-nodes pr-node :pr)))
                  (push (list :repo (plist-get meta :repo)
                              :owner (plist-get meta :owner)
                              :name (plist-get meta :name)
                              :issues issues-cnt
                              :pr pr-cnt
                              :recent-issues recent-issues
                              :recent-prs recent-prs)
                        records))))))
        (nreverse records))
    (error
     (message "[gh-radar] Failed to parse API response: %s" err)
     nil)))

(defun gh-radar-process-fetch-repos (&optional callback)
  "Trigger asynchronous GraphQL fetch for `gh-radar-repos'.
Calls optional CALLBACK with updated state data on completion."
  (when (and gh-radar-process--current
             (process-live-p gh-radar-process--current))
    (delete-process gh-radar-process--current))
  (if-let* ((built (gh-radar-query-build gh-radar-repos)))
      (let* ((default-directory (expand-file-name "~/"))
             (query-str (car built))
             (alias-map (cdr built))
             (stdout-buf (generate-new-buffer " *gh-radar-output*"))
             (stderr-buf (generate-new-buffer " *gh-radar-stderr*"))
             (cmd (list gh-radar-gh-executable "api" "graphql"
                        "-f" (concat "query=" query-str)))
             (process-environment
              (append '("NO_COLOR=1" "CLICOLOR=0") process-environment)))
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
                                  (records
                                   (gh-radar-process--parse-response
                                    output alias-map)))
                             (when records
                               (gh-radar-state-update records))
                             (when callback
                               (funcall callback gh-radar-state-data))))
                       (let ((err-msg (when (buffer-live-p stderr-buf)
                                        (with-current-buffer stderr-buf
                                          (string-trim (buffer-string))))))
                         (message "[gh-radar] gh api failed (code %d): %s %s"
                                  status (string-trim event) (or err-msg "")))
                       (when callback (funcall callback nil))))
                   (when (buffer-live-p (process-buffer proc))
                     (kill-buffer (process-buffer proc)))
                   (when (buffer-live-p stderr-buf)
                     (kill-buffer stderr-buf))
                   (setq gh-radar-process--current nil))))))
    (when callback (funcall callback nil))))

(defun gh-radar-process-fetch (&optional callback)
  "Trigger asynchronous fetch for repository metrics and notifications.
Calls optional CALLBACK with state data when all fetches complete."
  (let* ((pending 0)
         (on-complete (lambda (&rest _)
                        (setq pending (1- pending))
                        (when (and (<= pending 0) callback)
                          (funcall callback gh-radar-state-data)))))
    (when gh-radar-track-notifications
      (setq pending (1+ pending))
      (gh-radar-process-fetch-notifications on-complete))
    (when gh-radar-repos
      (setq pending (1+ pending))
      (gh-radar-process-fetch-repos on-complete))
    (when (and (zerop pending) callback)
      (funcall callback gh-radar-state-data))))

(defvar gh-radar-process--notifications nil
  "Current active gh-radar notifications process instance.")

(defun gh-radar-process-fetch-notifications (&optional callback)
  "Trigger asynchronous fetch for GitHub unread notifications.
Calls optional CALLBACK with updated notification state on success."
  (when (and gh-radar-process--notifications
             (process-live-p gh-radar-process--notifications))
    (delete-process gh-radar-process--notifications))
  (let* ((default-directory (expand-file-name "~/"))
         (stdout-buf (generate-new-buffer " *gh-radar-notifications*"))
         (stderr-buf (generate-new-buffer " *gh-radar-notifications-err*"))
         (cmd (list gh-radar-gh-executable "api" "notifications"))
         (process-environment
          (append '("NO_COLOR=1" "CLICOLOR=0") process-environment)))
    (setq gh-radar-process--notifications
          (make-process
           :name "gh-radar-notifications"
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
                       (let* ((raw (buffer-string))
                              (items
                               (condition-case _
                                   (if (fboundp 'json-parse-string)
                                       (json-parse-string
                                        raw :array-type 'list)
                                     (let ((json-array-type 'list))
                                       (json-read-from-string raw)))
                                 (error nil)))
                              (count (if (listp items) (length items) 0)))
                         (gh-radar-state-update-notifications count items)
                         (when callback
                           (funcall callback gh-radar-state-notifications))))
                   (let ((err-msg (when (buffer-live-p stderr-buf)
                                    (with-current-buffer stderr-buf
                                      (string-trim (buffer-string))))))
                     (message
                      "[gh-radar] notifications fetch failed (code %d): %s %s"
                      status (string-trim event) (or err-msg "")))
                   (when callback (funcall callback nil))))
               (when (buffer-live-p (process-buffer proc))
                 (kill-buffer (process-buffer proc)))
               (when (buffer-live-p stderr-buf)
                 (kill-buffer stderr-buf))
               (setq gh-radar-process--notifications nil)))))))

(provide 'gh-radar-process)
;;; gh-radar-process.el ends here
