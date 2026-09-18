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

(provide 'gh-radar-process-test)
;;; gh-radar-process-test.el ends here
