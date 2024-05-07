;
; pipe-count.scm -- Hack: word-pair counting via Atomese pipe.
;
; Quick hack, based on the `count-agent.scm` from the `agents` git repo.
; See `word-pair-count.scm` for a general overview of the idea.
;
; The stuff here is a hack because:
; 1) It bypasses the matrix API completely, and is not API-compatible
;    with that general API.
; 2) Despite #1, it is de facto functionally compatible with current
;    usage. The only exported routine, `make-block-pipe-observer`
;    is functionally compatible with `make-block-pair-observer`
;    (defined in `word-pair-count.scm`)
;
; It seems to actually work, and runs 3x faster than the older code.
; So this version will now be the default version for pair-counting.
;
; The default is set in:
;    run-config/2-pair-conf.sh:export OBSERVE="observe-block-pairs"
; and
;    run-common/cogserver-pair.scm:(define (observe-block-pairs TXT)
;
; TODO:
; * Need ((add-count-api LLOBJ) 'count-key) to replace hard-coded count
;   But this is not urgent, because the count-api itself is hard coded.

(use-modules (opencog) (opencog exec) (opencog persist))
(use-modules (opencog nlp) (opencog nlp lg-parse))
(use-modules (opencog matrix))
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
(define (make-parser txt-stream STORAGE)
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
	(define NUML (Number 6))
	(define DICT (LgDict "any"))
	(define any-parse (ParseNode "ANY"))
	(define any-sent (SentenceNode "ANY"))

	; Compatible with opencog/matrix/count-api.scm
	; Due to ancient history, we increment the third location.
	(define COUNT-PRED (PredicateNode "*-TruthValueKey-*"))
	(define COUNT-ZERO (Number 0 0 0))
	(define COUNT-ONE (Number 0 0 1))

	; XXX Hack to fetch sentence count from storage. XXX we should not
	; do it this way, and use a cleaner design but I'm in a hurry so....
	(cog-execute! (FetchValueOf any-sent COUNT-PRED STORAGE
		(FloatValueOf COUNT-ZERO)))

	; Increment the count on one atom.
	; If the count is not available, it is fetched from storage.
	; If there is no count in storage, it is set to zero.
	(define (incr-cnt atom)
		(SetValue atom COUNT-PRED
			(Plus COUNT-ONE
				(FloatValueOf atom COUNT-PRED
					(FetchValueOf atom COUNT-PRED STORAGE
						(FloatValueOf COUNT-ZERO))))))

	(define (store-cnt atom)
		(StoreValueOf atom COUNT-PRED STORAGE))

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
				(incr-cnt (Variable "$atom"))
				(store-cnt (Variable "$atom"))
			)
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
				; Apply the function FUNKY to the word and edge lists.
				(FUNKY (Variable "$word-list"))
				(FUNKY (Variable "$edge-list"))
				; Increment by one for each parse
				(incr-cnt any-parse)
				(store-cnt any-parse))
			PASRC))

	(define parser (LgParseBonds txt-stream DICT NUML))

	; Return the assembled counting pipeline.
	; All that the user needs to do is to call `cog-execute!` on it,
	; until end of file is reached.
	(stream-splitter parser atom-counter)
)

; --------------------------------------------------------------
; If the current cog-storage-node never changes, then the parser only
; needs to be created only once. In the long term, there is a reasonable
; expectation that maybe this should work with multiple different storage
; nodes, maybe even a different one in each thread? This futre remains
; uncertain, so for now, assume only one global. FIXME someday, if
; needed.
(define pipe-parser #f)
(define (make-pipe-parser)
	(if (not pipe-parser)
		(begin
			(set! pipe-parser
				(make-parser
					(ValueOf (Anchor "parse pipe") (Predicate "text src"))
					(cog-storage-node)))))
	pipe-parser
)

; Parse one line of text. The text string is assumed to be a scheme
; string
(define (obs-one-text-string TXT-STRING)

	(cog-set-value! (Anchor "parse pipe") (Predicate "text src")
		(StringValue TXT-STRING))

	; Run parser once.
	(cog-execute! (make-pipe-parser))

	; Increment sentence count. Not handled in pipeline above.
	(define any-sent (SentenceNode "ANY"))
	(count-one-atom any-sent)
)

; Example usage:
#|
(use-modules (opencog learn))
(use-modules (opencog persist))
(use-modules (opencog persist-rocks))
(load "../common.scm")
(load "pipe-count.scm")
(define rsn (RocksStorageNode "rocks:///tmp/foo"))
(cog-open rsn)
(obs-one-text-string "this is a test")
(cog-report-counts)
(cog-get-atoms 'AnyNode)
(cog-get-atoms 'WordNode)
(define CNT (PredicateNode "*-TruthValueKey-*"))
(cog-execute! (ValueOf (SentenceNode "ANY") CNT))
(cog-execute! (ValueOf (ParseNode "ANY") CNT))
(cog-execute! (ValueOf (WordNode "is") CNT))
(cog-execute! (ValueOf (Edge (Bond "ANY") (List (Word "is") (Word "a"))) CNT))
(cog-close rsn)
; ...
(load-atomspace)
|#


; --------------------------------------------------------------------

; Temp hack for temp hacking
(define-public (make-block-pipe-observer)
"
   make-block-pipe-observer -- Make an observer for counting pairs in
   text blocks. Returns a function of the following form:

   func TEXT-BLOCK
      Impose a sliding window on the TEXT-BLOCK, and then submit
      everything in that window for word-pair counting.

   TEXT-BLOCK is a utf8 string of text. A sliding window, of the default
   width of 9 words, is created on that block. Everything within the
   window is sent to the LG 'any' random-planar-tree parser. The word
   pairs in the random tree are then counted. Counts are stored.
"
	(define ala (make-any-link-api))
	(define alc (add-count-api ala))
	(define als (add-storage-count alc))

	(make-observe-block als obs-one-text-string #:WIN-SIZE 9)
)

; ---------------------------------------------------------------------
; ---------------------------------------------------------------------
