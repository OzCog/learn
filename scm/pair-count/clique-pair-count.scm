;
; clique-pair-count.scm
;
; Word-pair counting by counting all possible pairings (the "clique")
; inside a window. The window slides along (sliding window).
;
; Copyright (c) 2013, 2017 Linas Vepstas <linasvepstas@gmail.com>
;
; Word-pairs show up, and can be counted in several different ways. One
; method  is a windowed clique-counter. If two words appear within a
; fixed distance from each other (the window size), the corresponding
; word-pair count is incremented. This is a clique-count, because every
; possible pairing is considered. This count is stored in the CountTV
; for the EvaluationLink on (PredicateNode "*-Sentence Word Pair-*").
; A second count is maintained for this same pair, but including the
; distance between the two words. This is kept on a link identified by
; (SchemaNode "*-Pair Distance-*"). Please note that the pair-distance
; counter can lead to very large atomspaces, because for window widths
; of N, a given word-pair might be observed with every possible
; distance between them, i.e. up to N times.
;
; XXX FIXME we should probably not store this way. We should probably
; have just one word-pair, and hold the counts in different values,
; instead. This needs a code redesign. XXX
;
(use-modules (opencog) (opencog nlp) (opencog persist))
(use-modules (opencog exec))
(use-modules (srfi srfi-1))

; ---------------------------------------------------------------------
; update-clique-pair-counts -- count occurrences of random word-pairs.
;
; This generates what are termed "clique pairs" throughout: these are
; all possible word-pair combinations, given a sequence of words.
; No parsing is involved; this code simply generates one word-pair
; for each and every edge in the clique of the sequence of the words.
;
; This code is problematic for multiple reasons:
; 1) The kinds of pairs it generates occur with different frequencies
;    than they would in a random planar tree parse.  In particular,
;    it generates more pairs between distant words than the planar tree
;    would. This could be ameliorated by simply not generating pairs
;    for words that are more than 6 lengths apart. Or, alternately,
;    only the statistics for closer pairs closer together than 6 could
;    be used.  Anyway, this is probably not a big deal, by itself.
;
; 2) This generates pairs tagged with the distance between the pairs.
;    (See below for the format).  This is might be interesting to
;    look at for academic reasons, but it currently puts a huge
;    impact on the size of the atomspace, and the size of the
;    database, impacting performance in a sharply negative way.
;    That's because, for every possible word-pair, chances are that
;    it will appear, sooner or later, with with every possible distance
;    from 1 to about 30. Each distance requires it's own atom to keep
;    count: thus requiring maybe 30x more atoms for word-pairs!  Ouch!
;    This is huge!
;
;    Limiting pair-counts to distances of 6 or less still blows up
;    the database size by 6x... which is still a lot.
;
;    We might be able to cut down on this by using different values
;    (on the same pair-atom) to count the different lengths, but the
;    hit is still huge.
;
; 3) On a per-sentence basis, when clique-counting is turned on, the
;    number of database updates increases by 3x-4x atom value updates.
;    If your database is on spinning disks, not SSD, this means that
;    database updates will be limited by the disk I/O subsystem, and
;    this additional traffic can slow down statistics gathering by...
;    3x or 4x.
;
; Thus, clique-counting is currently disabled. You can turn it on
; by uncommenting this routine in the main loop, below.
;
; Note that this might throw an exception...
;
; The structures that get created and incremented are of the form
;
;     EvaluationLink
;         PredicateNode "*-Sentence Word Pair-*"
;         ListLink
;             WordNode "lefty"  -- or whatever words these are.
;             WordNode "righty"
;
;     ExecutionLink
;         SchemaNode "*-Pair Distance-*"
;         ListLink
;             WordNode "lefty"
;             WordNode "righty"
;         NumberNode 3
;
; Here, the NumberNode encodes the distance between the words. It is always
; at least one -- i.e. it is the difference between their ordinals.
;
; Parameters:
; MAX-LEN -- integer: don't count a pair, if the words are farther apart
;            than this.
; RECORD-LEN -- boolean #t of #f: enable or disable recording of lengths.
;            If enabled, see warning about the quantity of data, above.
;
(define (update-pair-counts-once PARSE MAX-LEN RECORD-LEN)

	; Get the scheme-number of the word-sequence number
	(define (get-no seq-lnk)
		(cog-number (gdr seq-lnk)))

	; Create and count a word-pair, and the distance.
	(define (count-one-pair left-seq right-seq)
		(define dist (- (get-no right-seq) (get-no left-seq)))

		; Only count if the distance is less than the cap.
		(if (<= dist MAX-LEN)
			(let ((pare (ListLink (gar left-seq) (gar right-seq))))
				(count-one-atom (EvaluationLink *-word-pair-tag-* pare))
				(if RECORD-LEN
					(count-one-atom
						(ExecutionLink *-word-pair-dist-* pare (NumberNode dist)))))))

	; Create pairs from `first`, and each word in the list in `rest`,
	; and increment counts on these pairs.
	(define (count-pairs first rest)
		(if (not (null? rest))
			(begin
				(count-one-pair first (car rest))
				(count-pairs first (cdr rest)))))

	; Iterate over all of the words in the word-list, making pairs.
	(define (make-pairs word-list)
		(if (not (null? word-list))
			(begin
				(count-pairs (car word-list) (cdr word-list))
				(make-pairs (cdr word-list)))))

	; If this function throws, then it will be here, so all counting
	; will be skipped, if any one word fails.
	(define word-seq (make-word-sequence PARSE))

	; What the heck. Go ahead and count these, too.
	(for-each count-one-atom word-seq)

	; Count the pairs, too.
	(make-pairs word-seq)
)

; See above for explanation.
(define (update-clique-pair-counts SENT MAX-LEN RECORD-LEN)
	; In most cases, all parses return the same words in the same order.
	; Thus, counting only requires us to look at only one parse.
	(update-pair-counts-once
		(car (sentence-get-parses SENT))
		MAX-LEN RECORD-LEN)
)

; ---------------------------------------------------------------------
