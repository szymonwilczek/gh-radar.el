;;; gh-radar-cache-test.el --- Tests for cache -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Szymon Wilczek
;; Author: Szymon Wilczek <swilczek.lx@gmail.com>
;; License: GPL-3.0-or-later

;;; Commentary:
;; Unit tests for disk persistence and configuration caching.

;;; Code:

(require 'test-helper)

(ert-deftest gh-radar-cache-test-normalize ()
  "Test cache normalization for nil, legacy, and standard plists."
  (let ((empty (gh-radar-cache--normalize nil)))
    (should (eq (plist-get empty :version) 1))
    (should-not (plist-get empty :repos))
    (should-not (plist-get empty :items)))
  (let ((std (gh-radar-cache--normalize
              '(:version 1 :repos (("a/b")) :items nil))))
    (should (equal (plist-get std :repos) '(("a/b"))))))

(ert-deftest gh-radar-cache-test-save-load-roundtrip ()
  "Test saving and loading cache data to a temporary file."
  (let* ((tmp-file (make-temp-file "gh-radar-cache-test" nil ".eld"))
         (gh-radar-cache-file tmp-file)
         (gh-radar-cache--data nil)
         (gh-radar-repos gh-radar-repos)
         (gh-radar-count-display gh-radar-count-display))
    (unwind-protect
        (progn
          (gh-radar-cache-add-repo "foo/bar" '("issues"))
          (gh-radar-cache-set-setting :count-display 'delta)
          ;; reset in-memory cache to force loading from disk
          (setq gh-radar-cache--data nil)
          (let ((loaded (gh-radar-cache-load)))
            (should (equal (plist-get loaded :repos) '(("foo/bar" "issues"))))
            (should (eq (gh-radar-cache-get-setting :count-display) 'delta))))
      (when (file-exists-p tmp-file)
        (delete-file tmp-file)))))

(ert-deftest gh-radar-cache-test-add-remove-repo ()
  "Test adding, updating, and removing configured repositories."
  (let* ((tmp-file (make-temp-file "gh-radar-cache-test" nil ".eld"))
         (gh-radar-cache-file tmp-file)
         (gh-radar-cache--data nil)
         (gh-radar-repos gh-radar-repos))
    (unwind-protect
        (progn
          (gh-radar-cache-add-repo "user/repo1" '("issues" "pr"))
          (gh-radar-cache-add-repo "user/repo2" '("issues"))
          (should (= (length (gh-radar-cache-get-repos)) 2))
          ;; update existing repo targets
          (gh-radar-cache-add-repo "user/repo1" '("pr"))
          (should (= (length (gh-radar-cache-get-repos)) 2))
          (should (equal (cdr (assoc "user/repo1" (gh-radar-cache-get-repos)))
                         '("pr")))
          ;; remove repo
          (gh-radar-cache-remove-repo "user/repo2")
          (should (= (length (gh-radar-cache-get-repos)) 1))
          (should-not (assoc "user/repo2" (gh-radar-cache-get-repos))))
      (when (file-exists-p tmp-file)
        (delete-file tmp-file)))))

(provide 'gh-radar-cache-test)
;;; gh-radar-cache-test.el ends here
