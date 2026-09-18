;;; gh-radar-config-test.el --- Tests for config -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Szymon Wilczek
;; Author: Szymon Wilczek <swilczek.lx@gmail.com>
;; License: GPL-3.0-or-later

;;; Commentary:
;; Unit tests for configuration options and icon resolution.

;;; Code:

(require 'test-helper)

(ert-deftest gh-radar-config-test-resolve-icon-fallback ()
  "Test resolving icon returns fallback when key is not in gh-radar-icons."
  (let ((gh-radar-icons nil))
    (should (equal (gh-radar-resolve-icon :unknown "F") "F"))
    (should (equal (gh-radar-resolve-icon :unknown "F" 'bold)
                   (propertize "F" 'face 'bold 'font-lock-face 'bold)))))

(ert-deftest gh-radar-config-test-resolve-icon-custom ()
  "Test resolving icon returns custom glyph configured in gh-radar-icons."
  (cl-letf (((symbol-function 'display-graphic-p) (lambda () t)))
    (let ((gh-radar-icons '((issues . "!"))))
      (should (equal (gh-radar-icon :issues) "!")))))

(ert-deftest gh-radar-config-test-defaults ()
  "Test default values for primary customizable variables."
  (should (> gh-radar-interval 0))
  (should (memq gh-radar-count-display '(all only-new)))
  (should (integerp gh-radar-recent-items-limit)))

(ert-deftest gh-radar-config-test-github-host ()
  "Test configurable GitHub Enterprise host."
  (should (stringp gh-radar-github-host))
  (let ((gh-radar-github-host "ghe.myorg.internal"))
    (should (equal gh-radar-github-host "ghe.myorg.internal"))))

(provide 'gh-radar-config-test)
;;; gh-radar-config-test.el ends here
