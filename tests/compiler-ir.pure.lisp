;;;; This software is part of the SBCL system. See the README file for
;;;; more information.
;;;;
;;;; While most of SBCL is derived from the CMU CL system, the test
;;;; files (like this one) were written from scratch after the fork
;;;; from CMU CL.
;;;;
;;;; This software is in the public domain and is provided with
;;;; absolutely no warranty. See the COPYING and CREDITS files for
;;;; more information.

(enable-test-parallelism)

(import '(sb-c::combination-fun-debug-name
          sb-c::combination-fun-source-name
          sb-c::*compile-component-hook*
          sb-c::basic-combination-p
          sb-c::combination-p
          sb-c::basic-combination-info
          sb-c::node-tail-p
          sb-c::do-blocks
          sb-c::do-nodes
          sb-c::%check-bound
          sb-kernel:%bit-pos-fwd/1))

(defun inspect-ir (form fun &rest checked-compile-args)
  (let ((*compile-component-hook* fun))
    (apply #'test-util:checked-compile form checked-compile-args)))

(defun ir-full-calls (form)
  (let (calls)
    (inspect-ir
     form
     (lambda (component)
       (do-blocks (block component)
         (do-nodes (node nil block)
           (when (and (basic-combination-p node)
                      (eq (basic-combination-info node) :full))
             (push node calls))))))
    calls))

(defun ir-calls (form)
  (let (calls)
    (inspect-ir
     form
     (lambda (component)
       (do-blocks (block component)
         (do-nodes (node nil block)
           (when (basic-combination-p node)
             (push node calls))))))
    calls))

(test-util:with-test (:name :%bit-pos-fwd/1-tail-called)
  (destructuring-bind (combination)
      (ir-full-calls `(lambda (x)
                        (declare (optimize (debug 2)))
                        (position 1 (the simple-bit-vector x))))
    (assert (eql (combination-fun-debug-name combination) '%bit-pos-fwd/1))
    (assert (node-tail-p combination))))

(test-util:with-test (:name :bounds-check-constants)
  (assert (= (count '%check-bound
                    (ir-calls
                     `(lambda (v)
                        (declare (simple-vector v))
                        (setf (aref v 0) (aref v 1))))
                    :key (lambda (x) (combination-fun-source-name x nil)))
             1)))

(test-util:with-test (:name :local-call-tail-call)
  (destructuring-bind (combination)
      (ir-full-calls `(lambda ()
                        (flet ((x ()
                                 (terpri)))
                          (declare (notinline x))
                          (x)
                          10)))
    (assert (eql (combination-fun-debug-name combination) 'terpri))
    (assert (node-tail-p combination))))

(test-util:with-test (:name :fold-derived-logand)
  (assert (not (find 'logand
                     (ir-calls `(lambda (x)
                                  (declare ((integer 1 4) x))
                                  (logand #xF00 x)))
                     :key #'combination-fun-debug-name)))
  (assert (not (find 'logand
                     (ir-calls `(lambda (x)
                                  (declare ((integer 1 4) x))
                                  (logand #xFF (1+ x))))
                     :key #'combination-fun-debug-name)))
  (assert (not (find 'logand
                     (ir-calls `(lambda (x)
                                  (declare ((integer 1 4) x))
                                  (logand #xFF (ash 1 x))))
                     :key #'combination-fun-debug-name))))

(test-util:with-test (:name :mod-ash
                      :skipped-on (not (or :arm64 :x86-64)))
  (assert (not (ir-full-calls `(lambda (x y)
                                 (declare (fixnum x y))
                                 (logand #xFF (ash x y)))))))

(test-util:with-test (:name :exit-reoptimize-uses)
  (assert (not (find 'cdr
                     (ir-calls `(lambda (a b)
                                  (/ (unwind-protect (if a
                                                         (values b (cdr a))
                                                         (values 1 0))
                                       a)
                                     1)))
                     :key (lambda (x)
                            (and (combination-p x)
                                 (combination-fun-debug-name x)))))))
