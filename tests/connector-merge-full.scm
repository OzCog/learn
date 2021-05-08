;
; connector-merge-full.scm
; Unit test for merging of Connectors - full case.
;
; Tests merging of several words into a single word-class.
; The focus here is to make sure that that when the words to
; be merged also appear in Connectors, that those are merged
; correctly, too. This triggers some extra merge logic, beyond
; the basic case.
;
; Created May 2021

(use-modules (opencog) (opencog matrix))
(use-modules (opencog nlp))
(use-modules (opencog nlp learn))

(use-modules (opencog test-runner))

(opencog-test-runner)

(load "connector-setup.scm")
(load "connector-data.scm")

; ---------------------------------------------------------------
(define t-start-cluster "full start-cluster merge test")
(test-begin t-start-cluster)

; Open the database
(setup-database)

; Load some data
(setup-e-j-sections)
(setup-j-extra)

; Define matrix API to the data
(define pca (make-pseudo-cset-api))
(define csc (add-covering-sections pca))
(define gsc (add-cluster-gram csc))

; Verify that the data loaded correctly
; We expect 3 sections on "e" and four on "j"
(test-equal 3 (length (gsc 'right-stars (Word "e"))))
(test-equal 4 (length (gsc 'right-stars (Word "j"))))

; Create CrossSections and verify that they got created
; We expect 3 x (3+4) = 21 of them.
(csc 'explode-sections)
(test-equal 21 (length (cog-get-atoms 'CrossSection)))

; Verify that direct-sum object is accessing shapes correctly
; i.e. the 'explode should have created some CrossSections
(test-equal 3 (length (gsc 'right-stars (Word "g"))))
(test-equal 3 (length (gsc 'right-stars (Word "h"))))

; Expect 3 Sections and two CrossSections on e.
(test-equal 5 (length (gsc 'right-stars (Word "e"))))
(test-equal 4 (length (gsc 'right-stars (Word "j"))))
(test-equal 3 (length (filter
	(lambda (atom) (equal? (cog-type atom) 'Section))
		(gsc 'right-stars (Word "e")))))
(test-equal 2 (length (filter
	(lambda (atom) (equal? (cog-type atom) 'CrossSection))
		(gsc 'right-stars (Word "e")))))
(test-equal 4 (length (filter
	(lambda (atom) (equal? (cog-type atom) 'Section))
		(gsc 'right-stars (Word "j")))))
(test-equal 0 (length (filter
	(lambda (atom) (equal? (cog-type atom) 'CrossSection))
		(gsc 'right-stars (Word "j")))))

; We expect a total of 3+4=7 Sections
(test-equal 7 (length (cog-get-atoms 'Section)))

; Merge two sections together.
(define disc (make-discrim gsc 0.25 4 4))
(disc 'merge-function (Word "e") (Word "j"))

#! =====================
; We expect just one section left on "e", the klm section.
(test-equal 1 (length (gsc 'right-stars (Word "e"))))

; We expect no sections left on j
(test-equal 0 (length (gsc 'right-stars (Word "j"))))

; We expect three merged sections
(test-equal 3 (length (gsc 'right-stars (WordClassNode "e j"))))

; Of the 5 original Sections, 4 are deleted, and 3 are created,
; leaving a grand total of 4. The 3 new ones are all e-j, the
; remaining old one is an "e" with a reduced count.  This is just
; the sum of the above.
(test-equal 4 (length (cog-get-atoms 'Section)))

; Validate counts.
(define angl 0.35718064330452926) ; magic value from make-discrim
(test-approximate (* cnt-e-klm (- 1.0 angl))
	(cog-count (car (gsc 'right-stars (Word "e")))) 0.001)

; TODO: validate counts on the other Sections...

; Of the 15 original CrossSections, 12 are deleted outright, and three
; get thier counts reduced (the e-klm crosses). A total of 3x3=9 new
; crosses get created, leaving a grand-total of 12.
(test-equal 12 (length (cog-get-atoms 'CrossSection)))

; TODO: validate counts on the CrossSections...
============!#

(test-end t-start-cluster)

; ---------------------------------------------------------------
