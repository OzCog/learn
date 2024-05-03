;
; pipe-count.scm -- Hack: word-pair counting via Atomese pipe.
;
; Quick hack, based on the `count-agent.scm` from the `agents` git repo.
; This is a hack because:
; 1) It bypasses the matrix API completely, and thus is unreliable in
;    the backwards-compat to what that does.
; 2) It is intened as a quick hack to evaluate performance.
; 3) Despite #1, I think i'ts compatible. Trying to be.

(use-modules (opencog) (opencog exec) (opencog persist))
(use-modules (opencog nlp) (opencog nlp lg-parse))
(use-modules (opencog sensory))
(use-modules (srfi srfi-1))

; --------------------------------------------------------------
; Return a text parser that counts words and word-pairs obtained from
; parsing text on a stream. The `txt-stream` must be an Atom that can
; serve as a source of text. Typically, `txt-stream` will be
;    (ValueOf (Concept "some atom") (Predicate "some key"))
; and the Value there will be a LinkStream from some file or
; other text source.
;
; These sets up a processing pipeline in Atomese, and returns that
; pipeline. The actual parsing all happens in C++ code, not in scheme
; code. The scheme here is just to glue the pipeline together.
(define (make-parser txt-stream)
	;
	; Pipeline steps, from inside to out:
	; * LGParseBonds tokenizes a sentence, and then parses it.
	; * The PureExecLink makes sure that the parsing is done in a
	;   sub-AtomSpace so that the main AtomSpace is not garbaged up.
	;
	; The result of parsing is a list of pairs. First item in a pair is
	; the list of words in the sentence; the second is a list of the edges.
	; Thus, each pair has the form
	;     (LinkValue
	;         (LinkValue (Word "this") (Word "is") (Word "a") (Word "test"))
	;         (LinkValue (Edge ...) (Edge ...) ...))
	;
	; The outer Filter matches this, so that (Glob "$edge-list") is
	; set to the LinkValue of Edges.
	;
	; The inner Filter loops over the list of edges, and invokes a small
	; pipe to increment the count on each edge.
	;
	; The counter is a non-atomic pipe of (SetValue (Plus 1 (GetValue)))
	;
	(define NUML (Number 4))
	(define DICT (LgDict "any"))

	; Increment the count on one atom.
	(define (incr-cnt atom)
		(SetValue atom (Predicate "count")
			(Plus (Number 0 0 1)
				(FloatValueOf atom (Predicate "count")
					(FloatValueOf (Number 0 0 0))))))

	; Given a list (an Atomese LinkValue list) of Atoms,
	; increment the count on each Atom.
	(define (atom-counter ATOM-LIST)
		(Filter
			(Rule
				; We could type for safety, but seems like no need...
				; (TypedVariable (Variable "$atom")
				;       (TypeChoice (Type 'Edge) (Type 'Word)))
				(Variable "$atom") ; vardecl
				(Variable "$atom") ; body to match
				(incr-cnt (Variable "$atom")))
			ATOM-LIST))

	; Given PASRC holding a stream of parses, split it into a list of
	; words, and a list of edges, and apply FUNKY to both lists.
	(define (stream-splitter PASRC FUNKY)
		(Filter
			(Rule
				(LinkSignature
					(Type 'LinkValue)
					(Variable "$word-list")
					(Variable "$edge-list"))
				; Apply the function FUNKY to the edge-list
				(FUNKY (Variable "$word-list"))
				(FUNKY (Variable "$edge-list")))
			PASRC))

	(define parser (LgParseBonds txt-stream DICT NUML))

	; Is there any benefit to private parsing?
	; (edge-filter (PureExecLink parser) edge-counter)

	; Return the assembled counting pipeline.
	; All that the user needs to do is to call `cog-execute!` on it,
	; until end of file is reached.
	(stream-splitter parser atom-counter)
)

; --------------------------------------------------------------
; Demo wrapper: Parse one line of text.
(define (obs-texty TXT-STRING)

	; We don't need to create this over and over; once is enough.
	(define txt-stream
		(ValueOf (Anchor "parse pipe") (Predicate "text src")))
	(define parser (make-parser txt-stream))

	(define phrali (Item TXT-STRING))

	(cog-execute!
		(SetValue (Anchor "parse pipe") (Predicate "text src") phrali))

	; Run parser once.
	(cog-execute! parser)
	(cog-extract-recursive! phrali)
)

; --------------------------
; Run the above demo:
; (obs-file "/tmp/demo.txt")
;
; Look at results. Poke around, look at counts.
; (cog-report-counts)
; (cog-execute! (ValueOf (Word "is") (Predicate "count")))
; (cog-execute! (ValueOf
;     (Edge (Bond "ANY") (List (Word "is") (Word "a")))
;     (Predicate "count")))
;
; Erase all words, so we can try again.
; (extract-type 'WordNode)

; --------------------------
