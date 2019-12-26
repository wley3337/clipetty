;;; clipetty.el --- Manipulate the system (clip)board with (e)macs from a (TTY)

;; Copyright (C) 2019 Mike Hamrick

;; Author: Mike Hamrick <mikeh@muppetlabs.com>
;; Maintainer: Mike Hamrick <mikeh@muppetlabs.com>
;; Created: 25 Dec 2019
;; Modified: 25 Dec 2029
;; Version: 0.1
;; Package-Requires: ((emacs "24.3") (use-package "2.4"))
;; Keywords: clipboard tty osc terminal
;; URL: https://github.com/spudlyo/clippety

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 3, or (at
;; your option) any later version.

;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.

;;; Commentary:

;; Sends ANSI "Operating System Command" (OSC) 52 escape sequences, and
;; attempts to wrap these sequences in a correctly flavored "Device Control
;; String" (DCS) where appropriate.
;;
;; Please see README.org from the same repository for documentation.

;;; Code:

(defcustom clipetty-assume-nested-mux t
  "Non-nil means if we detect a remote multiplexer, we assume it's nested.
Nesting is the practice of running a terminal multiplexer inside
a terminal multiplexer, which is what you'd be doing if you ran
tmux both locally and on remote hosts you SSH into."
  :type 'boolean
  :group 'clipetty)

;; The maximum OSC 52 message is 10,000 bytes. This means we can support base64
;; encoded strings of up to 74,994 bytes long.
(defvar clipetty-max-cut 74994)

(defun clipetty-tty ()
  "Return which TTY we should send our OSC payload to."
  (let ((ssh-tty (getenv "SSH_TTY" (selected-frame)))
        (showenv "tmux show-environment SSH_TTY | cut -d'=' -f2 | tr -d '\n'"))
    (if (not ssh-tty) (terminal-name)
      (if (getenv "TMUX" (selected-frame))
          ;; If we're SSH'd into a host running tmux that means `$SSH_TTY' could
          ;; very well be stale due to detach/re-attach. This workaround queries
          ;; tmux itself, rather than the environment variable to get the
          ;; current value of `SSH_TTY'. This requires you to add the following
          ;; to your .tmux.conf:
          ;;
          ;;     set -ag update-environment "SSH_TTY"
          ;;
          ;; As far as I know, there exists no such workaround for GNU screen.
          (shell-command-to-string showenv)
        ssh-tty))))

(defun clipetty-dcs-wrap (string)
  "Return STRING wrapped in an appropriate DCS if necessary."
  (let ((tmuxp   (getenv "TMUX" (selected-frame)))
        (screenp (string-match-p "screen" (getenv "TERM" (selected-frame))))
        (remotep (getenv "SSH_TTY" (selected-frame)))
        (dcs      string))
    (cond (screenp (setq dcs (concat "\eP" string "\e\\")))
          (tmuxp   (setq dcs (concat "\ePtmux;\e" string "\e\\"))))
    (if (and remotep (not clipetty-assume-nested-mux)) string dcs)))

(defun clipetty-emit (string)
  "Emit STRING, optionally wrapped in a DCS, to an appropriate tty."
  (if (<= (length string) clipetty-max-cut)
      (write-region (clipetty-dcs-wrap string) nil (clipetty-tty) t 0)
    (message "Selection too long to send to terminal %d" (length string))
    (sit-for 1)))

(defun clipetty-osc (string &optional encode)
  "Return an OSC 52 escape sequence out of STRING.
Optionally base64 encode it first if you specify non-nil for ENCODE."
  (let ((bin (base64-encode-string (encode-coding-string string 'binary) t)))
    (concat "\e]52;c;" (if encode bin string) "\a")))

(defun clipetty-cut (string)
  "If in a terminal frame, convert STRING to a series of OSC 52 messages."
  (if (display-graphic-p)
      (gui-select-text string)
    ;; An exclamation mark is an invalid base64 string. This signals to the
    ;; Kitty terminal emulator to reset the clipboard.  Other terminals will
    ;; simply ignore this.
    ;;
    ;; TODO: Support longer than `clipetty-max-cut' length messages in Kitty.
    (clipetty-emit (clipetty-osc "!"))
    (clipetty-emit (clipetty-osc string t))))

(defun clipetty-init ()
  "Initialize the `interprogram-cut-function'."
  (interactive)
  (setq interprogram-cut-function 'clipetty-cut))

(defun clipetty-kill-ring-save (beg end &optional region)
  "Enables clipetty for this save, passes BEG END and optionally REGION."
  (let (old-interprogram-cut-function interprogram-cut-function)
    (setq interprogram-cut-function 'clipetty-cut)
    (kill-ring-save beg end region)
    (setq interprogram-cut-function 'old-iinterprogram-cut-function)))

(provide 'clipetty)

;;; clipetty.el ends here