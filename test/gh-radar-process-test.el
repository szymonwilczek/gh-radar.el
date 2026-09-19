;;; gh-radar-process-test.el --- Tests for process -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Szymon Wilczek
;; Author: Szymon Wilczek <swilczek.lx@gmail.com>
;; License: GPL-3.0-or-later

;;; Commentary:
;; Unit tests for API response parsing and node extraction.

;;; Code:

(require 'test-helper)

(ert-deftest gh-radar-process-test-extract-nodes-nil ()
  "Test node extraction with nil or non-hash-table inputs."
  (should-not (gh-radar-process--extract-nodes nil :issue))
  (should-not (gh-radar-process--extract-nodes "string" :pr))
  (should-not (gh-radar-process--extract-nodes (make-hash-table) :issue)))

(ert-deftest gh-radar-process-test-extract-nodes-valid ()
  "Test node extraction with valid connection node hash table."
  (let ((conn (make-hash-table :test 'equal))
        (node1 (make-hash-table :test 'equal))
        (node2 (make-hash-table :test 'equal))
        (author (make-hash-table :test 'equal)))
    (puthash "login" "alice" author)
    (puthash "number" 42 node1)
    (puthash "title" "Fix bug" node1)
    (puthash "url" "https://github.com/o/r/issues/42" node1)
    (puthash "createdAt" "2026-09-18T12:00:00Z" node1)
    (puthash "author" author node1)

    (puthash "number" 43 node2)
    (puthash "title" "Docs update" node2)
    (puthash "url" "https://github.com/o/r/issues/43" node2)
    (puthash "createdAt" "2026-09-18T13:00:00Z" node2)
    (puthash "author" nil node2)

    (puthash "nodes" (vector node1 node2) conn)
    (let ((extracted (gh-radar-process--extract-nodes conn :issue)))
      (should (= (length extracted) 2))
      (let ((item1 (nth 0 extracted))
            (item2 (nth 1 extracted)))
        (should (eq (plist-get item1 :type) :issue))
        (should (= (plist-get item1 :number) 42))
        (should (equal (plist-get item1 :title) "Fix bug"))
        (should (equal (plist-get item1 :author) "alice"))
        (should (equal (plist-get item2 :author) "ghost"))))))

(ert-deftest gh-radar-process-test-parse-response-valid ()
  "Test parsing valid GraphQL JSON string with alias mapping."
  (let* ((json (concat "{\"data\": {\"repo_0\": "
                       "{\"issues\": {\"totalCount\": 5, \"nodes\": []}, "
                       "\"pullRequests\": {\"totalCount\": 2, "
                       "\"nodes\": []}}}}"))
         (alias-map '(("repo_0" . (:owner "o" :name "r" :repo "o/r"
                                          :targets (:issues :pr))))))
    (let ((parsed (gh-radar-process--parse-response json alias-map)))
      (should (= (length parsed) 1))
      (let ((record (car parsed)))
        (should (equal (plist-get record :repo) "o/r"))
        (should (equal (plist-get record :owner) "o"))
        (should (equal (plist-get record :name) "r"))
        (should (= (plist-get record :issues) 5))
        (should (= (plist-get record :pr) 2))))))

(ert-deftest gh-radar-process-test-parse-response-malformed ()
  "Test parsing malformed JSON string returns nil gracefully."
  (let ((alias-map '(("repo_0" . (:repo "o/r")))))
    (should-not (gh-radar-process--parse-response "not json" alias-map))
    (should-not (gh-radar-process--parse-response "" alias-map))
    (should-not (gh-radar-process--parse-response
                 "{\"data\": null}" alias-map))))

(ert-deftest gh-radar-process-test-parse-response-errors ()
  "Test handling GraphQL errors array with partial data."
  (let* ((json (concat "{\"data\": {\"repo_0\": "
                       "{\"issues\": {\"totalCount\": 3, \"nodes\": []}, "
                       "\"pullRequests\": {\"totalCount\": 1, "
                       "\"nodes\": []}}, "
                       "\"repo_1\": null}, "
                       "\"errors\": [{\"message\": "
                       "\"Repo repo_1 not found\"}]}"))
         (alias-map '(("repo_0" . (:owner "o" :name "r0" :repo "o/r0"))
                      ("repo_1" . (:owner "o" :name "r1" :repo "o/r1")))))
    (let ((parsed (gh-radar-process--parse-response json alias-map)))
      (should (= (length parsed) 1))
      (should (equal (plist-get (car parsed) :repo) "o/r0"))
      (should (= (plist-get (car parsed) :issues) 3)))))

(ert-deftest gh-radar-process-test-parse-response-page-info ()
  "Test parsing pageInfo hasNextPage sets :has-more flags."
  (let* ((json (concat "{\"data\": {\"repo_0\": "
                       "{\"issues\": {\"totalCount\": 15, "
                       "\"pageInfo\": {\"hasNextPage\": true}, "
                       "\"nodes\": []}, "
                       "\"pullRequests\": {\"totalCount\": 1, "
                       "\"pageInfo\": {\"hasNextPage\": false}, "
                       "\"nodes\": []}}}}"))
         (alias-map '(("repo_0" . (:owner "o" :name "r" :repo "o/r")))))
    (let ((parsed (gh-radar-process--parse-response json alias-map)))
      (should (= (length parsed) 1))
      (let ((rec (car parsed)))
        (should (eq (plist-get rec :has-more-issues) t))
        (should (eq (plist-get rec :has-more-prs) nil))
        (should (eq (plist-get rec :has-more) t))))))

(ert-deftest gh-radar-process-test-cancellation-flag ()
  "Test that tagging process with :cancelled preserves state without error."
  (let ((gh-radar-state-last-error nil)
        (called nil))
    (let* ((proc (make-process
                  :name "test-cancel"
                  :command '("sleep" "5")
                  :sentinel
                  (lambda (p _e)
                    (when (or (process-get p :cancelled)
                              (memq (process-exit-status p) '(9 15)))
                      (setq called t)))))
           (gh-radar-process--current proc))
      (process-put proc :cancelled t)
      (delete-process proc)
      (accept-process-output proc 0.2)
      (should called)
      (should-not gh-radar-state-last-error))))

(ert-deftest gh-radar-process-test-inflight-coalescing ()
  "Test that in-flight process is not deleted without force flag."
  (let* ((proc (make-process
                :name "test-inflight"
                :command '("sleep" "5")))
         (gh-radar-process--current proc)
         (callback-called nil))
    (unwind-protect
        (progn
          ;; calling without force should not delete proc
          (gh-radar-process-fetch-repos
           (lambda (_) (setq callback-called t))
           nil)
          (should (process-live-p proc))
          (should callback-called)
          ;; calling with force should kill proc
          (gh-radar-process-fetch-repos nil t)
          (should (process-get proc :cancelled)))
      (when (process-live-p proc)
        (delete-process proc)))))

(ert-deftest gh-radar-process-test-grace-period ()
  "Test startup grace period checks and retry scheduling."
  (let ((gh-radar-startup-grace-period 30)
        (gh-radar--start-time (current-time)))
    (should (gh-radar-process--in-grace-period-p))
    (let ((gh-radar--start-time (time-subtract (current-time) 60)))
      (should-not (gh-radar-process--in-grace-period-p)))
    (let ((gh-radar-startup-grace-period 0))
      (should-not (gh-radar-process--in-grace-period-p)))))

(ert-deftest gh-radar-process-test-grace-period-suppresses-error ()
  "Test that failures during grace period suppress error state and retry."
  (let ((gh-radar-startup-grace-period 30)
        (gh-radar--start-time (current-time))
        (gh-radar-state-last-error nil)
        (gh-radar-repos '(("test/repo" "issues")))
        (gh-radar-gh-executable "false"))
    (unwind-protect
        (progn
          (gh-radar-process-fetch-repos nil t)
          (while (and gh-radar-process--current
                      (process-live-p gh-radar-process--current))
            (accept-process-output gh-radar-process--current 0.05))
          (should-not gh-radar-state-last-error)
          (should gh-radar-process--grace-timer))
      (gh-radar-process-cancel-grace-timer)
      (when (and gh-radar-process--current
                 (process-live-p gh-radar-process--current))
        (delete-process gh-radar-process--current)))))

(provide 'gh-radar-process-test)
;;; gh-radar-process-test.el ends here
