;;; test-helper.el --- Test helper for gh-radar -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Szymon Wilczek
;; Author: Szymon Wilczek <swilczek.lx@gmail.com>
;; License: GPL-3.0-or-later

;;; Commentary:
;; Test helper and environment setup for gh-radar ERT suite.

;;; Code:

(require 'ert)

(let ((root (file-name-directory
             (directory-file-name
              (file-name-directory
               (or load-file-name buffer-file-name))))))
  (add-to-list 'load-path root)
  (add-to-list 'load-path (expand-file-name "test" root)))

(require 'gh-radar-config)
(require 'gh-radar-query)
(require 'gh-radar-cache)

(setq gh-radar-cache-file (make-temp-file "gh-radar-test" nil ".eld"))
(setq gh-radar-cache--data nil)

(require 'gh-radar-state)
(require 'gh-radar-process)
(require 'gh-radar-modeline)
(require 'gh-radar-dashboard)
(require 'gh-radar-settings)
(require 'gh-radar)

(setq gh-radar-count-display 'all)
(setq gh-radar-track-notifications t)
(setq gh-radar-bell-modeline nil)
(setq gh-radar-hide-zero-counts nil)
(setq gh-radar-repos nil)
(setq gh-radar-state-data nil)
(setq gh-radar-state-notifications nil)

(provide 'test-helper)
;;; test-helper.el ends here
