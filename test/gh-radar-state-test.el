;;; gh-radar-state-test.el --- Tests for state -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Szymon Wilczek
;; Author: Szymon Wilczek <swilczek.lx@gmail.com>
;; License: GPL-3.0-or-later

;;; Commentary:
;; Unit tests for in-memory state tracking, deltas, and unread queue.

;;; Code:

(require 'test-helper)

(ert-deftest gh-radar-state-test-initial-update ()
  "Test initial state update populates watermarks without false deltas."
  (let* ((tmp (make-temp-file "gh-radar-state-test" nil ".eld"))
         (gh-radar-cache-file tmp)
         (gh-radar-cache--data nil)
         (gh-radar-state-data nil)
         (records '((:repo "o/r" :owner "o" :name "r" :issues 10 :pr 5
                           :recent-issues ((:number 10 :title "Issue 10"))
                           :recent-prs ((:number 5 :title "PR 5"))))))
    (unwind-protect
        (progn
          (gh-radar-state-update records)
          (let ((state (gh-radar-state-get "o/r")))
            (should state)
            (should (= (plist-get state :issues) 10))
            (should (= (plist-get state :pr) 5))
            (should (= (plist-get state :last-seen-issue) 10))
            (should (= (plist-get state :last-seen-pr) 5))
            (should (= (plist-get state :new-issues) 0))
            (should (= (plist-get state :new-pr) 0))))
      (when (file-exists-p tmp)
        (delete-file tmp)))))

(ert-deftest gh-radar-state-test-delta-detection ()
  "Test detecting new issues and PRs arriving in subsequent fetch."
  (let* ((tmp (make-temp-file "gh-radar-state-test" nil ".eld"))
         (gh-radar-cache-file tmp)
         (gh-radar-cache--data nil)
         (gh-radar-state-data nil)
         (rec1 '((:repo "o/r" :owner "o" :name "r" :issues 10 :pr 5
                        :recent-issues ((:number 10 :title "Issue 10"))
                        :recent-prs ((:number 5 :title "PR 5")))))
         (rec2 '((:repo "o/r" :owner "o" :name "r" :issues 11 :pr 6
                        :recent-issues ((:number 11 :title "Issue 11")
                                        (:number 10 :title "Issue 10"))
                        :recent-prs ((:number 6 :title "PR 6")
                                     (:number 5 :title "PR 5"))))))
    (unwind-protect
        (progn
          (gh-radar-state-update rec1)
          (gh-radar-state-update rec2)
          (let ((state (gh-radar-state-get "o/r")))
            (should (= (plist-get state :issues) 11))
            (should (= (plist-get state :pr) 6))
            (should (= (plist-get state :new-issues) 1))
            (should (= (plist-get state :new-pr) 1))
            (should (= (length (plist-get state :unread-issues)) 1))
            (should (= (plist-get (car (plist-get state :unread-issues))
                                  :number)
                       11))))
      (when (file-exists-p tmp)
        (delete-file tmp)))))

(ert-deftest gh-radar-state-test-dismiss-unread ()
  "Test dismissing individual and all unread items."
  (let* ((tmp (make-temp-file "gh-radar-state-test" nil ".eld"))
         (gh-radar-cache-file tmp)
         (gh-radar-cache--data nil)
         (gh-radar-state-data nil)
         (rec1 '((:repo "o/r" :owner "o" :name "r" :issues 1 :pr 0
                        :recent-issues ((:number 1 :title "Old"))
                        :recent-prs nil)))
         (rec2 '((:repo "o/r" :owner "o" :name "r" :issues 3 :pr 0
                        :recent-issues ((:number 3 :title "New 3")
                                        (:number 2 :title "New 2")
                                        (:number 1 :title "Old"))
                        :recent-prs nil))))
    (unwind-protect
        (progn
          (gh-radar-state-update rec1)
          (gh-radar-state-update rec2)
          (should (= (length (gh-radar-state-unread-items)) 2))
          ;; dismiss one
          (gh-radar-state-dismiss-item "o/r" :issue 2)
          (should (= (length (gh-radar-state-unread-items)) 1))
          ;; dismiss all
          (gh-radar-state-dismiss-all)
          (should (= (length (gh-radar-state-unread-items)) 0)))
      (when (file-exists-p tmp)
        (delete-file tmp)))))

(ert-deftest gh-radar-state-test-notifications ()
  "Test notification state tracking."
  (let ((gh-radar-state-notifications nil))
    (gh-radar-state-update-notifications 5 '((:id "1" :title "Notif 1")))
    (should (= (plist-get gh-radar-state-notifications :count) 5))
    (should (= (length (plist-get gh-radar-state-notifications :items)) 1))
    (gh-radar-state-update-notifications 7 '((:id "2" :title "Notif 2")))
    (should (= (plist-get gh-radar-state-notifications :count) 7))
    (should (= (plist-get gh-radar-state-notifications :new) 2))))

(provide 'gh-radar-state-test)
;;; gh-radar-state-test.el ends here
