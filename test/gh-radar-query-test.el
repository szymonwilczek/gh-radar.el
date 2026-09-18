;;; gh-radar-query-test.el --- Tests for query -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Szymon Wilczek
;; Author: Szymon Wilczek <swilczek.lx@gmail.com>
;; License: GPL-3.0-or-later

;;; Commentary:
;; Unit tests for GraphQL query construction and target parsing.

;;; Code:

(require 'test-helper)

(ert-deftest gh-radar-query-test-parse-target ()
  "Test normalization of target strings and symbols."
  (should (eq (gh-radar-query--parse-target "issues") :issues))
  (should (eq (gh-radar-query--parse-target ":issues") :issues))
  (should (eq (gh-radar-query--parse-target 'issues) :issues))
  (should (eq (gh-radar-query--parse-target ":issues") :issues))
  (should (eq (gh-radar-query--parse-target "pr") :pr))
  (should (eq (gh-radar-query--parse-target ":pr") :pr))
  (should (eq (gh-radar-query--parse-target "pulls") :pr))
  (should (eq (gh-radar-query--parse-target 'pr) :pr))
  (should-not (gh-radar-query--parse-target "unknown"))
  (should-not (gh-radar-query--parse-target ""))
  (should-not (gh-radar-query--parse-target nil)))

(ert-deftest gh-radar-query-test-parse-repo-entry ()
  "Test parsing of repository configuration entries."
  (should (equal (gh-radar-query--parse-repo-entry '("owner/repo"))
                 '("owner" "repo" (:issues :pr))))
  (should (equal (gh-radar-query--parse-repo-entry '("owner/repo" "issues"))
                 '("owner" "repo" (:issues))))
  (should (equal (gh-radar-query--parse-repo-entry '("owner/repo" "pr"))
                 '("owner" "repo" (:pr))))
  (should (equal (gh-radar-query--parse-repo-entry '("  foo/bar  " "pulls"))
                 '("foo" "bar" (:pr))))
  (should-not (gh-radar-query--parse-repo-entry '("invalid-repo")))
  (should-not (gh-radar-query--parse-repo-entry '("too/many/slashes")))
  (should-not (gh-radar-query--parse-repo-entry '("/empty-owner")))
  (should-not (gh-radar-query--parse-repo-entry '("empty-name/"))))

(ert-deftest gh-radar-query-test-build-empty ()
  "Test query builder when repositories list is empty or invalid."
  (should-not (gh-radar-query-build nil))
  (should-not (gh-radar-query-build '()))
  (should-not (gh-radar-query-build '(("invalid-entry")))))

(ert-deftest gh-radar-query-test-build-single-repo ()
  "Test query builder for a single repository."
  (let* ((built (gh-radar-query-build '(("szymonwilczek/octo.el"))))
         (query (car built))
         (alias-map (cdr built)))
    (should (string-prefix-p "query {" query))
    (should (string-match-p "repo_0: repository(owner: \"szymonwilczek\""
                            query))
    (should (string-match-p "issues(states: OPEN" query))
    (should (string-match-p "pullRequests(states: OPEN" query))
    (should (= (length alias-map) 1))
    (let ((meta (cdar alias-map)))
      (should (equal (plist-get meta :owner) "szymonwilczek"))
      (should (equal (plist-get meta :name) "octo.el"))
      (should (equal (plist-get meta :repo) "szymonwilczek/octo.el"))
      (should (equal (plist-get meta :targets) '(:issues :pr))))))

(ert-deftest gh-radar-query-test-build-multiple-repos ()
  "Test query builder for multiple repositories with specific targets."
  (let* ((repos '(("user1/repo1" "issues")
                  ("user2/repo2" "pr")))
         (built (gh-radar-query-build repos))
         (query (car built))
         (alias-map (cdr built)))
    (should (string-match-p "repo_0: repository" query))
    (should (string-match-p "repo_1: repository" query))
    (should (= (length alias-map) 2))
    (should (equal (plist-get (cdr (nth 0 alias-map)) :targets) '(:issues)))
    (should (equal (plist-get (cdr (nth 1 alias-map)) :targets) '(:pr)))))

(ert-deftest gh-radar-query-test-page-info ()
  "Test query builder includes pageInfo hasNextPage field."
  (let* ((built (gh-radar-query-build '(("owner/repo"))))
         (query (car built)))
    (should (string-match-p "pageInfo { hasNextPage }" query))))

(provide 'gh-radar-query-test)
;;; gh-radar-query-test.el ends here
