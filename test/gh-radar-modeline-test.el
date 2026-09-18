;;; gh-radar-modeline-test.el --- Tests for modeline -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Szymon Wilczek
;; Author: Szymon Wilczek <swilczek.lx@gmail.com>
;; License: GPL-3.0-or-later

;;; Commentary:
;; Unit tests for mode-line segment rendering and display styles.

;;; Code:

(require 'test-helper)

(ert-deftest gh-radar-modeline-test-empty-state ()
  "Test mode-line returns nil when no metrics exist."
  (let ((gh-radar-state-data nil)
        (gh-radar-state-notifications nil)
        (gh-radar-show-prefix nil))
    (should-not (gh-radar-modeline-format))))

(ert-deftest gh-radar-modeline-test-format-counts-all ()
  "Test mode-line formatting in default 'all counts mode."
  (let ((gh-radar-count-display 'all)
        (gh-radar-show-prefix nil)
        (gh-radar-bell-modeline nil)
        (gh-radar-hide-zero-counts nil)
        (gh-radar-repos '(("o/r" "issues" "pr")))
        (gh-radar-cache--data nil)
        (gh-radar-state-data
         '(("o/r" . (:issues 5 :pr 2 :new-issues 1 :new-pr 0)))))
    (let ((formatted (gh-radar-modeline-format)))
      (should formatted)
      ;; contains issue count and delta
      (should (string-match-p "5" formatted))
      (should (string-match-p "\\+1" formatted))
      ;; contains PR count
      (should (string-match-p "2" formatted)))))

(ert-deftest gh-radar-modeline-test-format-counts-only-new ()
  "Test mode-line formatting in 'only-new counts mode."
  (let ((gh-radar-count-display 'only-new)
        (gh-radar-show-prefix nil)
        (gh-radar-bell-modeline nil)
        (gh-radar-hide-zero-counts nil)
        (gh-radar-repos '(("o/r" "issues" "pr")))
        (gh-radar-cache--data nil)
        (gh-radar-state-data
         '(("o/r" . (:issues 10 :pr 5 :new-issues 3 :new-pr 0)))))
    (let ((formatted (gh-radar-modeline-format)))
      (should formatted)
      (should (string-match-p "\\+3" formatted))
      ;; does not show total 10 when only-new is configured
      (should-not (string-match-p "10" formatted)))))

(ert-deftest gh-radar-modeline-test-bell-mode ()
  "Test mode-line formatting in aggregate bell mode."
  (let ((gh-radar-bell-modeline t)
        (gh-radar-show-bell-icon t)
        (gh-radar-show-prefix nil)
        (gh-radar-repos '(("o/r" "issues" "pr")))
        (gh-radar-cache--data nil)
        (gh-radar-state-data
         '(("o/r" . (:issues 4 :pr 1 :new-issues 2 :new-pr 1)))))
    (let ((formatted (gh-radar-modeline-format)))
      (should formatted)
      ;; bell mode shows aggregate delta +3
      (should (string-match-p "\\+3" formatted)))))

(ert-deftest gh-radar-modeline-test-notifications ()
  "Test mode-line includes notifications indicator when tracked."
  (let ((gh-radar-count-display 'all)
        (gh-radar-track-notifications t)
        (gh-radar-hide-zero-counts nil)
        (gh-radar-show-prefix nil)
        (gh-radar-bell-modeline nil)
        (gh-radar-state-data nil)
        (gh-radar-state-notifications '(:count 7 :new 2)))
    (let ((formatted (gh-radar-modeline-format)))
      (should formatted)
      (should (string-match-p "7" formatted))
      (should (string-match-p "\\+2" formatted)))))

(ert-deftest gh-radar-modeline-test-error-indicator ()
  "Test mode-line displays error indicator when last error is set."
  (let ((gh-radar-state-data nil)
        (gh-radar-state-notifications nil)
        (gh-radar-show-prefix nil)
        (gh-radar-state-last-error "Connection refused"))
    (let ((formatted (gh-radar-modeline-format)))
      (should formatted)
      (should (string-match-p "!" formatted)))))

(provide 'gh-radar-modeline-test)
;;; gh-radar-modeline-test.el ends here
