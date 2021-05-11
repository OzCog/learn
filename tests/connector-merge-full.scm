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
(use-modules (srfi srfi-64))

(opencog-test-runner)

(load "connector-setup.scm")
(load "connector-data.scm")

; ---------------------------------------------------------------
;
; This is similar to the "simple start-cluster merge test" except
; that the word "e" appears both as germ, and in two connectors.
;
; This diagram explains what is being tested here:
;
; From basic section merge:
;    (e, abc) + (j, abc) -> ({ej}, abc)
;    (e, dgh) + (j, dgh) -> ({ej}, dgh)
;    (e, klm) +  none    -> p * ({ej}, klm) + (1-p) * (e, klm)
;     none    + (j, abe) -> p * ({ej}, abe) + (1-p) * (j, abe)
;     none    + (j, egh) -> p * ({ej}, egh) + (1-p) * (j, egh)
;
; However, the last two are not the final form. From the cross-section
; merge, one has
;    [e, <j, abv>] + none -> p * [{ej}, <j, abv>] + (1-p) * [e, <j, abv>]
;    [e, <j, vgh>] + none -> p * [{ej}, <j, vgh>] + (1-p) * [e, <j, vgh>]
;
; which reshapes into
;     p * (j, ab{ej}) + (1-p) * (j, abe)
;     p * (j, {ej}gh) + (1-p) * (j, egh)
;
; The two reshapes are merged, to yeild as the final form
;     p * ({ej}, ab{ej}) + (1-p) * (j, abe)
;     p * ({ej}, {ej}gh) + (1-p) * (j, egh)
;
; The cross-sections on e should be:
;     (1-p) * [e, <j, abv>]
;     (1-p) * [e, <j, vgh>]
; and nothing more. The motivation for this is described in the diary
; entry "April-May 20201 ...Non-Commutivity, Again... Case B".
;
; In this diagram, (e,abc) is abbreviated notation for
; (Section (Word e) (ConnectorList (Connector a) (Connector b) (Connector c)))
; and so on.
; {ej} is short for (WordClassNode "e j") (a set of two words)
; "p" is the fraction to merge == 0.25, hard-coded below.
;

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

(define (filter-type wrd atype)
	(filter
		(lambda (atom) (equal? (cog-type atom) atype))
		(gsc 'right-stars wrd)))

(define (len-type wrd atype)
	(length (filter-type wrd atype)))

; Expect 3 Sections and two CrossSections on e.
(test-equal 5 (length (gsc 'right-stars (Word "e"))))
(test-equal 4 (length (gsc 'right-stars (Word "j"))))

(test-equal 3 (len-type (Word "e") 'Section))
(test-equal 2 (len-type (Word "e") 'CrossSection))
(test-equal 4 (len-type (Word "j") 'Section))
(test-equal 0 (len-type (Word "j") 'CrossSection))

; We expect a total of 3+4=7 Sections
(test-equal 7 (length (cog-get-atoms 'Section)))

; Merge two sections together.
(define frac 0.25)
(define disc (make-fuzz gsc 0 frac 4 0))
(disc 'merge-function (Word "e") (Word "j"))

; We expect one section left on "e", the klm section, and two
; cross-sections. The two cross-sections should correspond
; to the sections (1-p) * (j, abe) and (1-p) * (j, egh)
; that is, to the "orthogonal"  word-sense.
(test-equal 1 (len-type (Word "e") 'Section))
#! =====================
(test-equal 2 (len-type (Word "e") 'CrossSection))
(test-equal 3 (length (gsc 'right-stars (Word "e"))))
============ !#

; We expect two sections remaining on j
(test-equal 2 (len-type (Word "j") 'Section))
(test-equal 0 (len-type (Word "j") 'CrossSection))
(test-equal 2 (length (gsc 'right-stars (Word "j"))))

#! =====================
; We expect three merged sections
(test-equal 3 (length (gsc 'right-stars (WordClassNode "e j"))))

; Of the 5 original Sections, 4 are deleted, and 3 are created,
; leaving a grand total of 4. The 3 new ones are all e-j, the
; remaining old one is an "e" with a reduced count.  This is just
; the sum of the above.
(test-equal 4 (length (cog-get-atoms 'Section)))
============ !#

; Validate counts.
(define epsilon 1.0e-8)
(test-approximate (* cnt-e-klm (- 1.0 frac))
	(cog-count (car (filter-type (Word "e") 'Section))) epsilon)

; TODO: validate counts on the other Sections...

#! =====================
; Of the 15 original CrossSections, 12 are deleted outright, and three
; get thier counts reduced (the e-klm crosses). A total of 3x3=9 new
; crosses get created, leaving a grand-total of 12.
(test-equal 12 (length (cog-get-atoms 'CrossSection)))
============ !#

; Validate counts on the CrossSections...
(expected-j-extra-sections)
(test-approximate (* (- 1 frac) cnt-j-abe) (cog-count sec-j-abe) epsilon)
(test-approximate (* (- 1 frac) cnt-j-egh) (cog-count sec-j-egh) epsilon)

(test-end t-start-cluster)

; ---------------------------------------------------------------
