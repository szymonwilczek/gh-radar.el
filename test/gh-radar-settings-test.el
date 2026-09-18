;;; gh-radar-settings-test.el --- Settings tests -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Szymon Wilczek
;; Author: Szymon Wilczek <swilczek.lx@gmail.com>
;; License: GPL-3.0-or-later

;;; Commentary:
;; Unit tests for interactive settings buffer and toggle handlers.

;;; Code:

(require 'test-helper)

(ert-deftest gh-radar-settings-test-render ()
  "Test rendering settings buffer."
  (let* ((tmp (make-temp-file "gh-radar-settings-test" nil ".eld"))
         (gh-radar-cache-file tmp)
         (gh-radar-cache--data nil)
         (buf (get-buffer-create "*gh-radar-test-settings*")))
    (unwind-protect
        (with-current-buffer buf
          (gh-radar-settings-mode)
          (gh-radar-cache-set-repos '(("owner/repo" "issues" "pr")))
          (gh-radar-settings-render buf)
          (let ((content (buffer-string)))
            (should (string-match-p "gh-radar Settings" content))
            (should (string-match-p "General Settings" content))
            (should (string-match-p "Configured Repositories" content))
            (should (string-match-p "owner/repo" content))))
      (when (buffer-live-p buf)
        (kill-buffer buf))
      (when (file-exists-p tmp)
        (delete-file tmp)))))

(ert-deftest gh-radar-settings-test-toggles ()
  "Test toggling settings switches options and updates cache."
  (let* ((tmp (make-temp-file "gh-radar-settings-test" nil ".eld"))
         (gh-radar-cache-file tmp)
         (gh-radar-cache--data nil)
         (gh-radar-track-notifications t)
         (gh-radar-count-display 'all)
         (gh-radar-bell-modeline nil))
    (unwind-protect
        (progn
          (gh-radar-settings-toggle-notifications)
          (should-not gh-radar-track-notifications)
          (gh-radar-settings-toggle-count-display)
          (should (eq gh-radar-count-display 'only-new))
          (gh-radar-settings-toggle-bell)
          (should gh-radar-bell-modeline))
      (when (file-exists-p tmp)
        (delete-file tmp)))))

(ert-deftest gh-radar-settings-test-host ()
  "Test configuring GitHub host in settings."
  (let* ((tmp (make-temp-file "gh-radar-settings-test" nil ".eld"))
         (gh-radar-cache-file tmp)
         (gh-radar-cache--data nil)
         (gh-radar-github-host "github.com"))
    (unwind-protect
        (cl-letf (((symbol-function 'read-string)
                   (lambda (&rest _) "ghe.corp.internal")))
          (gh-radar-settings-set-host)
          (should (equal gh-radar-github-host "ghe.corp.internal"))
          (should (equal (gh-radar-cache-get-setting :github-host)
                         "ghe.corp.internal")))
      (when (file-exists-p tmp)
        (delete-file tmp)))))

(provide 'gh-radar-settings-test)
;;; gh-radar-settings-test.el ends here
