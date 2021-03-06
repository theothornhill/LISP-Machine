;;; -*- Mode:LISP; Package:SYSTEM-INTERNALS; Readtable:T; Base:8 -*-

;(defsubst %region-origin (region)
;  (aref #'region-origin region))

(defmacro define-region-accessor ((name . args) &body body)
  (let ((set-name (intern (string-append "SET-" (symbol-name name))))
        (set-args (append args '(value))))
    (loop for form in body
          when (eq (car form) :array)
            collect `(defun ,name ,args (aref ,(cadr form) ,(car args))) into result
            and collect `(defun ,name ,set-args (aset value ,(cadr form) ,(car args))) into result
          else when (eq (car form) :access)
            collect `(defun ,name ,args ,@(cdr form)) into result
          else when (eq (car form) :modify)
            collect `(defun ,set-name ,set-args ,@(cdr form)) into result
          finally (return (append '(progn) result `((defsetf ',name ',set-name)))))))

(define-region-accessor (%region-type region)
 ; (:access (%p-ldb-offset %%region-space-type (%region-origin region-bits) region))
  (:modify (%p-dpb-offset value %%region-space-type (%region-origin region-bits) region)))

(define-region-accessor (%region-representation-type region)
 ; (:access (%p-ldb-offset %%region-representation-type (%region-origin region-bits) region))
  (:modify
    (%p-dpb-offset value %%region-representation-type (%region-origin region-bits) region)))

;(define-region-accessor (%region-area region)
;  (:array #'region-area-map))

;(define-region-accessor (%region-bits region)
;  (:array #'region-bits))

;(define-region-accessor (%region-size region)
;  (:array #'region-size))

(define-region-accessor (%region-free-pointer region)
;  (:access (%p-contents-offset (%region-origin region-free-pointer) region))
;  (:modify (%p-store-contents-offset value (%region-origin region-free-pointer) region))
  )

(define-region-accessor (%region-scavenge-pointer region)
  (:array #'region-scavenge-pointer))

(define-region-accessor (%region-flippable? region)
  (:access
    (not (zerop (%p-ldb-offset %%region-flip-enable (%region-origin region-bits) region))))
  (:modify
    (%p-dpb-offset (if value 1 0) %%region-flip-enable (%region-origin region-bits) region)))

(define-region-accessor (%region-scavengeable? region)
  (:access
    (not (zerop (%p-ldb-offset %%region-scavenge-enable (%region-origin region-bits) region))))
  (:modify
    (%p-dpb-offset (if value 1 0) %%region-scavenge-enable (%region-origin region-bits) region)))

(define-region-accessor (%region-volatility region)
;  (:access
;    (- 3 (%p-ldb-offset %%region-volatility (%region-origin region-bits) region)))
  (:modify
    (%p-dpb-offset (- 3 value) %%region-volatility (%region-origin region-bits) region)))

(define-region-accessor (%region-swap-quantum region)
  (:access
    (%p-ldb-offset %%region-swapin-quantum (%region-origin region-bits) region))
  (:modify
    (%p-dpb-offset value %%region-swapin-quantum (%region-origin region) region)))

;;; Lisp Machine storage examiner.  KHS@LMI, December 1984.

(defsubst area-space-type (area)
  (ldb #.%%region-space-type (aref #'area-region-bits area)))

(defsubst region-space-type (region)
  (ldb #.%%region-space-type (aref #'region-bits region)))

(defsubst region-representation-type (region)
  (ldb #.%%region-representation-type (aref #'region-bits region)))

;(defsubst page-number (address)
;  (ldb #o1021 address))

;(defsubst page-index (address)
;  (ldb #o0010 address))

(defsubst pages-in-region (region)
  (floor (%region-free-pointer region) #.page-size))

(defsubst virtual-address-resident? (address)
  (or (system:%page-status address)
      (= (region-space-type (%region-number address)) #.%region-space-fixed)))

(defsubst io-space-pointer? (pointer)
  ( (%pointer-unsigned pointer) (%pointer-unsigned io-space-virtual-address)))

;;;

(defsubst dynamic-space-region? (region)
  (eq (region-space-type region) #.%region-space-new))

(defsubst old-space-region? (region)
  (eq (region-space-type region) #.%region-space-old))

(defsubst copy-space-region? (region)
  (eq (region-space-type region) #.%region-space-copy))

(defsubst static-space-region? (region)
  (eq (region-space-type region) #.%region-space-static))

(defsubst list-representation-region? (region)
  (eq (region-representation-type region) #.%region-representation-type-list))

(defsubst structure-representation-region? (region)
  (eq (region-representation-type region) #.%region-representation-type-structure))

(defsubst region-scavenge-enabled? (region)
  (not (zerop (ldb #.%%region-scavenge-enable (aref #'region-bits region)))))

(defsubst region-area (region)
  (%area-number (aref #'region-origin region)))

(defsubst cdr-normal? (address) (= (%p-cdr-code address) cdr-normal))
(defsubst cdr-error? (address) (= (%p-cdr-code address) cdr-error))
(defsubst cdr-next? (address) (= (%p-cdr-code address) cdr-next))
(defsubst cdr-nil? (address) (= (%p-cdr-code address) cdr-nil))

(defun array-leader? (address)
  (and (= (%p-data-type address) dtp-header)
       (= (%p-ldb %%header-type-field address) %header-type-array-leader)))

;;;

(defvar *output-indentation* -2)
(defvar *object-descriptor-table* (make-array 32.))
(defvar *object-size-table* (make-array 32.))

(defun detail-region (region)
  (setq *output-indentation* -2)
  (terpri)
  (loop with address = (aref #'region-origin region)
        with bound = (%pointer-plus (aref #'region-origin region)
                                    (%region-free-pointer region))
        until ( (%pointer-difference address bound) 1)
        for boxed = (%structure-boxed-size address)
        for total = (%structure-total-size address)
        do (describe-storage address)
        unless (and (= (%p-data-type address) dtp-array-header)
                    (memq (%p-ldb %%array-type-field address) '(13 15)))
          do (let ((*output-indentation* 0))
               (loop for i from 1 below boxed
                     do (describe-storage (%pointer-plus address i))))
        when ( boxed total)
          do (format t "~&     ")
        when (and (= boxed total)
                  (= (%p-data-type (+ address total -1)) dtp-header-forward)
                  (= (%p-cdr-code (+ address total -1)) cdr-normal))
          do (incf address (- total 1))
        else
          do (incf address total)))

;       do (multiple-value-bind (boxed total)
;              (compute-object-size address)
;            (unless (and (= boxed (%structure-boxed-size address))
;                         (= total (%structure-total-size address)))
;              (unless (array-leader? address)
;                (ferror "Structure size inconsistent.")))
;            (describe-storage address)
;            (let ((*output-indentation* 0))
;              (loop for i from 1 below boxed
;                    do (unless (= (%pointer address) (%pointer (%find-structure-header address)))
;                         (unless (array-leader? address)
;                           (ferror "Couldn't find header")))
;                    do (describe-storage (%pointer-plus address i))))
;            (if ( boxed total) (format t "~&  ..."))
;            (incf address total))))

(defun describe-storage (address)
  (if (%region-number address)
      (let ((*output-indentation* (+ *output-indentation* 2)))
        (funcall (aref *object-descriptor-table* (%p-data-type address)) address))
    (format t "~%Invalid pointer: ~O" address)))

(defun output (address format-control &rest format-args)
  (terpri)
  (dotimes (i *output-indentation*) (tyo #/space))
  (format t "~O ~A ~24T" address (nth (%p-cdr-code address) q-cdr-codes))
  (apply #'format t format-control format-args))

(defmacro describe-object (data-type &body body)
  `(setf (aref *object-descriptor-table* ,(symbol-value data-type))
         (compile-lambda '(lambda (address) ,@body))))

;;;

(describe-object dtp-trap
  (output address "DTP-TRAP"))

(describe-object dtp-null
  (output address "DTP-NULL"))

(describe-object dtp-free
  (output address "DTP-FREE"))

(describe-object dtp-symbol
  (output address "Symbol: ~O ~A"
          (%p-pointer address)
          (%make-pointer dtp-symbol (%p-pointer address))))

(describe-object dtp-symbol-header
  (output address "Symbol-header: ~A" (symbol-name (%make-pointer dtp-symbol address))))

(describe-object dtp-fix
  (output address "Fixnum: ~D" (%p-pointer address)))

(describe-object dtp-extended-number
  (output address "Extended number pointer: ~A"
          (%make-pointer dtp-extended-number (%p-pointer address))))

(describe-object dtp-header
  (select (%p-ldb %%header-type-field address)
    (%header-type-error                            (output address "HEADER-TYPE-ERROR"))
    (%header-type-fef                              (ddt-describe-fef address))
    (%header-type-array-leader                     (ddt-describe-array-leader address))
    (%header-type-list                           (output address "HEADER-TYPE-LIST"))
    (%header-type-flonum                           (ddt-describe-extended-number address))
    (%header-type-complex                          (ddt-describe-extended-number address))
    (%header-type-bignum                           (ddt-describe-extended-number address))
    (%header-type-rational                         (ddt-describe-extended-number address))
    (%header-type-fast-fef-fixed-args-no-locals    (ddt-describe-fef address))
    (%header-type-fast-fef-var-args-no-locals      (ddt-describe-fef address))
    (%header-type-fast-fef-fixed-args-with-locals  (ddt-describe-fef address))
    (%header-type-fast-fef-var-args-with-locals    (ddt-describe-fef address))
    (otherwise                                     (output address "Unknown header type."))))

(defun ddt-describe-fef (address)
  (output address "FEF Header: ~S" (function-name (%make-pointer dtp-fef-pointer address))))

(defun ddt-describe-extended-number (address)
  (output address "Extended number: ~A" (%make-pointer dtp-extended-number address)))

(defun ddt-describe-array-leader (address)
  (let ((length (%p-ldb %%array-leader-length address)))
    (output address "Array leader: ~D elements" (- length 2))))

(describe-object dtp-gc-forward
  (output address "GC-forward: ~O" (%p-pointer address)))

(describe-object dtp-external-value-cell-pointer
  (output address "EVCP: ~O" (%p-pointer address)))

(describe-object dtp-one-q-forward
  (output address "One-Q-forward: ~O" (%p-pointer address)))

(describe-object dtp-header-forward
  (output address "Header-forward: ~O" (%p-pointer address)))

(describe-object dtp-body-forward
  (output address "Body-forward: ~O" (%p-pointer address)))

(describe-object dtp-locative
  (let ((*print-level* 2) (*print-length* 2))
    (output address "Locative: ~O ~S"
            (%p-pointer address)
            (catch-error (car (%make-pointer dtp-locative (%p-pointer address))) nil))))

(describe-object dtp-list
  (let ((*print-level* 2) (*print-length* 2))
    (output address "List: ~O ~S"
            (%p-pointer address)
            (%make-pointer dtp-list (%p-pointer address)))))

(describe-object dtp-u-entry
  (output address "Microcode-entry: ~A"
          (function-name (%make-pointer dtp-u-entry (%p-pointer address)))))

(describe-object dtp-fef-pointer
  (output address "~S" (%make-pointer dtp-fef-pointer (%p-pointer address))))

(describe-object dtp-array-pointer
  (output address "Array pointer: ~S"
          (%make-pointer dtp-array-pointer (%p-pointer address))))

(describe-object dtp-array-header
  (let* ((array (%make-pointer dtp-array-pointer address))
         (array-type (%p-ldb %%array-type-field address))
         (displaced? (%p-ldb %%array-displaced-bit address))
         (leader-length (if (zerop (%p-ldb %%array-leader-bit address))
                            0
                          (+ (%p-ldb %%array-leader-length (1- address)) 2))))
    (if (typep array 'string)
        (output address "String: ~S" array)
      (output address "Array header: ~A ~A leader ~A"
              (nth array-type array-types)
              (if (zerop displaced?) "" "(Displaced)")
              leader-length))))

(describe-object dtp-stack-group
  (output address "Stack group: ~A"
          (function-name (%make-pointer dtp-stack-group (%p-pointer address)))))

(describe-object dtp-closure
  (output address "Closure:"))

(describe-object dtp-small-flonum
  (output address "Small flonum: ~S"
          (%make-pointer dtp-small-flonum (%p-pointer address))))

(describe-object dtp-select-method
  (output address "Select method: ~O" (%p-pointer address)))

(describe-object dtp-instance
  (output address "Instance: ~O ~S"
          (%p-pointer address)
          (%make-pointer dtp-instance (%p-pointer address))))

(describe-object dtp-instance-header
  (output address "Instance header: ~S" (%make-pointer dtp-instance address)))

(describe-object dtp-entity
  (output address "Entity: ~O" (%p-pointer address)))

(describe-object dtp-stack-closure
  (output address "Stack closure: ~O" (%p-pointer address)))

(describe-object dtp-self-ref-pointer
  (output address "Self-reference"))

(describe-object dtp-character
  (output address "Character: ~S"
          (%make-pointer dtp-character (%p-pointer address))))

;;;

(defun compute-object-size (address)
  (let ((entry (aref *object-size-table* (%p-data-type address))))
    (if (integerp entry)
        (values entry entry)
      (funcall entry address))))

(defmacro define-object-size (data-type &body body)
  (if (integerp (car body))
      `(setf (aref *object-size-table* ,(symeval data-type)) ,@body)
    `(setf (aref *object-size-table* ,(symeval data-type))
           (compile-lambda '(lambda (address) ,@body)))))

(defun list-object-size (address)
  (loop for i from 0 to 100000
        for a = (+ address i)
        for s = 1 then (1+ s)
        when (memq (%p-data-type a)
                   (list dtp-symbol-header
                         dtp-header
                         dtp-array-header
                         dtp-instance-header))
          do (return (compute-object-size a))
        when (or (= (%p-cdr-code a) cdr-error)
                 (= (%p-cdr-code a) cdr-nil))
          do (return s s)))

(define-object-size dtp-trap 1)
(define-object-size dtp-null (list-object-size address))
(define-object-size dtp-free (list-object-size address))
(define-object-size dtp-symbol (list-object-size address))
(define-object-size dtp-symbol-header 5)
(define-object-size dtp-fix (list-object-size address))
(define-object-size dtp-extended-number (list-object-size address))

(define-object-size dtp-header
  (select (%p-ldb %%header-type-field address)
    ((%header-type-fef
      %header-type-fast-fef-fixed-args-no-locals
      %header-type-fast-fef-var-args-no-locals
      %header-type-fast-fef-fixed-args-with-locals
      %header-type-fast-fef-var-args-with-locals)
     (let ((boxed (%p-ldb %%fefh-pc-in-words address)))
       (values boxed (%p-contents-offset address %fefhi-storage-length))))
    (%header-type-array-leader
      (let ((length (%p-ldb %%array-leader-length address)))
        (values length length)))
    (%header-type-flonum
      (values 1 3))
    (%header-type-complex
      (values 3 3))
    (%header-type-bignum
      (values 1 (1+ (%p-ldb #o0022 address))))
    (%header-type-rational
      (values 3 3))
    (%header-type-error
      (ferror nil "%HEADER-TYPE-ERROR at ~O" address))
    (%header-type-list
      (values 1 1))
    (otherwise
      (ferror nil "Unknown header type at ~O" address))))

(define-object-size dtp-gc-forward (list-object-size address))
(define-object-size dtp-external-value-cell-pointer (list-object-size address))
(define-object-size dtp-one-q-forward (list-object-size address))

(define-object-size dtp-header-forward
  (do ((scan (1+ address) (1+ scan)))
      ((neq (%p-data-type scan) dtp-body-forward)
       (values 1 (- scan address)))))

(define-object-size dtp-body-forward 1)
(define-object-size dtp-locative (list-object-size address))
(define-object-size dtp-list (list-object-size address))
(define-object-size dtp-u-entry (list-object-size address))
(define-object-size dtp-fef-pointer (list-object-size address))
(define-object-size dtp-array-pointer (list-object-size address))

(define-object-size dtp-array-header
  ;; This is very dependent on the current world values.  This will be fixed as
  ;; soon as ARRAY-BOXED-WORDS-PER-ELEMENT is defined for the cold load.
  (flet ((boxed-array-size (address words-per-element)
           (let ((length) (offset))
             (cond ((zerop (%p-ldb %%array-long-length-flag address))
                    (setq length (%p-ldb %%array-index-length-if-short address))
                    (setq offset (%p-ldb %%array-number-dimensions address)))
                   (t
                    (setq length (%p-contents-offset address 1))
                    (setq offset (1+ (%p-ldb %%array-number-dimensions address)))))
             (setq length (+ offset (ceiling (* length words-per-element) 1)))
             (values length length)))
         (unboxed-array-size (address words-per-element)
           (let ((length) (offset))
             (cond ((zerop (%p-ldb %%array-long-length-flag address))
                    (setq length (%p-ldb %%array-index-length-if-short address))
                    (setq offset (%p-ldb %%array-number-dimensions address)))
                   (t
                    (setq length (%p-contents-offset address 1))
                    (setq offset (1+ (%p-ldb %%array-number-dimensions address)))))
             (values offset (+ offset (ceiling (* length words-per-element) 1))))))
    (if (not (zerop (%p-ldb %%array-displaced-bit address)))
        (let ((boxed-size (+ (max 1 (%p-ldb %%array-number-dimensions address))
                             (%p-ldb %%array-index-length-if-short address))))
          (values boxed-size boxed-size))
      (case (%p-ldb %%array-type-field address)
        (1  (unboxed-array-size address 1\40))  ;art-1b
        (2  (unboxed-array-size address 1\20))  ;art-2b
        (3  (unboxed-array-size address 1\8))   ;art-4b
        (4  (unboxed-array-size address 1\4))   ;art-8b
        (5  (unboxed-array-size address 1\2))   ;art-16b
        (6  (unboxed-array-size address 1))     ;art-32b
        (7  (boxed-array-size address 1))       ;art-q
        (10 (boxed-array-size address 1))       ;art-q-list
        (11 (unboxed-array-size address 1\4))   ;art-string
        (12 (boxed-array-size address 1))       ;art-stack-group-head
        (13 (unboxed-array-size address 1))     ;art-special-pdl
        (14 (unboxed-array-size address 1\2))   ;art-half-fix
        (15 (unboxed-array-size address 1))     ;art-regular-pdl
        (16 (unboxed-array-size address 2))     ;art-float
        (17 (unboxed-array-size address 1))     ;art-fps-float
        (20 (unboxed-array-size address 1\2))   ;art-fat-string
        (21 (unboxed-array-size address 4))     ;art-complex-float
        (22 (boxed-array-size address 2))       ;art-complex
        (23 (unboxed-array-size address 2))     ;art-complex-fps-float
        ))))

(define-object-size dtp-stack-group (list-object-size address))
(define-object-size dtp-closure (list-object-size address))
(define-object-size dtp-small-flonum (list-object-size address))
(define-object-size dtp-select-method (list-object-size address))
(define-object-size dtp-instance (list-object-size address))

(define-object-size dtp-instance-header
  (let ((boxed (%p-contents-offset (%p-pointer address) %instance-descriptor-size)))
    (values boxed boxed)))

(define-object-size dtp-entity (list-object-size address))
(define-object-size dtp-stack-closure (list-object-size address))
(define-object-size dtp-self-ref-pointer (list-object-size address))
(define-object-size dtp-character (list-object-size address))

;;;

(defmacro for-every-area-in-world ((area) &body body)
  `(dolist (name (current-area-list))
     (let ((,area (symbol-value name)))
       (unless (= (area-space-type ,area) %region-space-fixed)
         ,@body))))

(defmacro for-every-region-in-world ((region) &body body)
  `(do ((,region size-of-area-arrays (1- ,region)))
       ((minusp ,region))
     ,@body))

(defmacro for-every-list-region-in-world ((region) &body body)
  `(for-every-area-in-world (area)
     (for-every-region-in-area (,region area)
       (when (list-representation-region? ,region)
         (format t "~%Searching region ~D of area ~S ..."
                 ,region
                 (aref #'area-name (region-area ,region)))
         ,@body))))

(defmacro for-every-structure-region-in-world ((region) &body body)
  `(for-every-area-in-world (area)
     (for-every-region-in-area (,region area)
       (when (structure-representation-region? ,region)
         (format t "~%Searching region ~D of area ~S ..."
                 ,region
                 (aref #'area-name (region-area ,region)))
         ,@body))))

(defmacro for-every-region-in-area ((region area) &body body)
  `(do ((,region (aref #'area-region-list ,area) (aref #'region-list-thread ,region)))
       ((minusp ,region))
     ,@body))

(defmacro for-every-page-in-region ((region) &body body)
  `(do* ((.base. (page-number (aref #'region-origin ,region)))
         (.size. (floor (%region-free-pointer ,region) #.page-size))
         (.page. 0 (1+ .page.)))
       ((> .page. .size.))
     (let ((page (+ .base. .page.)))
       ,@body)))

(defmacro for-every-object-in-region ((object region) &body body)
  `(let* ((start (aref #'region-origin ,region))
          (stop (%pointer-plus start (%region-free-pointer ,region))))
     (do ((,object start))
         (( (%pointer-difference ,object stop) 0))
       (multiple-value-bind (object-boxed-size object-total-size)
           (compute-object-size ,object)
         ,@body
         (setq ,object (%pointer-plus ,object object-total-size))))))

(defmacro for-every-pointer-in-object ((object) &body body)
  `(do ((address ,object (%pointer-plus address 1)))
       (( (%pointer-difference address ,object) object-boxed-size))
     (when (%p-pointerp address)
       ,@body)))

(defun describe-object-once-only (address &special *last-object-address*)
  (unless (eq address *last-object-address*)
    (describe-storage address)
    (setq *last-object-address* address)))

;;;

(defun search-region-for-pointer (region pointer)
  (for-every-object-in-region (object region)
    (for-every-pointer-in-object (object)
      (when (= (%p-pointer address) (%pointer pointer))
        (describe-object-once-only object)))))

(defun search-region-for-zero-rank-arrays (region)
  (for-every-object-in-region (object region)
    (when (= (%p-data-type object) dtp-array-header)
      (if (= (%p-ldb %%array-number-dimensions object) 0)
          (describe-storage object)))))

(defun search-region-for-art-32b-arrays (region)
  (for-every-object-in-region (object region)
    (when (= (%p-data-type object) dtp-array-header)
      (if (= (%p-ldb %%array-type-field object) 6)
          (describe-storage object)))))

(defun search-region-for-pointers-to-region (search-region target-region)
  (unless (= search-region target-region)
    (for-every-object-in-region (object search-region)
      (for-every-pointer-in-object (object)
        (when (= (%region-number (%p-pointer address)) target-region)
          (describe-object-once-only object))))))

(defun search-region-for-pointers-to-area (search-region target-area)
  (for-every-object-in-region (object search-region)
    (for-every-pointer-in-object (object)
      (when (= (%area-number (%p-pointer address)) target-area)
        (describe-object-once-only object)))))

(defun search-region-for-illegal-pointers (region)
  (for-every-object-in-region (object region)
    (for-every-pointer-in-object (object)
      (let ((target-region (%region-number (%p-pointer address))))
        (if (integerp target-region)
            (when (> (%pointer-unsigned (%p-pointer address))
                     (+ (%pointer-unsigned (aref #'region-origin target-region))
                        (%region-free-pointer target-region)))
              (format t "~% ~O: ~A ~A ~O" address
                      (nth (%p-cdr-code address) q-cdr-codes)
                      (nth (%p-data-type address) q-data-types)
                      (%p-pointer address)))
          (unless (io-space-pointer? (%p-pointer address))
            (format t "~% ~O: ~A ~A ~O  Not in any region."
                    address
                    (nth (%p-cdr-code address) q-cdr-codes)
                    (nth (%p-data-type address) q-data-types)
                    (%p-pointer address))))))))

(defun search-region-for-pointers-to-old-space (region)
  (unless (old-space-region? region)
    (for-every-object-in-region (object region)
      (for-every-pointer-in-object (object)
        (let ((target-region (%region-number (%p-pointer address))))
          (if (integerp target-region)
              (when (old-space-region? target-region)
                (format t "~% ~O: ~A ~A ~O" address
                        (nth (%p-cdr-code address) q-cdr-codes)
                        (nth (%p-data-type address) q-data-types)
                        (%p-pointer address)))
            (unless (io-space-pointer? (%p-pointer address))
              (format t "~% ~O: ~A ~A ~O  Not in any region."
                      address
                      (nth (%p-cdr-code address) q-cdr-codes)
                      (nth (%p-data-type address) q-data-types)
                      (%p-pointer address)))))))))

;;;

(defun search-area-for-pointer (area pointer)
  (for-every-region-in-area (region area)
    (search-region-for-pointer region pointer)))

(defun search-area-for-pointers-to-region (area target-region)
  (for-every-region-in-area (region area)
    (search-region-for-pointers-to-region region target-region)))

(defun search-area-for-zero-rank-arrays (area)
  (for-every-region-in-area (region area)
    (search-region-for-zero-rank-arrays region)))

(defun search-area-for-art-32b-arrays (area)
  (for-every-region-in-area (region area)
    (search-region-for-art-32b-arrays region)))

(defun search-area-for-pointers-to-area (area target-area)
  (unless (= area target-area)
    (for-every-region-in-area (region area)
      (search-region-for-pointers-to-area region target-area))))

(defun search-area-for-illegal-pointers (area)
  (for-every-region-in-area (region area)
    (search-region-for-illegal-pointers region)))

(defun search-area-for-pointers-to-old-space (area)
  (for-every-region-in-area (region area)
    (search-region-for-pointers-to-old-space region)))

;;;

(defun print-area-message (area)
  (format t "~%Searching area ~S ..." (aref #'area-name area)))

(defun search-everywhere-for-pointer (pointer)
  (for-every-area-in-world (area)
    (print-area-message area)
    (search-area-for-pointer area pointer)))

(defun search-everywhere-for-art-32b-arrays ()
  (for-every-area-in-world (area)
    (print-area-message area)
    (search-area-for-art-32b-arrays area)))

(defun search-everywhere-for-pointers-to-region (region)
  (for-every-area-in-world (area)
    (print-area-message area)
    (search-area-for-pointers-to-region area region)))

(defun search-everywhere-for-pointers-to-area (target-area)
  (for-every-area-in-world (area)
    (print-area-message area)
    (search-area-for-pointers-to-area area target-area)))

(defun search-everywhere-for-illegal-pointers ()
  (for-every-area-in-world (area)
    (print-area-message area)
    (search-area-for-illegal-pointers area)))

(defun search-everywhere-for-pointers-to-old-space ()
  (for-every-area-in-world (area)
    (print-area-message area)
    (search-area-for-pointers-to-old-space area)))

;;;

(defsubst instruction-opcode (instruction)
  (if (< (ldb #o1104 instruction) #o11)
      (ldb #o1105 instruction)
    (ldb #o1104 instruction)))

(defsubst instruction-misc-code (instruction)
  (ldb #o0011 instruction))

(defsubst instruction-destination (instruction)
  (ldb #o1602 instruction))

(defsubst instruction-register (instruction)
  (ldb #o0603 instruction))

(defsubst instruction-offset (instruction)
  (ldb #o0006 instruction))

(defmacro for-every-instruction-in-compiled-function ((instruction fef) &body body)
  `(do ((pc (fef-initial-pc ,fef) (+ pc (fef-instruction-length ,fef pc))))
       (( pc (fef-limit-pc ,fef)))
     (let ((,instruction (fef-instruction ,fef pc)))
       ,@body)))

(defmacro for-every-compiled-function-in-world ((fef) &body body)
  `(for-every-region-in-area (region macro-compiled-program)
     (when (structure-representation-region? region)
       (for-every-object-in-region (object region)
         (when (and (= (%p-data-type object) dtp-header)
                    (= (%p-ldb %%header-type-field object) %header-type-fef))
           (let ((,fef (%make-pointer dtp-fef-pointer object)))
             ,@body))))))

(defun search-for-misc-instruction (misc)
  (if (= (%data-type misc) dtp-symbol) (setq misc (get misc 'compiler:qlval)))
  (check-type misc integer)
  (terpri)
  (for-every-compiled-function-in-world (function)
     (tyo #/.)
    (let ((found 0))
      (for-every-instruction-in-compiled-function (instruction function)
        (when (= (instruction-opcode instruction) 15)
          (when (= (instruction-misc-code instruction) misc)
            (incf found))))
      (unless (zerop found)
        (format t "~%~D found in ~S" found function)))))

(defun search-for-arefi-sub-opcode (subop)
  (terpri)
  (for-every-compiled-function-in-world (function)
    (let ((found 0))
      (for-every-instruction-in-compiled-function (instruction function)
        (when (= (instruction-opcode instruction) 20)
          (when (= (instruction-register instruction) subop)
            (incf found))))
      (unless (zerop found)
        (format t "~%~D found in ~S" found function)))))

(defun search-for-fef3-instructions ()
  (terpri)
  (for-every-compiled-function-in-world (function)
     (tyo #/.)
    (let ((found 0))
      (for-every-instruction-in-compiled-function (instruction function)
        (when ( (instruction-opcode instruction) 13)
          (if (= (instruction-register instruction) 3)
              (incf found))))
      (unless (zerop found)
        (format t "~%~D found in ~S" found function)))))

(defun search-for-fef2-instructions ()
  (terpri)
  (for-every-compiled-function-in-world (function)
     (tyo #/.)
    (let ((found 0))
      (for-every-instruction-in-compiled-function (instruction function)
        (when ( (instruction-opcode instruction) 13)
          (if (= (instruction-register instruction) 2)
              (incf found))))
      (unless (zerop found)
        (format t "~%~D found in ~S" found function)))))

(defun search-for-long-branches ()
  (terpri)
  (for-every-compiled-function-in-world (function)
    (tyo #/.)
    (let ((found 0))
      (for-every-instruction-in-compiled-function (instruction function)
        (when (> (fef-instruction-length function pc) 1)
          (incf found)))
      (unless (zerop found)
        (format t "~%~D found in ~S" found function)))))


(defun record-fef-header-block-sizes ()
  (let ((fef-0 0) (fef-1 0) (fef-2 0) (fef-3 0) (fail 0))
    (terpri)
    (for-every-compiled-function-in-world (function)
      (tyo #/.)
      (let ((size (// (fef-initial-pc function) 2)))
        (cond ((< size 100) (incf fef-0))
              ((< size 200) (incf fef-1))
              ((< size 300) (incf fef-2))
              ((< size 400) (incf fef-3))
              (t (incf fail)))))
    (values fef-0 fef-1 fef-2 fef-3 fail)))

(defun search-for-functions-without-debugging-info ()
  (terpri)
  (for-every-compiled-function-in-world (function)
    (tyo #/.)
    (unless (ldb-test %%fefhi-ms-debug-info-present (%p-contents-offset function %fefhi-misc))
      (format t "~%~S does not contain debugging info" (function-name function)))))

(defun search-for-calls-to-functions-with-quoted-arguments (&aux result)
  (format t "~&")
  (for-every-compiled-function-in-world (function)
    object-boxed-size
    (dotimes (i (%structure-boxed-size function))
      (let* ((address (%make-pointer-offset dtp-locative function i))
             (called-function
               (do ((current-address address))
                    ((not (= (%p-data-type current-address) dtp-external-value-cell-pointer))
                     (if (and (= (%p-data-type current-address) dtp-header)
                              (= (%p-ldb %%header-type-field current-address) header-type-fef))
                         (%make-pointer dtp-fef-pointer current-address)
                       nil))
                 (setq current-address (%p-pointer current-address)))))
        (cond ((null called-function))
              ((or (not (zerop (logand (%args-info called-function) %arg-desc-quoted-rest)))
                   (not (zerop (logand (%args-info called-function) %arg-desc-fef-quote-hair))))
               (pushnew function result)
               (print function)))))))
