;;; gh-radar-dashboard-test.el --- Dashboard tests -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Szymon Wilczek
;; Author: Szymon Wilczek <swilczek.lx@gmail.com>
;; License: GPL-3.0-or-later

;;; Commentary:
;; Unit tests for dashboard rendering, relative time formatting, and layout.

;;; Code:

(require 'test-helper)

(ert-deftest gh-radar-dashboard-test-time-ago ()
  "Test relative time formatting helper."
  (should (equal (gh-radar-dashboard--time-ago nil) "never"))
  (let ((now (current-time)))
    (should (equal (gh-radar-dashboard--time-ago now) "just now"))
    (should (equal (gh-radar-dashboard--time-ago
                    (time-subtract now (seconds-to-time 120)))
                   "2m ago"))
    (should (equal (gh-radar-dashboard--time-ago
                    (time-subtract now (seconds-to-time 7200)))
                   "2h ago"))
    (should (equal (gh-radar-dashboard--time-ago
                    (time-subtract now (seconds-to-time (* 86400 3))))
                   "3d ago"))))

(ert-deftest gh-radar-dashboard-test-width ()
  "Test dashboard width calculation adheres to bounds."
  (let ((gh-radar-dashboard-max-width 90))
    (should (>= (gh-radar-dashboard-width) 40))
    (should (<= (gh-radar-dashboard-width) 90))))

(ert-deftest gh-radar-dashboard-test-render-empty ()
  "Test rendering dashboard buffer with empty state."
  (let ((gh-radar-state-data nil)
        (gh-radar-track-notifications nil)
        (buf (get-buffer-create "*gh-radar-test-dashboard*")))
    (unwind-protect
        (with-current-buffer buf
          (gh-radar-dashboard-mode)
          (gh-radar-dashboard-render)
          (let ((content (buffer-string)))
            (should (string-match-p "gh-radar" content))
            (should (string-match-p "No repository data available" content))))
      (when (buffer-live-p buf)
        (kill-buffer buf)))))

(ert-deftest gh-radar-dashboard-test-render-with-data ()
  "Test rendering dashboard buffer with populated repository state."
  (let* ((gh-radar-state-data
          '(("user/repo" . (:owner "user" :name "repo" :issues 12 :pr 3
                                   :new-issues 1 :new-pr 0
                                   :unread-issues ((:number 42 :title "Bug fix"
                                                            :author "alice" :url "http://x"))
                                   :unread-prs nil))))
         (buf (get-buffer-create "*gh-radar-test-dashboard*")))
    (unwind-protect
        (with-current-buffer buf
          (gh-radar-dashboard-mode)
          (gh-radar-dashboard-render)
          (let ((content (buffer-string)))
            (should (string-match-p "user/repo" content))
            (should (string-match-p "New Activity" content))
            (should (string-match-p "#42" content))
            (should (string-match-p "Bug fix" content))))
      (when (buffer-live-p buf)
        (kill-buffer buf)))))

(provide 'gh-radar-dashboard-test)
;;; gh-radar-dashboard-test.el ends here
