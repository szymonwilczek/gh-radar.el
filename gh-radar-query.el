;;; gh-radar-query.el --- GraphQL query generator -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Szymon Wilczek
;; Author: Szymon Wilczek <swilczek.lx@gmail.com>
;; License: GPL-3.0-or-later

;;; Commentary:
;; Parses user repository configurations and generates unified GraphQL queries.

;;; Code:

(require 'subr-x)

(defun gh-radar-query--parse-target (target)
  "Normalize TARGET string or symbol into :issues or :pr."
  (let ((s (downcase (if (symbolp target) (symbol-name target) target))))
    (cond
     ((or (string= s "issues") (string= s ":issues")) :issues)
     ((or (string= s "pr") (string= s ":pr") (string= s "pulls")) :pr)
     (t nil))))

(defun gh-radar-query--parse-repo-entry (entry)
  "Parse ENTRY into (OWNER NAME TARGETS-LIST)."
  (let* ((repo-spec (car entry))
         (parts (split-string (string-trim repo-spec) "/"))
         (targets (delq nil (mapcar #'gh-radar-query--parse-target
                                    (cdr entry)))))
    (when (and (= (length parts) 2)
               (not (string-empty-p (car parts)))
               (not (string-empty-p (cadr parts))))
      (list (car parts) (cadr parts) (or targets '(:issues :pr))))))

(defcustom gh-radar-recent-items-limit 10
  "Number of recent issues and pull requests to fetch per repository."
  :type 'integer
  :group 'gh-radar)

(defun gh-radar-query-build (repos)
  "Generate a consolidated GraphQL query string and alias map for REPOS list.
Returns a cons cell (QUERY-STRING . ALIAS-MAP)."
  (let ((fields nil)
        (alias-map nil)
        (limit (max 1 (or gh-radar-recent-items-limit 10)))
        (index 0))
    (dolist (entry repos)
      (when-let* ((parsed (gh-radar-query--parse-repo-entry entry)))
        (let* ((owner (nth 0 parsed))
               (name (nth 1 parsed))
               (targets (nth 2 parsed))
               (alias (format "repo_%d" index))
               (parts nil))
          (when (memq :issues targets)
            (push (format
                   (concat "issues(states: OPEN, first: %d, "
                           "orderBy: {field: CREATED_AT, direction: DESC}) "
                           "{ totalCount pageInfo { hasNextPage } "
                           "nodes { number title url createdAt "
                           "author { login } } }")
                   limit)
                  parts))
          (when (memq :pr targets)
            (push (format
                   (concat "pullRequests(states: OPEN, first: %d, "
                           "orderBy: {field: CREATED_AT, direction: DESC}) "
                           "{ totalCount pageInfo { hasNextPage } "
                           "nodes { number title url createdAt "
                           "author { login } } }")
                   limit)
                  parts))
          (when parts
            (push (format "%s: repository(owner: \"%s\", name: \"%s\") { %s }"
                          alias owner name (string-join (nreverse parts) " "))
                  fields)
            (push (cons alias
                        (list :owner owner
                              :name name
                              :repo (format "%s/%s" owner name)
                              :targets targets))
                  alias-map)
            (setq index (1+ index))))))
    (when fields
      (cons (format "query { %s }" (string-join (nreverse fields) " "))
            (nreverse alias-map)))))

(provide 'gh-radar-query)
;;; gh-radar-query.el ends here
