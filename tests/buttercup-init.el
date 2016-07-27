;; test utils
(require 'buttercup)
(require 'seq)

;; coverage
;; based on https://github.com/sviridov/undercover.el-buttercup-integration-example/blob/master/tests/test-multiply.el
(require 'undercover-init.el)

;; the tested library
(require 'window-purpose)

;;; save/load purpose configurations
(defun get-purpose-config ()
  (seq-map (lambda (var)
             (cons var (eval var)))
           '(purpose-user-mode-purposes
             purpose-user-name-purposes
             purpose-user-regexp-purposes
             purpose-extended-configuration
             purpose-use-default-configuration)))

(cl-defun make-purpose-config (&key modes names regexps extensions use-default)
  (list (cons 'purpose-user-mode-purposes modes)
        (cons 'purpose-user-name-purposes names)
        (cons 'purpose-user-regexp-purposes regexps)
        (cons 'purpose-extended-configuration extensions)
        (cons 'purpose-use-default-configuration use-default)))

(defun load-purpose-config (config)
  (seq-map (lambda (var-value)
             (set (car var-value) (cdr var-value)))
           config)
  (purpose-compile-user-configuration)
  (purpose-compile-extended-configuration)
  (purpose-compile-default-configuration))

;;; match window recipes and trees
;; trees are extracted from `window-tree' to have similar structure to recipes
(defvar window-data-extractors
  (list :name (lambda (win) (buffer-name (window-buffer win)))
        :purpose #'purpose-window-purpose
        :selected (lambda (win) (eq win (frame-selected-window win)))
        :b-ded #'window-dedicated-p
        :p-ded #'purpose-window-purpose-dedicated-p))

(defvar window-data-comparers
  (list :name #'string=
        :purpose #'eq
        :selected #'eq
        :b-ded #'eq
        :p-ded #'eq))

(defun map-plist (func plist)
  "Apply FUNC to each key-value pair in PLIST.
FUNC is called as (FUNC key value) for each pair."
  (do* ((plist plist (cddr plist))
        (key (car plist) (car plist))
        (value (cadr plist) (cadr plist))
        (result))
      ;; `consp' test stops loop for plist values of `()' and also `(:a)', IOW
      ;; ignores last element if plist has an odd (not even) length
      ((not (consp (cdr plist)))
       (nreverse result))
    (push (funcall func key value) result)))

(defun alist-to-plist (alist)
  (nreverse (seq-reduce
             (lambda (result next-pair)
               (cons (cdr next-pair) (cons (car next-pair) result)))
             alist nil)))

(defun plist-to-alist (plist)
  (map-plist #'cons plist))

(defun extract-window-data (window)
  (alist-to-plist (map-plist (lambda (key extractor)
                               (cons key (funcall extractor window)))
                             window-data-extractors)))

(defun extract-window-tree-1 (tree)
  (if (windowp tree)
      (extract-window-data tree)
    ;; FUTURE: can replace 'split with `extract-split-data' (or something)
    (cons 'split (seq-map #'extract-window-tree-1 (cddr tree)))))

(defun extract-window-tree (&optional frame)
  (extract-window-tree-1 (car (window-tree frame))))

(defun window-matches-recipe-p (window recipe)
  (cl-loop for (key . expect-val) in (plist-to-alist recipe)
           for comparer = (plist-get window-data-comparers key)
           for val = (plist-get window key)
           unless comparer do (error "Unknown comparer %S" key)
           always (funcall comparer val expect-val)))

(defun tree-matches-recipe-p (tree recipe)
  (if (eq (car recipe) 'split)
      ;; should be split
      (and (eq (car tree) 'split)
           (= (length tree) (length recipe))
           (cl-loop for sub-tree in (cdr tree)
                    for sub-recipe in (cdr recipe)
                    always (tree-matches-recipe-p sub-tree sub-recipe)))
    ;; should be window
    (and (not (eq (car tree) 'split))
         (window-matches-recipe-p tree recipe))))

(buttercup-define-matcher :to-match-window-recipe (tree recipe)
  (if (tree-matches-recipe-p tree recipe)
      (cons t (format "Expcted window tree %S to match recipe %S" tree recipe))
    (cons nil (format "Expected window tree %S to be different from recipe %S" tree recipe))))

(buttercup-define-matcher :to-match-window-tree (recipe)
  (let ((tree (extract-window-tree)))
    (if (tree-matches-recipe-p tree recipe)
        (cons t (format "Expcted window recipe %S to match tree %S" recipe tree))
      (cons nil (format "Expected window recipe %S to be different from tree %S" recipe tree)))))

;;; --- obsolete?
(defun frame-buffers (frame)
  (seq-map #'window-buffer (window-list frame 'no-minibuffer)))

(buttercup-define-matcher :to-show-exactly-buffers (frame buffer-names)
  (let ((frame-buffers (seq-map #'buffer-name (frame-buffers frame))))
    (if (equal (sort frame-buffers #'string-lessp)
               (sort buffer-names #'string-lessp))
        (cons t (format "Expcted frame to show exactly %S" buffer-names))
      (cons nil (format "Expcted frame not to show exactly %S" buffer-names)))))

(buttercup-define-matcher :to-show-any-buffers (frame buffer-names)
  (let ((frame-buffs (frame-buffers frame)))
    (if (seq-find (lambda (name)
                    (memq (get-buffer name) frame-buffs))
                  buffer-names)
        (cons t (format "Expected frame to show at least one of %S" buffer-names))
      (cons t (format "Expected frame to show none of %S" buffer-names)))))

(buttercup-define-matcher :to-show-all-buffers (frame buffer-names)
  (let ((frame-buffs (frame-buffers)))
    (if (seq-every-p (lambda (name)
                       (memq (get-buffer name) frame-buffs))
                     buffer-names)
        (cons t (format "Expected frame to show all of %S" buffer-names))
      (cons t (format "Expected frame not to show at least one of %S" buffer-names)))))

(buttercup-define-matcher :to-show-buffer (window buffer-or-name)
  (let ((buff (window-normalize-buffer buffer-or-name))
        (win (window-normalize-window window)))
    (if (eq (window-buffer win) buff)
        (cons t (format "Expected window %S to show %s" win (buffer-name buff)))
      (cons nil (format "Expected window %S not to show %s" win (buffer-name buff))))))
;;; ---


(provide 'buttercup-init)