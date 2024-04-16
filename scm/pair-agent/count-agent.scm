
(use-modules (opencog) (opencog exec) (opencog persist))
(use-modules (opencog nlp) (opencog nlp lg-parse))
(use-modules (opencog sensory))
(use-modules (srfi srfi-1))

; Here's the design we want:
; 1) Some source of text strings; actually a source of PhraseNode's
;    This source blocks if there's nothing to be read; else it
;    returns the next PhraseNode. The SRFI's call this a generator.
;    For now, see `sensory.scm` module and example.
; 2) (Optional) Some way to split one source into multiple sources.
;    Maybe this:
;    https://wiki.opencog.org/w/PromiseLink#Multiplex_Example
;    but what happens if the readers don't both read ???
; 3) A Filter that takes above and increments pair counts.
; 4) Execution control. There are two choices:
;    Pull: infinite loop polls on promise. Source blocks if
;          no input.
;    Push: Nothing happens until source triggers; then a cascade
;          of effects downstream.
;    Right now, the general infrastructure supports Pull naturally.
;    There aren't any push demos.
;    Attention control is easier with Pull.


(define text-blob "this is just a bunch of words you know")


; Return a text parser that counts edges on a stream. The
; `txt-stream` must be an Atom that can serve as a source of text.
; Typically, `txt-stream` will be
;    (ValueOf (Concept "some atom") (Predicate "some key"))
; and the Value there will be a LinkStream from some file or
; other text source.
(define (make-parser txt-stream)
	; From inside to out:
	; LGParseBonds tokenizes a sentence, and then parses it.
	; The PureExecLink makes sure that the parsing is done in a sub-AtomSpace
	; so that the main AtomSpace is not garbaged up.
	;
	; The result of parsing is a list of pairs. First item in a pair is
	; the list of words in the sentence; the second is a list of the edges.
	; Thus, each pair has the form
	;     (LinkValue
	;         (LinkValue (Word "this") (Word "is") (Word "a") (Word "test"))
	;         (LinkValue (Edge ...) (Edge ...) ...))
	;
	; The Filter matches this, so that (Variable "$x") is equated with the
	; list of Edges.
	;
	(define NUML (Number 4))
	(define DICT (LgDict "any"))

	; Increment the count on one edge.
	(define (incr-cnt edge)
		(SetValue edge (Predicate "count")
			(Plus (Number 0 0 1)
				(FloatValueOf edge (Predicate "count") (FloatValueOf (Number 0 0 0))))))

	; Given a list (an Atomese LinkValue list) of parse results,
	; extract the edges and increment the count on them.
	(define (count-edges parsed-stuff)
		(Filter
			(Rule
				; (Variable "$edge")
				(TypedVariable (Variable "$edge") (Type 'Edge))
				(Variable "$edge")
				(incr-cnt (Variable "$edge")))
			parsed-stuff))

	; Parse text in a private space.
	(define (parseli phrali)
		(PureExecLink (LgParseBonds phrali DICT NUML)))

	; Given an Atom `phrali` hold text to be parsed, get that text,
	; parse it, and increment the counts on the edges.
	(define (filty phrali)
		(Filter
			(Rule
				; Type decl
				(Glob "$x")
				; Match clause - one per parse.
				(LinkSignature
					(Type 'LinkValue) ; the wrapper for the pair
					(Type 'LinkValue) ; the word-list
					(LinkSignature    ; the edge-list
						(Type 'LinkValue)  ; edge-list wrapper
						(Glob "$x")))      ; all of the edges
				; Rewrite
				(count-edges (Glob "$x"))
			)
			(parseli phrali)))

	; Return the parser.
	(filty txt-stream)
)

; Parse a string.
(define (obs-txt PLAIN-TEXT)
	(define txt-stream (ValueOf (Concept "foo") (Predicate "some place")))
	(define parser (make-parser txt-stream))

	(define phrali (Phrase PLAIN-TEXT))
	(cog-set-value! (Concept "foo") (Predicate "some place") phrali)

	(cog-execute! parser)

	; Remove the phrase-link, return the list of edges.
	(cog-extract-recursive! phrali)
)

; Parse contents of a file.
(define (obs-file FILE-NAME)
	(define txt-stream (ValueOf (Concept "foo") (Predicate "some place")))
	(define parser (make-parser txt-stream))

	(define phrali (FileRead (string-append "file://" FILE-NAME)))

	; This will do the trick to set the value. Except it creates an Atom
	; (cog-execute!
	;    (SetValue (Concept "foo") (Predicate "some place")
	;       (FileRead "file:///tmp/demo.txt")))
	; Same as bove, without creating Atom.
	(cog-set-value! (Concept "foo") (Predicate "some place")
		(cog-execute! phrali))

	; Parse only first line of file:
	; (cog-execute! parser)

	; Loop over all lines.
	(define (looper) (cog-execute! parser) (looper))

	; At end of file, exception will be thrown. Catch it.
	(catch #t looper
		(lambda (key . args) (format #t "The end ~A\n" key)))

	(cog-extract-recursive! phrali)
)

; --------------------------
; Issues.
; Parses arrive as LinkValues. We want to apply a function to each.
; How? Need:
; 4) IncrementLink just like cog-inc-value!
;    or is it enough to do atomic lock?
;    Make SetValue exec under lock. ... easier said than done.
;    risks deadlock.
;
; cog-update-value calls
; asp->increment_count(h, key, fvp->value()));

; Below works but is a non-atomic increment.
(define ed (Edge (Bond "ANY") (List (Word "words") (Word "know"))))
(define (doinc)
	(cog-execute!
		(SetValue ed (Predicate "count")
			(Plus (Number 0 0 1)
				(FloatValueOf ed (Predicate "count") (Number 0 0 0))))))

; Lets work on file-access now.
(cog-execute!
   (SetValue (Concept "foo") (Predicate "some place")
      (FileRead "file:///tmp/demo.txt")))

; Wait ...
(define txt-stream-gen
	(ValueOf (Concept "foo") (Predicate "some place")))

; (cog-execute! (LgParseBonds txt-stream-gen DICT NUML))

; (load "count-agent.scm")
; (obs-txt text-blob)
; (obs-file "/tmp/demo.txt")
; (cog-report-counts)
; (cog-get-atoms 'WordNode)
