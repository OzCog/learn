;
; orthogonal-ensemble.scm
;
; Experiments with gaussian orthogonal ensembles.
; Part of experiments/run-15, described in diary part eight.
;
; Sept 2022
; -------------------------------------
; Ingest data
(define pca (make-pseudo-cset-api)) ; shapes not needed to fetch sims.
(define pcs (add-pair-stars pca))
(define smi (add-similarity-api pcs #f "shape-mi"))

; Need to fetch all pairs, because the similarity object doesn't
; automate this.
(smi 'fetch-pairs) ;;; same as (load-atoms-of-type 'Similarity)

; -------------------------------------
; Graphs, verify it still looks gaussian.
; See similarity-graphs.scm -- this is a cut-n-paste from there.
; See line 196ff of similarity-graphs.scm

(define all-sims ((add-pair-stars smi) 'get-all-elts))

(define wmi (/ 2.0 (length all-sims)))

; Plain MI distribution
(define mi-dist
   (bin-count all-sims 100
      (lambda (SIM) (cog-value-ref (smi 'get-count SIM) 0))
      (lambda (SIM) wmi)
      -25 25))

; Ranked MI distribution
(define rmi-dist
   (bin-count all-sims 100
      (lambda (SIM) (cog-value-ref (smi 'get-count SIM) 1))
      (lambda (SIM) wmi)
      -25 25))

(define (prt-mi-dist)
	(define csv (open "/tmp/sim-mi-dist.dat" (logior O_WRONLY O_CREAT)))
	(print-bincounts-tsv mi-dist csv)
	(close csv))

(define (prt-rmi-dist)
	(define csv (open "/tmp/sim-rmi-dist.dat" (logior O_WRONLY O_CREAT)))
	(print-bincounts-tsv rmi-dist csv)
	(close csv))

; -------------------------------------
; TODO filter the top lists
; (define (filter the top list...

; Wrap similarity, to create a new base object.
(define sob (add-pair-stars smi))

; Counts on smi are FloatValues of two floats.
; First float is mi-sim
; Second float is ranked-mi-sim
; That is, (smi 'get-count PR) returns a FloatValue.
; So, unwrap it.
(define (add-mi-sim LLOBJ)
	(define (get-ref PR IDX)
		; Expect either a FloatValue or #f if absent.
		(define flov (LLOBJ 'get-count PR))
		(if flov (cog-value-ref flov IDX) -inf.0))

	(lambda (message . args)
		(case message
			((get-mi)  (get-ref (car args) 0))
			((get-rmi) (get-ref (car args) 1))
			(else      (apply LLOBJ (cons message args))))
	))

(define ami (add-mi-sim sob))

; -------------------------------------
; SKIP THIS. Its not needed.
; Compute vector norms. Use plain MI, for now.
; Its fast, (5 seconds) so do both left and right, to avoid confusion.
; Except we don't actually need this for anything ...
(define ssc (add-support-compute ami 'get-mi))
; (ssc 'all-left-marginals)
(ssc 'cache-all)

; Verify that values are not insane.
(define w (car (ssc 'left-basis)))
(ssc 'left-support w)
(ssc 'left-count w)

; The support API will provide access to the vector lengths.
(define gmi (add-support-api sob))
(gmi 'left-support w)
(gmi 'left-count w)

; The summary report is convoluted and ugly. Oh well.
; ((make-central-compute sob) 'cache-all)
; (print-matrix-summary-report sob)

; -------------------------------------
; Look at dot products
(define goe (add-gaussian-ortho-api ami 'get-mi))
(goe 'mean-rms)

; Make sure things work as expected.
(define gsu (add-support-compute goe #f "goe"))
(gsu 'all-left-marginals)

(define w (first (goe 'left-basis)))
(define u (second (goe 'left-basis)))

(gsu 'left-support w)
(gsu 'left-count w)
(gsu 'left-length w)

(define god (add-similarity-compute gsu))
(god 'left-cosine w u)

(god 'left-cosine (Word "the") (Word "a"))

(god 'left-product (Word "the") (Word "the"))

(gsu 'left-length (Word "the"))

; =================================================
; Below is a LONG debugging session. Ignore it.
; WTF why is it wrong?
(goe 'mean-rms)
;  (-1.4053400751699667 2.898486631855367)
(define self (Similarity (Word "the") (Word "the")))

(cog-value self (PredicateNode "*-SimKey shape-mi"))
; (FloatValue 4.892396662694156 10.02792661666408)
; first should be just (ami 'get-mi) ... and it is. Good.
(ami 'get-mi self)

; Verify this too -- looks OK
(goe 'get-count self)
; 2.1727672188133718

; So this is OK...
(define allwo (rank-words pcs))
(define nwrd 0)
(define nzwords '())
(fold
	(lambda (wrd sum)
; (format #t "wrd=~A<<\n" (cog-name wrd))
		(define sl (Similarity wrd (Word "the")))
; (format #t "sim=~A\n" sl)
; (format #t "mi=~A sum=~A\n" (ami 'get-mi sl) sum)
		(define cmp (goe 'get-count sl))
		; (define cmp (ami 'get-mi sl))
; (format #t "cmp=~A\n" cmp)
		(if (and (not (eqv? cmp 0)) (< -inf.0 cmp))
			(begin
;(format #t "cmp=~A old sum=~A wrd=~A<<\n" cmp sum (cog-name wrd))
;(format #t "wtf new sum=~A\n" (+ sum (* cmp cmp)))
				(set! nwrd (+ 1 nwrd))
				(set! nzwords (cons wrd nzwords))
				(+ sum (* cmp cmp)))
			sum)
	)
	0 allwo)
; 4360.614619250912
(sqrt 4360.614619250912)
; 66.03494998295155
2460 words participated.

(define gsu (add-support-compute goe))
(gsu 'left-length (Word "the"))
; 66.03494998295147

(define god (add-similarity-compute gsu))
(god 'left-product (Word "the") (Word "the"))
; 4365.335536638053

(define prod-obj (add-support-compute
    (add-fast-math goe * 'get-count)))
(define prod-obj (add-support-compute (add-fast-math goe *)))
(prod-obj 'left-count (list (Word "the") (Word "the")))
; 4365.335536638053
(prod-obj 'left-sum (list (Word "the") (Word "the")))
; 4365.335536638053

(define tup (add-support-compute (add-tuple-math goe *)))
(tup 'left-sum (list (Word "the") (Word "the")))
; 4360.614619250912

(define fma (add-fast-math goe * 'get-count))

(goe 'get-count (Similarity (Word "the") (Word "o'clock")))
-1.9411586964140686

(define sl (Similarity (Word "the") (Word "o'clock")))
(fma 'get-count (list sl sl))
; 3.768097084663966  OK.

(define df 0)
(define sm 0)
(for-each
	(lambda (wrd)
		(define sl (Similarity (Word "the") wrd))
		(define fpr (fma 'get-count (list sl sl)))
		(define cor (goe 'get-count sl))
		(define cors (* cor cor))
		(set! df (+ df (- cors fpr)))
		(set! sm (+ sm cors))
		(format #t "~6f ~6f dif=~6f sum=~6f ~A\n" fpr cors df sm (cog-name wrd))
	)
	nzwords)
; 4360.614619250919

	allwo)
; 4360.614619250912

(define fas (add-support-compute fma))
(fas 'left-sum (list (Word "the") (Word "the")))
4365.3355366380665

add-support-compute 'left-sum
(length (fma 'left-stars (list (Word "the") (Word "the"))))
; 9496
; 2501 ... wtf ..

(length allwo)
; 9495

(define fwo
	(append
	(map (lambda (prs) (gar (car prs)))
		(fma 'left-stars (list (Word "the") (Word "the"))))
	(map (lambda (prs) (gdr (car prs)))
		(fma 'left-stars (list (Word "the") (Word "the"))))))

(define faswo (delete-dup-atoms fwo))
(length faswo)
2500

(atoms-subtract faswo allwo)

(define wl '())
(for-each
	(lambda (prs)
		(define sl (car prs))
		(define fw (gar sl))
		(define sw (gdr sl))
		(define ow (if (equal? (Word "the") fw) sw fw))
		(when (equal? (Word "the") ow)
			(format #t "yo its ~A" sl))
		(set! wl (cons ow wl)))
	(fma 'left-stars (list (Word "the") (Word "the"))))
(length wl)
; 2501
(length (delete-dup-atoms wl))
; 2500
(keep-duplicate-atoms wl)
; (WordNode "the")

(goe 'get-count (Similarity (Word "the") (Word "the")))
; 2.1727672188133718

(* 2.1727672188133718 2.1727672188133718)
; 4.720917387149995
(- 4365.335536638053 4360.614619250912)
; 4.7209173871406165

Holy cow.
So (fma 'left-stars (list (Word "the") (Word "the"))))
has a duplicate entry! Sheesh, that took a long time.

; Confirm.
(keep-duplicate-atoms
	(map car (fma 'left-stars (list (Word "the") (Word "the")))))

(define row-var (uniquely-named-variable))
(define LLOBJ goe)
(define (thunk-type TY) (if (symbol? TY) (TypeNode TY) TY))
(define row-type (thunk-type (LLOBJ 'left-type)))
; (TypeNode "WordNode")
(define COL-TUPLE (list (Word "the") (Word "the")))
(define term-list
    (map (lambda (COL) (LLOBJ 'make-pair row-var COL)) COL-TUPLE))

(define qry
   (Meet
     (TypedVariable row-var row-type)
     (Present term-list)))
(define rowset (cog-value->list (cog-execute! qry)))
(length rowset)
; 2501

Got it. Must deduplicate.
Fixed in 4d4c7fe854208798e36c76fb8d740d89b54aa949
; =================================================

; wtf is this??
(cog-value self (PredicateNode "*-SimKey goe"))


; This is not the minus sign, its some utf8 dash
(define wtf (Similarity (Word "the") (Word "‑")))
(cog-keys wtf)
(ami 'get-mi wtf)

; =================================================

(god 'left-cosine (Word "the") (Word "a"))

(god 'left-product (Word "the") (Word "the"))
; 4360.614619250908
(god 'left-cosine (Word "the") (Word "the"))
; 0.999999999999999

Yayyy!

; -------------------------------------
; Compute a bunch of them.
(smi 'fetch-pairs)

; goe provides the 'get-count method that returns a renormalized
; version of whatever 'get-mi returns.
(define goe (add-gaussian-ortho-api ami 'get-mi))
(goe 'mean-rms)
(define gos (add-similarity-api ami #f "goe"))
(define god (add-similarity-compute goe))

(define (do-compute A B)
	(define sim (god 'left-cosine A B))
	(format #t "cos=~7F for (\"~A\", \"~A\")\n" sim (cog-name A) (cog-name B))
	; (store-atom ...)
	(gos 'set-pair-similarity
		(gos 'make-pair A B)
		(FloatValue sim)))

(define (dot-prod A B)
	(define have-it (gos 'pair-count A B))
	(if (not have-it) (do-compute A B)))

(define allwo (rank-words pcs))
(loop-upper-diagonal dot-prod allwo 0 50)

cos=0.33705 for ("by", ".")
(define sl (Similarity (Word "by") (Word ".")))
(cog-keys sl)
(cog-value sl (PredicateNode "*-SimKey goe"))
; Yayyy!

; -------------------------------------
; Graphs of cosine distance distributions.

(gos 'pair-count (Word "house") (Word "the"))
(gos 'get-count (Similarity (Word "house") (Word "the")))

(define all-sims ((add-pair-stars smi) 'get-all-elts))
(define all-sims (cog-get-atoms 'Similarity))
(length all-sims) ; 3126250
(define all-cosi (filter (lambda (sl) (gos 'get-count sl)) all-sims))
(length all-cosi) ; 31375 = (251 * 250) / 2

; 100 because 100 bins, and 2.0 because of width
(define wmi (/ 100 (* 2.0 (length all-cosi))))

; Plain cosine-MI distribution
(define cos-mi-dist
   (bin-count all-cosi 100
      (lambda (SIM) (cog-value-ref (gos 'get-count SIM) 0))
      (lambda (SIM) wmi)
      -1 1))

(define cos-rmi-dist
   (bin-count all-cosi 100
      (lambda (SIM) (cog-value-ref (gos 'get-count SIM) 1))
      (lambda (SIM) wmi)
      -1 1))

(define (prt-cos-mi-dist)
	(define csv (open "/tmp/cos-mi-dist-250.dat" (logior O_WRONLY O_CREAT)))
	(print-bincounts-tsv cos-mi-dist csv)
	(close csv))

(define (prt-cos-rmi-dist)
	(define csv (open "/tmp/cos-rmi-dist-250.dat" (logior O_WRONLY O_CREAT)))
	(print-bincounts-tsv cos-rmi-dist csv)
	(close csv))

; ----------
; Again same as above out to M=500 insead of 250

(define cosi-500 (filter (lambda (sl) (gos 'get-count sl)) all-sims))
(length cosi-500) ; 125250 = 500*501 / 2

(define cosi-1k (filter (lambda (sl) (gos 'get-count sl))
	(cog-get-atoms 'SimilarityLink)))
(length cosi-1k) ; 500500 = 1000 * 1001 / 2


(define (cos-dist LST)
	(define wnc (/ 100 (* 2.0 (length LST))))
   (bin-count LST 100
      (lambda (SIM) (cog-value-ref (gos 'get-count SIM) 0))
      (lambda (SIM) wnc)
      -1 1))

(define cos-mi-dist-500 (cos-dist cosi-500))
(define cos-mi-dist-1k (cos-dist cosi-1k))

(define (prt-cos-mi-500-dist)
	(define csv (open "/tmp/cos-mi-dist-500.dat" (logior O_WRONLY O_CREAT)))
	(print-bincounts-tsv cos-mi-dist-500 csv)
	(close csv))

(define (prt-cos-mi-1k-dist)
	(define csv (open "/tmp/cos-mi-dist-1k.dat" (logior O_WRONLY O_CREAT)))
	(print-bincounts-tsv cos-mi-dist-1k csv)
	(close csv))

; ---------------------------------------
; Dump datafile -- goe cos-MI vs MI scatterplot
; Graphed with p8-goe/scatter-goe-mi-rmi.gplot and related.

(chdir "/home/ubuntu/experiments/run-15/data")

(define (scatter-goe DOT-LIST FILENAME)
	(define csv (open FILENAME (logior O_WRONLY O_CREAT)))
	(define cnt 0)
	(format csv "#\n# MI and Cosines\n#\n")
	(format csv "#\n# mi\trmi\tcos-mi\tcos-rmi\n")
	(for-each
		(lambda (SL)
			(format csv "~8F\t~8F\t~8F\t~8F\n"
				(cog-value-ref (smi 'get-count SL) 0)
				(cog-value-ref (smi 'get-count SL) 1)
				(cog-value-ref (gos 'get-count SL) 0)
				(cog-value-ref (gos 'get-count SL) 1)))
		DOT-LIST)
	(close csv)
)

(scatter-goe all-cosi "scatter-goe.dat")

; ---------------------------------------
; Top most similar words (according to goe)

(define (lessi A B)
	(> (cog-value-ref (gos 'get-count A) 0)
		(cog-value-ref (gos 'get-count B) 0)))

(define all-cosi-ord (sort all-cosi lessi))

(define distinct-cosi-ord
	(filter (lambda (SL) (not (equal? (gar SL) (gdr SL)))) all-cosi-ord))

(define (top-pairs LST N)
	(for-each (lambda (SL)
		(format #t "~6F ~A ~A\n" (cog-value-ref (gos 'get-count SL) 0)
			(cog-name (gar SL)) (cog-name (gdr SL))))
		(take LST N)))

(top-pairs distinct-cosi-ord 20)

(top-pairs (drop distinct-cosi-ord 200) 20)

; --------------
; Do it again, but for old RMI -- the top-20 RMI-associated words.
(define (lessr A B)
	(> (cog-value-ref (smi 'get-count A) 1)
		(cog-value-ref (smi 'get-count B) 1)))

(define all-rmi-ord (sort all-cosi lessr))

(define distinct-rmi-ord
	(filter (lambda (SL) (not (equal? (gar SL) (gdr SL)))) all-rmi-ord))

(top-pairs distinct-rmi-ord 20)

(define (top-pairs LST N)
	(for-each (lambda (SL)
		(format #t "~6F, ~6F, ~A, ~A\n"
			(cog-value-ref (gos 'get-count SL) 0)
			(cog-value-ref (smi 'get-count SL) 1)
			(cog-name (gar SL)) (cog-name (gdr SL))))
		(take LST N)))

; ---------------------------------------
; Vector addititivity

(define gos (add-similarity-api ami #f "goe"))

(define (most-sim A B C WLIST)
	(define wa (cog-node 'WordNode A))
	(define wb (cog-node 'WordNode B))
	(define wc (cog-node 'WordNode C))
	(if (not (and wa wb wc))
		(throw 'bad-word 'most-sim "a word doesnt exist"))

	(define (get-sim wp wq)
		; (define OFF 1)
		(define OFF 1)
		(define fa (gos 'pair-count wp wq))
		(if fa (cog-value-ref fa OFF) 0.0))

	(define sims (map
		(lambda (W)
			(define sa (get-sim W wa))
			(define sb (get-sim W wb))
			(define sc (get-sim W wc))
			(define vs (+ (- sa sb) sc))
			(cons W vs))
		WLIST))

	(define sosi
		(sort sims (lambda (L R) (> (cdr L) (cdr R)))))

	(for-each (lambda (ITM)
		(format #t "~A, ~6F\n" (cog-name (car ITM)) (cdr ITM)))
		(take sosi 10))
)

(most-sim "husband" "man" "woman" (take allwo 1000))
(most-sim "brother" "man" "woman" (take allwo 1000))
(most-sim "boy" "man" "woman" (take allwo 1000))

(most-sim "Paris" "France" "Spain" (take allwo 1000))
(most-sim "Paris" "France" "Germany" (take allwo 1000))
(most-sim "London" "England" "Germany" (take allwo 1000))

(most-sim "tree" "leaf" "flower" (take allwo 1000))
(most-sim "dog" "puppy" "cat" (take allwo 1000))
(most-sim "kitten" "cat" "puppy" (take allwo 1000))

(most-sim "hammer" "nail" "comb" (take allwo 1000))

(most-sim "black" "white" "up" (take allwo 1000))
(most-sim "black" "white" "good" (take allwo 1000))
(most-sim "black" "white" "smile" (take allwo 1000))
(most-sim "black" "white" "love" (take allwo 1000))

(most-sim "short" "light" "long" (take allwo 1000))
(most-sim "speak" "sing" "walk" (take allwo 1000))
(most-sim "like" "love" "dislike" (take allwo 1000))
(most-sim "left" "right" "north" (take allwo 1000))

(most-sim "flood" "rain" "drought" (take allwo 1000))
(most-sim "giggle" "laugh" "sniffle" (take allwo 1000))

(most-sim "blue" "sky" "green" (take allwo 1000))

; ---------------------------------------
; Recursion and hypervectors

(define gob (add-pair-stars goe))
(gob 'left-basis-size)
; 2516 which is ...too big...
(gob 'right-basis-size)
; 2516

(define five-oh (take allwo 500))
(define gob (add-keep-filter goe five-oh five-oh #t))
(gob 'left-basis-size)
; 500 OK

(define eft (add-gaussian-ortho-api gob))
(eft 'mean-rms)
;  (-0.25555738133716827 1.1584385596852502)
; That seems wrong; from histogram, it should be positive!?
; Well, it is wrong: goe is just returning normalized MI see below.

(define kay-oh (take allwo 1000))
(define gob (add-keep-filter goe kay-oh kay-oh #t))
(gob 'left-basis-size)
; 1000 OK

(define eft (add-gaussian-ortho-api gob))
(eft 'mean-rms)
; (-0.2180147305050371 1.1366521583220763)

(define ba (take allwo 1))
(define gob (add-keep-filter goe ba ba #t))
; (2.172767218813379 0.0)
(goe 'get-count (SimilarityLink (WordNode "the") (WordNode "the")))
; 2.172767218813379
(define ba (take allwo 2))
;  (1.414824560307269 1.0428797257092879)
(define ba (take allwo 3))
; (1.2329852733998437 0.9772158839540837)
(define ba (take allwo 30))
; (0.390644117360052 0.9305769758909003)
(define ba (take allwo 130))
; (0.0020365579834682895 1.085450691694644)
(define ba (take allwo 250))
(-0.1952801391684226 1.1732756963984179)

; WTF double check above
(define alle (gob 'get-all-elts))
(define wmi (/ 0.5 (length alle)))
(define wtf-dist
   (bin-count alle 100
      (lambda (SIM) (goe 'get-count SIM))
      (lambda (SIM) wmi)
      -1 1))

(define (prt-wtf-dist)
	(define csv (open "/tmp/wtf-dist.dat" (logior O_WRONLY O_CREAT)))
	(print-bincounts-tsv wtf-dist csv)
	(close csv))

; Hang on, what are we doing?
(define goe (add-gaussian-ortho-api ami 'get-mi))
(goe 'mean-rms)

; So (goe 'get-count) just returns the MI's after renormalization
; the actual similarity vectors are in gos:
(define gos (add-similarity-api ami #f "goe"))

; Well, wtf, This is confusing.... what's with the graph?
; why is it spiked?
; Clearly the spikes affect the mean and rms...
; I'm confused.

; ------
; So the correct flow is this:
(define ba (take allwo 1))
(define gob (add-keep-filter gos ba ba #t))
(gob 'left-basis-size)
(gob 'get-all-elts)
(gob 'get-count (car (gob 'get-all-elts)))

(define five-oh (take allwo 500))
(define gob (add-keep-filter gos five-oh five-oh #t))

(define (add-goe-sim LLOBJ)
	(define (get-ref PR IDX)
		; Expect FloatValue always IDX=0 is the MI sims, and 1 is the RMI
		(cog-value-ref (LLOBJ 'get-count PR) IDX))

	(lambda (message . args)
		(case message
			((get-count)  (get-ref (car args) 0))
			(else      (apply LLOBJ (cons message args))))
	))

(define goc (add-goe-sim gob))
(goc 'get-count (car (goc 'get-all-elts)))

(define eft (add-gaussian-ortho-api goc))
(eft 'mean-rms)
; (0.3370672938409221 0.33866241211790027)

(define efc (add-similarity-compute eft))

; ---------------------------------------
