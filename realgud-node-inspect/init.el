;; Copyright (C) 2019 Free Software Foundation, Inc
;; Author: Rocky Bernstein

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; "node inspect" debugger

(eval-when-compile (require 'cl-lib))   ;For setf.

(require 'realgud)
(require 'realgud-lang-js)
(require 'ansi-color)

(defvar realgud:node-inspect-pat-hash)
(declare-function make-realgud-loc-pat (realgud-loc))

(defvar realgud:node-inspect-pat-hash (make-hash-table :test 'equal)
  "Hash key is the what kind of pattern we want to match:
backtrace, prompt, etc.  The values of a hash entry is a
realgud-loc-pat struct")

;; before a command prompt.
;; For example:
;;   break in /home/indutny/Code/git/indutny/myscript.js:1
(setf (gethash "loc" realgud:node-inspect-pat-hash)
      (make-realgud-loc-pat
       :regexp (format
		"\\(?:%s\\)*\\(?:break\\|exception\\|Break on start\\) in \\(?:file://\\)?%s:%s"
		realgud:js-term-escape "\\([^:]+\\)"
		realgud:regexp-captured-num)
       :file-group 1
       :line-group 2))

;; Regular expression that describes a node-inspect command prompt
;; For example:
;;   debug>
(setf (gethash "prompt" realgud:node-inspect-pat-hash)
      (make-realgud-loc-pat
       :regexp (format "^\\(?:%s\\)*debug> " realgud:js-term-escape)
       ))

;; Need an improved setbreak for this.
;; ;;  Regular expression that describes a "breakpoint set" line
;; ;;   3 const armlet = require('armlet');
;; ;; * 4 const client = new armlet.Client(
;; ;; ^^^^
;; ;;
;; (setf (gethash "brkpt-set" realgud:node-inspect-pat-hash)
;;       (make-realgud-loc-pat
;;        :regexp "^\*[ ]*\\([0-9]+\\) \\(.+\\)"
;;        :line-group 1
;;        :text-group 2))

;; Regular expression that describes a V8 backtrace line.
;; For example:
;;    at repl:1:7
;;    at Interface.controlEval (/src/external-vcs/github/trepanjs/lib/interface.js:352:18)
;;    at REPLServer.b [as eval] (domain.js:183:18)
(setf (gethash "lang-backtrace" realgud:node-inspect-pat-hash)
  realgud:js-backtrace-loc-pat)

;; Regular expression that describes a debugger "delete" (breakpoint)
;; response.
;; For example:
;;   Removed 1 breakpoint(s).
(setf (gethash "brkpt-del" realgud:node-inspect-pat-hash)
      (make-realgud-loc-pat
       :regexp (format "^Removed %s breakpoint(s).\n"
		       realgud:regexp-captured-num)
       :num 1))


(defconst realgud:node-inspect-frame-start-regexp  "\\(?:^\\|\n\\)\\(?:#\\)")
(defconst realgud:node-inspect-frame-num-regexp    realgud:regexp-captured-num)
(defconst realgud:node-inspect-frame-module-regexp "[^ \t\n]+")
(defconst realgud:node-inspect-frame-file-regexp   "[^ \t\n]+")

;; Regular expression that describes a debugger "backtrace" command line.
;; For example:
;; #0 module.js:380:17
;; #1 dbgtest.js:3:9
;; #2 Module._compile module.js:456:26
;;
;; and with a newer node inspect:
;;
;; #0 file:///tmp/module.js:380:17
;; #1 file:///tmp/dbgtest.js:3:9
;; #2 Module._compile file:///tmpmodule.js:456:26
(setf (gethash "debugger-backtrace" realgud:node-inspect-pat-hash)
      (make-realgud-loc-pat
       :regexp 	(format "%s%s\\(?: %s\\)? \\(?:file://\\)?\\(%s\\):%s:%s"
			realgud:node-inspect-frame-start-regexp
			realgud:node-inspect-frame-num-regexp
			realgud:node-inspect-frame-module-regexp
			realgud:node-inspect-frame-file-regexp
			realgud:regexp-captured-num
			realgud:regexp-captured-num
			)
       :num 1
       :file-group 2
       :line-group 3
       :char-offset-group 4))

(defconst realgud:node-inspect-debugger-name "node-inspect" "Name of debugger.")

;; ;; Regular expression that for a termination message.
;; (setf (gethash "termination" realgud:node-inspect-pat-hash)
;;        "^node-inspect: That's all, folks...\n")

(setf (gethash "font-lock-keywords" realgud:node-inspect-pat-hash)
      '(
	;; The frame number and first type name, if present.
	;; E.g. ->0 in file `/etc/init.d/apparmor' at line 35
	;;      --^-
	("^\\(->\\|##\\)\\([0-9]+\\) "
	 (2 realgud-backtrace-number-face))

	;; File name.
	;; E.g. ->0 in file `/etc/init.d/apparmor' at line 35
	;;          ---------^^^^^^^^^^^^^^^^^^^^-
	("[ \t]+\\(in\\|from\\) file `\\(.+\\)'"
	 (2 realgud-file-name-face))

	;; File name.
	;; E.g. ->0 in file `/etc/init.d/apparmor' at line 35
	;;                                         --------^^
	;; Line number.
	("[ \t]+at line \\([0-9]+\\)$"
	 (1 realgud-line-number-face))
	))

(setf (gethash "node-inspect" realgud-pat-hash)
      realgud:node-inspect-pat-hash)

;;  Prefix used in variable names (e.g. short-key-mode-map) for
;; this debugger

(setf (gethash "node-inspect" realgud:variable-basename-hash)
      "realgud:node-inspect")

(defvar realgud:node-inspect-command-hash (make-hash-table :test 'equal)
  "Hash key is command name like 'finish' and the value is
the node-inspect command to use, like 'out'.")

(setf (gethash realgud:node-inspect-debugger-name
	       realgud-command-hash)
      realgud:node-inspect-command-hash)

(setf (gethash "backtrace"        realgud:node-inspect-command-hash) "backtrace")
(setf (gethash "break"            realgud:node-inspect-command-hash)
      "setBreakpoint('%X',%l)")
(setf (gethash "clear"            realgud:node-inspect-command-hash)
      "clearBreakpoint('%X', %l)")
(setf (gethash "continue"         realgud:node-inspect-command-hash) "cont")
(setf (gethash "eval"             realgud:node-inspect-command-hash) "exec('%s')")
(setf (gethash "finish"           realgud:node-inspect-command-hash) "out")
(setf (gethash "info-breakpoints" realgud:node-inspect-command-hash) "breakpoints")
(setf (gethash "kill"             realgud:node-inspect-command-hash) "kill")
(setf (gethash "quit"             realgud:node-inspect-command-hash) ".exit")
(setf (gethash "shell"            realgud:node-inspect-command-hash) "repl")

;; We need aliases for step and next because the default would
;; do step 1 and node-inspect doesn't handle this. And if it did,
;; it would probably look like step(1).
(setf (gethash "step"       realgud:node-inspect-command-hash) "step")
(setf (gethash "next"       realgud:node-inspect-command-hash) "next")

;; Unsupported features:
(setf (gethash "jump"       realgud:node-inspect-command-hash) "*not-implemented*")
(setf (gethash "up"         realgud:node-inspect-command-hash) "*not-implemented*")
(setf (gethash "down"       realgud:node-inspect-command-hash) "*not-implemented*")
(setf (gethash "frame"      realgud:node-inspect-command-hash) "*not-implemented*")

(setf (gethash "node-inspect" realgud-command-hash) realgud:node-inspect-command-hash)
(setf (gethash "node-inspect" realgud-pat-hash) realgud:node-inspect-pat-hash)

(provide-me "realgud:node-inspect-")
