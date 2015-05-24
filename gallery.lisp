#|
This file is a part of halftone
(c) 2015 Shirakumo http://tymoon.eu (shinmera@tymoon.eu)
Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(in-package #:org.shirakumo.halftone)
(in-readtable :qtools)

(define-widget thumbnail (QWidget)
  ((file :initarg :file :accessor file)
   (selected :initarg :selected :accessor selected))
  (:default-initargs
    :file (error "FILE required.")
    :selected NIL))

(define-signal (thumbnail do-update) ())

(defmethod (setf selected) :after (val (thumbnail thumbnail))
  (signal! thumbnail (do-update)))

(define-initializer (thumbnail setup)
  (setf (q+:fixed-size thumbnail) (values 128 128))
  (connect! thumbnail (do-update) thumbnail (update)))

(define-subwidget (thumbnail image) NIL
  (with-callback-task result ('thumbnail-loader-task :file file)
    (setf image result)
    (signal! thumbnail (do-update))))

(define-override (thumbnail paint-event) (ev)
  (declare (ignore ev))
  (with-finalizing ((painter (q+:make-qpainter thumbnail)))
    (let ((brush (if selected
                     (q+:highlight (q+:palette thumbnail))
                     (q+:window (q+:palette thumbnail)))))
      (q+:fill-rect painter (q+:rect thumbnail) brush))
    (when image
      (let ((target (q+:rect thumbnail)))
        (q+:adjust target 5 5 -5 -5)
        (q+:draw-image painter target image (q+:rect image))))))

(define-override (thumbnail mouse-release-event) (ev)
  (setf (image *main*) file)
  (stop-overriding))

(define-widget gallery (QScrollArea)
  ((location :initarg :location :accessor location)
   (thumbnails :accessor thumbnails)
   (current :initform -1 :accessor current))
  (:default-initargs :location (user-homedir-pathname)))

(defmethod (setf location) :after (pathname (gallery gallery))
  (reload-images gallery))

(defmethod (setf current) :around (num (gallery gallery))
  (with-slots-bound (gallery gallery)
    (when (and (/= current num)
               (< -1 num (length thumbnails)))
      (when (/= current -1)
        (setf (selected (elt thumbnails current)) NIL))
      (call-next-method)
      (setf (selected (elt thumbnails current)) T)
      (setf (image *main*) (file (elt thumbnails current))))))

(defmethod (setf image) ((file pathname) (gallery gallery))
  (loop for i from 0
        for widget across (slot-value gallery 'thumbnails)
        do (when (equalp file (file widget))
             (setf (current gallery) i))))

(define-subwidget (gallery scrollable) (q+:make-qwidget))

(define-subwidget (gallery layout) (q+:make-qhboxlayout scrollable)
  (setf (q+:margin layout) 0)
  (setf (q+:spacing layout) 0))

(define-override (gallery key-release-event) (ev)
  (when (= (q+:key ev) (q+:qt.key_d))
    (setf (current gallery) (1+ (current gallery))))
  (when (= (q+:key ev) (q+:qt.key_a))
    (setf (current gallery) (1- (current gallery)))))

(define-initializer (gallery setup)
  (setf (q+:background-role gallery) (q+:qpalette.background))
  (setf (q+:vertical-scroll-bar-policy gallery) (q+:qt.scroll-bar-always-off))
  (setf (q+:widget-resizable gallery) NIL)
  (setf (q+:widget gallery) scrollable))

(define-finalizer (gallery teardown)
  (do-layout (widget layout)
    (finalize widget)))

(defun sort-files (files by &optional descending)
  (macrolet ((sorter (comp key)
               `(lambda (a b) (let ((result (,comp (,key a) (,key b))))
                                (if descending (not result) result)))))
    (sort files (ecase by
                  (:name (sorter string< pathname-name))
                  (:time (sorter uiop:stamp< uiop:safe-file-write-date))))))

(defun directory-images (dir)
  (remove-if-not #'image-file-p (uiop:directory-files dir)))

(defun reload-images (gallery)
  (let ((files (sort-files (directory-images (location gallery)) :time T)))
    (with-slots-bound (gallery gallery)
      (clear-layout layout)
      (setf (thumbnails gallery) (make-array 0 :adjustable T :fill-pointer 0))
      (dolist (file files)
        (let ((thumb (make-instance 'thumbnail :file file)))
          (vector-push-extend thumb (thumbnails gallery))
          (q+:add-widget layout thumb)))
      (setf (q+:fixed-size scrollable) (values (* 128 (length (thumbnails gallery))) 128))
      (setf (image *main*) (first files)))))
