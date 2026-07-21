;; igropyr.com background — one WebGL story in four movements.
;;
;;  1. FIRE   the honeycomb catches like a lit fuse (this is fire.ss:
;;            a Dijkstra front over the hex lattice, embers on transform
;;            feedback, an HDR bloom) and the ashes dissolve.
;;  2. PAUSE  three seconds of dark, after the ashes are gone.
;;  3. ICE    a frost front climbs the SAME lattice from the bottom up,
;;            each edge hardening from an icy crest to Goeteia lapis.
;;  4. WORD   the frozen dots let go of the honeycomb and fly together
;;            into GOETEIA (hero.ss's transform-feedback text particles),
;;            then hold with a whisper of life.
;;
;; Everything renders through (gfx fx) over (gfx gl)'s command buffer:
;; one bridge call per frame, GPU-resident particle state.
(import (rnrs) (web js) (web dom) (gfx gl) (gfx glsl) (gfx fx)
        (hive-data))

(define canvas (get-element-by-id "bg"))
(fx-init! canvas)

;; ================= the honeycomb graph (from fire.ss) =================
(define V (vector-length hive-vx))
(define Ecount (vector-length hive-ea))
(define (vx i) (vector-ref hive-vx i))
(define (vy i) (vector-ref hive-vy i))
(define (elen a b)
  (let ((dx (fl- (vx a) (vx b))) (dy (fl- (vy a) (vy b))))
    (flsqrt (fl+ (fl* dx dx) (fl* dy dy)))))

(define adj-n (make-vector V '()))
(define adj-l (make-vector V '()))
(let loop ((e 0))
  (when (< e Ecount)
    (let* ((a (vector-ref hive-ea e)) (b (vector-ref hive-eb e)) (L (elen a b)))
      (vector-set! adj-n a (cons b (vector-ref adj-n a)))
      (vector-set! adj-l a (cons L (vector-ref adj-l a)))
      (vector-set! adj-n b (cons a (vector-ref adj-n b)))
      (vector-set! adj-l b (cons L (vector-ref adj-l b))))
    (loop (+ e 1))))

;; Dijkstra from the bottom-left seed gives every point its arrival distance
(define INF 1000000000.0)
(define dist (make-vector V INF))
(define done (make-vector V #f))
(vector-set! dist hive-seed 0.0)
(let steps ((k 0))
  (when (< k V)
    (let pick ((i 0) (best -1) (bd INF))
      (if (= i V)
          (when (>= best 0)
            (vector-set! done best #t)
            (let relax ((ns (vector-ref adj-n best)) (ls (vector-ref adj-l best)))
              (when (pair? ns)
                (let ((w (car ns)) (nd (fl+ (vector-ref dist best) (car ls))))
                  (when (fl<? nd (vector-ref dist w))
                    (vector-set! dist w nd))
                  (relax (cdr ns) (cdr ls))))))
          (if (and (not (vector-ref done i)) (fl<? (vector-ref dist i) bd))
              (pick (+ i 1) i (vector-ref dist i))
              (pick (+ i 1) best bd))))
    (steps (+ k 1))))

;; sample each edge into the fuse point cloud: vec4 (x, y, arrival, seed)
(define SP 1.2)
(define (edge-segs e)
  (let* ((a (vector-ref hive-ea e)) (b (vector-ref hive-eb e))
         (s (%fl->fx (fl/ (elen a b) SP))))
    (if (< s 2) 2 s)))
(define npoints
  (let cnt ((e 0) (n 0))
    (if (= e Ecount) n (cnt (+ e 1) (+ n (edge-segs e) 1)))))
(define POS (fx-alloc! (* npoints 16)))

(define lcg 12345)
(define (rnd)
  (set! lcg (remainder (+ (* lcg 1103) 12345) 32749))
  (fl/ (fixnum->flonum lcg) 32749.0))

(let ecut ((e 0) (n 0))
  (when (< e Ecount)
    (let* ((a (vector-ref hive-ea e)) (b (vector-ref hive-eb e))
           (xa (vx a)) (ya (vy a)) (xb (vx b)) (yb (vy b))
           (L (elen a b))
           (da (vector-ref dist a)) (db (vector-ref dist b))
           (segs (edge-segs e)))
      (let put ((i 0) (m n))
        (if (> i segs)
            (ecut (+ e 1) m)
            (let* ((s (fl/ (fixnum->flonum i) (fixnum->flonum segs)))
                   (x (fl+ xa (fl* (fl- xb xa) s)))
                   (y (fl+ ya (fl* (fl- yb ya) s)))
                   (arr-a (fl+ da (fl* s L)))
                   (arr-b (fl+ db (fl* (fl- 1.0 s) L)))
                   (arr (if (fl<? arr-a arr-b) arr-a arr-b))
                   (o (+ POS (* m 16))))
              (%mem-f32-set! o x)
              (%mem-f32-set! (+ o 4) y)
              (%mem-f32-set! (+ o 8) arr)
              (%mem-f32-set! (+ o 12) (rnd))
              (put (+ i 1) (+ m 1))))))))

(define maxd
  (let mx ((i 0) (m 0.0))
    (if (= i V) m
        (let ((d (vector-ref dist i)))
          (mx (+ i 1) (if (and (fl<? d INF) (fl<? m d)) d m))))))

;; ---- reconstruct the hexagon cells, for the frost that freezes them ----
;; A planar face walk over the edge graph recovers each hexagon. Sort every
;; vertex's neighbours by a trig-free pseudo-angle (monotone in [0,4) with
;; the CCW angle), then trace faces by always turning to the clockwise
;; predecessor; the 6-cycles are the cells.
(define (pang i j)
  (let* ((dx (fl- (vx j) (vx i))) (dy (fl- (vy j) (vy i)))
         (ax (if (fl<? dx 0.0) (fl- 0.0 dx) dx))
         (ay (if (fl<? dy 0.0) (fl- 0.0 dy) dy))
         (s (fl+ ax ay))
         (u (if (fl<? s 0.001) 0.0 (fl/ dy s))))
    (cond ((fl<? dx 0.0) (fl- 2.0 u))
          ((fl<? dy 0.0) (fl+ 4.0 u))
          (else u))))
(define (insert-nbr i x sorted)
  (cond ((null? sorted) (list x))
        ((fl<? (pang i x) (pang i (car sorted))) (cons x sorted))
        (else (cons (car sorted) (insert-nbr i x (cdr sorted))))))
(define adjv (make-vector V #f))
(do ((i 0 (+ i 1))) ((= i V))
  (vector-set! adjv i
    (list->vector
      (let s ((xs (vector-ref adj-n i)) (acc '()))
        (if (null? xs) acc (s (cdr xs) (insert-nbr i (car xs) acc)))))))
(define (nbr-index v u)
  (let ((nb (vector-ref adjv v)))
    (let loop ((k 0)) (if (= (vector-ref nb k) u) k (loop (+ k 1))))))
(define seen (make-vector V '()))
(define hexes '())
(do ((u 0 (+ u 1))) ((= u V))
  (for-each
   (lambda (v0)
     (unless (memv v0 (vector-ref seen u))
       (let loop ((pu u) (pv v0) (acc '()) (n 0))
         (cond
          ((> n 7) #f)                          ; the outer face: too long, drop
          ((and (> n 0) (= pu u) (= pv v0))
           (when (= n 6) (set! hexes (cons acc hexes))))
          (else
           (vector-set! seen pu (cons pv (vector-ref seen pu)))
           (let* ((nb (vector-ref adjv pv)) (deg (vector-length nb))
                  (iu (nbr-index pv pu))
                  (iw (let ((z (- iu 1))) (if (< z 0) (+ z deg) z)))
                  (w (vector-ref nb iw)))
             (loop pv w (cons pv acc) (+ n 1))))))))
   (vector-ref adj-n u)))
(define nhex (length hexes))

;; build a triangle-fan mesh of the cells: per vertex (x, y, arrival, seed,
;; edge) where arrival is the cell's (its last-drawn corner, so it fills
;; only once fully outlined), edge is 0 at the centre and 1 at the rim
(define nfillv (* nhex 18))
(define FILLV (fx-alloc! (* (if (> nfillv 0) nfillv 1) 20)))
(define (putv o x y arr sd edge)
  (%mem-f32-set! o x) (%mem-f32-set! (+ o 4) y)
  (%mem-f32-set! (+ o 8) arr) (%mem-f32-set! (+ o 12) sd)
  (%mem-f32-set! (+ o 16) edge))
(let build ((hs hexes) (o FILLV))
  (when (pair? hs)
    (let* ((hv (list->vector (car hs)))
           (cx (let l ((k 0) (a 0.0)) (if (= k 6) (fl/ a 6.0) (l (+ k 1) (fl+ a (vx (vector-ref hv k)))))))
           (cy (let l ((k 0) (a 0.0)) (if (= k 6) (fl/ a 6.0) (l (+ k 1) (fl+ a (vy (vector-ref hv k)))))))
           (arr (let l ((k 0) (m 0.0))
                  (if (= k 6) m
                      (let ((d (vector-ref dist (vector-ref hv k))))
                        (l (+ k 1) (if (fl<? m d) d m))))))
           (sd (rnd)))
      (let tri ((k 0) (o o))
        (if (= k 6)
            (build (cdr hs) o)
            (let* ((a (vector-ref hv k)) (b (vector-ref hv (if (= k 5) 0 (+ k 1)))))
              (putv o cx cy arr sd 0.0)
              (putv (+ o 20) (vx a) (vy a) arr sd 1.0)
              (putv (+ o 40) (vx b) (vy b) arr sd 1.0)
              (tri (+ k 1) (+ o 60))))))))

;; ================= word homes: GOETEIA and IGROPYR (rasterize+sample) ==
;; a hidden 2d canvas in the same 1120x760 space; lit pixels become homes
(define hidden (create-element "canvas"))
(js-set! hidden "width" 1120)
(js-set! hidden "height" 760)
(js-set! (js-global) "__bg_cv" hidden)
(define hctx
  (js-eval "globalThis.__bg_cv.getContext('2d', { willReadFrequently: true })"))
(js-set! hctx "fillStyle" "#fff")
(js-set! hctx "textAlign" "center")
(js-set! hctx "textBaseline" "middle")
(js-set! hctx "font" "700 200px Georgia, 'Times New Roman', serif")

(define CAPT 7000)
(define samp-px (fx-alloc! (* 1120 760 4)))
(define (sample-word! word home)                 ; -> count of lit pixels
  (js-method hctx "clearRect" 0 0 1120 760)
  (js-method hctx "fillText" word 560.0 392.0)
  (let* ((img (js-method hctx "getImageData" 0 0 1120 760))
         (view (js-new (js-get (js-global) "Uint8Array")
                       (js-get (js-get (js-global) "__goeteia_mem") "buffer")
                       samp-px (* 1120 760 4))))
    (js-method view "set" (js-get img "data"))
    (let yloop ((y 0) (n 0))
      (if (>= y 760)
          n
          (let xloop ((x 0) (n n))
            (cond
             ((>= x 1120) (yloop (+ y 3) n))
             ((and (< n CAPT)
                   (> (%mem-u8-ref (+ samp-px (+ (* (+ (* y 1120) x) 4) 3))) 100))
              (%mem-f32-set! (+ home (* n 8)) (fixnum->flonum x))
              (%mem-f32-set! (+ home (+ (* n 8) 4)) (fixnum->flonum y))
              (xloop (+ x 3) (+ n 1)))
             (else (xloop (+ x 3) n))))))))
(define GHOME (fx-alloc! (* CAPT 8)))
(define IHOME (fx-alloc! (* CAPT 8)))
(define nG (sample-word! "GOETEIA" GHOME))
(define nI (sample-word! "IGROPYR" IHOME))
(define pool (if (< nG nI) nI nG))

;; particle state: pos2 vel2 homeG2 homeI2 hive2 seed = 44 bytes. Each dot
;; rests on a random honeycomb point (its "dispersed" home, so it scatters
;; back there between words); spares a word doesn't need park off-screen
(define (park) (if (fl<? (rnd) 0.5)
                   (fl- 0.0 (fl+ 60.0 (fl* 80.0 (rnd))))
                   (fl+ 1180.0 (fl* 80.0 (rnd)))))
(define WST (fx-alloc! (* pool 44)))
(let fill ((i 0))
  (when (< i pool)
    (let* ((p (%fl->fx (fl* (rnd) (fixnum->flonum npoints))))
           (src (+ POS (* p 16)))
           (hx (%mem-f32-ref src)) (hy (%mem-f32-ref (+ src 4)))
           (o (+ WST (* i 44))))
      (%mem-f32-set! o hx) (%mem-f32-set! (+ o 4) hy)     ; pos = hive point
      (%mem-f32-set! (+ o 8) 0.0) (%mem-f32-set! (+ o 12) 0.0)  ; vel
      (if (< i nG)
          (begin (%mem-f32-set! (+ o 16) (%mem-f32-ref (+ GHOME (* i 8))))
                 (%mem-f32-set! (+ o 20) (%mem-f32-ref (+ GHOME (+ (* i 8) 4)))))
          (begin (%mem-f32-set! (+ o 16) (park)) (%mem-f32-set! (+ o 20) (fl* 760.0 (rnd)))))
      (if (< i nI)
          (begin (%mem-f32-set! (+ o 24) (%mem-f32-ref (+ IHOME (* i 8))))
                 (%mem-f32-set! (+ o 28) (%mem-f32-ref (+ IHOME (+ (* i 8) 4)))))
          (begin (%mem-f32-set! (+ o 24) (park)) (%mem-f32-set! (+ o 28) (fl* 760.0 (rnd)))))
      (%mem-f32-set! (+ o 32) hx) (%mem-f32-set! (+ o 36) hy)   ; hive / dispersed
      (%mem-f32-set! (+ o 40) (rnd)))                    ; seed
    (fill (+ i 1))))

;; ================= FIRE: the burning honeycomb (fire.ss) ==============
(define fire-p
  (fx-program!
   '((attribute vec4 a)
     (uniform float front)
     (varying float v_heat)
     (varying float v_seed)
     (define (main) void
       (local float heat (- front a.z))
       (set! v_heat heat)
       (set! v_seed a.w)
       (local vec2 c (vec2 (- (* (/ a.x (fl 1120)) (fl 2)) (fl 1))
                           (- (fl 1) (* (/ a.y (fl 760)) (fl 2)))))
       (set! gl_Position (vec4 c (fl 0) (fl 1)))
       (local float sz (fl 2 40))
       (if (>= heat (fl 0))
           (local float tip (exp (- (/ (* heat heat) (fl 50)))))
           (local float glow (exp (- (/ (* heat heat) (fl 1250)))))
           (set! sz (+ (fl 2 40) (* (fl 8) tip) (* (fl 4) glow))))
       (set! gl_PointSize sz)))
   '((precision mediump float)
     (varying float v_heat)
     (varying float v_seed)
     (uniform float time)
     (uniform float fade)
     (define (main) void
       (if (< v_heat (fl 0)) (discard))
       (local vec2 d (- gl_PointCoord (vec2 (fl 0 50) (fl 0 50))))
       (local float r2 (dot d d))
       (if (> r2 (fl 0 25)) (discard))
       (local float soft (- (fl 1) (* r2 (fl 4))))
       (local vec3 base (vec3 (fl 0 91) (fl 0 51) (fl 0 36)))
       (local float flick (+ (fl 0 80) (* (fl 0 20) (sin (+ (* time (fl 22)) (* v_seed (fl 40)))))))
       (local float t (clamp (/ v_heat (fl 320)) (fl 0) (fl 1)))
       (local vec3 c (mix (vec3 (fl 1) (fl 0 93) (fl 0 62))
                          (vec3 (fl 1) (fl 0 42) (fl 0 2))
                          (smoothstep (fl 0) (fl 0 10) t)))
       (set! c (mix c (vec3 (fl 0 95) (fl 0 26) (fl 0 2)) (smoothstep (fl 0 10) (fl 0 35) t)))
       (set! c (mix c base (smoothstep (fl 0 35) (fl 1) t)))
       (local float av (* (mix (fl 1) (fl 0 22) (smoothstep (fl 0 05) (fl 1) t)) fade))
       (local float hot (+ (fl 1) (* "2.2" (exp (- (/ (* v_heat v_heat) "60.0"))))))
       (set! gl_FragColor (vec4 (* (* c flick) hot) (* av soft)))))))

;; ================= ICE: a frost front that climbs and hardens =========
;; the same fuse cloud, but the metric climbs from the bottom edge up
;; (760 - y, jittered by seed) so the frost rises along the lattice, and
;; the colour hardens from an icy crest to Goeteia lapis instead of fading
(define ice-p
  (fx-program!
   '((attribute vec4 a)
     (uniform float ice)
     (varying float v_ih)
     (varying float v_seed)
     (define (main) void
       ;; the SAME arrival metric the fire used (a.z, Dijkstra from the
       ;; bottom-left seed), so the frost travels the identical diagonal;
       ;; a little seed jitter only roughens the crystal crest
       (local float ia (+ a.z (- (* a.w (fl 24)) (fl 12))))
       (local float ih (- ice ia))
       (set! v_ih ih)
       (set! v_seed a.w)
       (local vec2 c (vec2 (- (* (/ a.x (fl 1120)) (fl 2)) (fl 1))
                           (- (fl 1) (* (/ a.y (fl 760)) (fl 2)))))
       (set! gl_Position (vec4 c (fl 0) (fl 1)))
       (local float sz (fl 2 40))
       (if (>= ih (fl 0))
           (local float crest (exp (- (/ (* ih ih) (fl 40)))))
           (set! sz (+ (fl 2 40) (* (fl 3) crest))))
       (set! gl_PointSize sz)))
   '((precision mediump float)
     (varying float v_ih)
     (varying float v_seed)
     (uniform float time)
     (uniform float alpha)
     (define (main) void
       (if (< v_ih (fl 0)) (discard))
       (local vec2 d (- gl_PointCoord (vec2 (fl 0 50) (fl 0 50))))
       (local float r2 (dot d d))
       (if (> r2 (fl 0 25)) (discard))
       (local float soft (- (fl 1) (* r2 (fl 4))))
       (local float t (clamp (/ v_ih (fl 120)) (fl 0) (fl 1)))
       (local vec3 crest (vec3 (fl 0 80) (fl 0 94) (fl 1)))
       (local vec3 azure (vec3 (fl 0 28) (fl 0 53) (fl 0 93)))
       (local vec3 lapis (vec3 (fl 0 08) (fl 0 31) (fl 0 77)))
       (local vec3 c (mix crest azure (smoothstep (fl 0) (fl 0 25) t)))
       (set! c (mix c lapis (smoothstep (fl 0 25) (fl 1) t)))
       (local float glint (+ (fl 0 85) (* (fl 0 15) (sin (+ (* time (fl 8)) (* v_seed (fl 40)))))))
       (local float hot (+ (fl 1) (* "1.1" (exp (- (/ (* v_ih v_ih) "50.0"))))))
       (set! gl_FragColor (vec4 (* (* c glint) hot) (* alpha soft)))))))

;; ================= FROST: the cells freeze a beat behind the line ======
;; a translucent triangle-fan fill per hexagon, blue-white, fading in
;; only once (ice - cell arrival) has passed the one-second lag
(define frost-p
  (fx-program!
   '((attribute vec2 a_pos)
     (attribute vec3 a_meta)                ; arrival, seed, edge
     (uniform float ice)
     (uniform float lag)
     (varying float v_fill)
     (varying float v_edge)
     (varying float v_seed)
     (define (main) void
       (local vec2 c (vec2 (- (* (/ a_pos.x (fl 1120)) (fl 2)) (fl 1))
                           (- (fl 1) (* (/ a_pos.y (fl 760)) (fl 2)))))
       (set! gl_Position (vec4 c (fl 0) (fl 1)))
       (set! v_fill (smoothstep lag (+ lag (fl 150)) (- ice a_meta.x)))
       (set! v_edge a_meta.z)
       (set! v_seed a_meta.y)))
   '((precision mediump float)
     (varying float v_fill)
     (varying float v_edge)
     (varying float v_seed)
     (uniform float time)
     (uniform float alpha)
     (define (main) void
       (if (< v_fill (fl 0 01)) (discard))
       ;; a pale icy blue at the frosted centre deepening to Goeteia blue at
       ;; the rim -- kept blue (not white) so the freeze reads on a light page
       (local vec3 icy (vec3 (fl 0 62) (fl 0 80) (fl 0 99)))
       (local vec3 blue (vec3 (fl 0 30) (fl 0 52) (fl 0 92)))
       (local vec3 c (mix icy blue v_edge))
       (local float sh (+ (fl 0 86) (* (fl 0 14) (sin (+ (* time (fl 3)) (* v_seed (fl 30)))))))
       ;; a touch of feather at the rim so neighbouring cells don't hard-tile
       (local float a (* v_fill (- (fl 1) (* v_edge (fl 0 30)))))
       (set! gl_FragColor (vec4 (* c sh) (* (* a (fl 0 78)) alpha)))))))

;; ================= embers (fire.ss, transform feedback) ===============
(define NEMBER 3000)
(define ember-update
  (fx-tf-program!
   '((attribute vec2 a_pos)
     (attribute vec2 a_vel)
     (attribute vec2 a_home)
     (attribute vec3 a_meta)
     (uniform float u_dt)
     (uniform float u_time)
     (varying vec2 v_pos)
     (varying vec2 v_vel)
     (varying vec2 v_home)
     (varying vec3 v_meta)
     (define (main) void
       (local float life (- a_meta.y (* u_dt "0.9")))
       (local vec2 pos a_pos)
       (local vec2 vel a_vel)
       (local float seed a_meta.z)
       (if-else (< life (fl 0))
                ((local float s (fract (* (sin (* seed "127.1")) "43758.5453")))
                 (set! pos (+ a_home (vec2 (* (- s (fl 0 50)) (fl 7)) (fl 0))))
                 (set! vel (vec2 (* (- (fract (* s "7.3")) (fl 0 50)) "30.0")
                                 (- (+ "46.0" (* s "52.0")))))
                 (set! life (+ "0.6" (* (fract (* s "3.7")) "0.9")))
                 (set! seed (fract (+ seed "0.6180339"))))
                ((set! vel (+ a_vel
                              (vec2 (* (sin (+ (* u_time (fl 3)) (* seed "40.0")))
                                       (* "16.0" u_dt))
                                    (* "150.0" u_dt))))
                 (set! vel (* vel (max (- (fl 1) (* (fl 0 30) u_dt)) (fl 0))))
                 (set! pos (+ a_pos (* vel u_dt)))))
       (set! v_pos pos)
       (set! v_vel vel)
       (set! v_home a_home)
       (set! v_meta (vec3 a_meta.x life seed))
       (set! gl_Position (vec4 (fl 0) (fl 0) (fl 0) (fl 1)))))
   '((precision mediump float)
     (define (main) void
       (set! gl_FragColor (vec4 (fl 0) (fl 0) (fl 0) (fl 1)))))))

(define ember-draw
  (fx-program!
   '((attribute vec2 a_pos)
     (attribute vec2 a_vel)
     (attribute vec2 a_home)
     (attribute vec3 a_meta)
     (uniform float front)
     (varying float v_life)
     (varying float v_gate)
     (varying float v_seed)
     (define (main) void
       (local float w (- front a_meta.x))
       (local float gate (* (step (fl 0) w) (- (fl 1) (smoothstep "60.0" "200.0" w))))
       (local vec2 c (vec2 (- (* (/ a_pos.x (fl 1120)) (fl 2)) (fl 1))
                           (- (fl 1) (* (/ a_pos.y (fl 760)) (fl 2)))))
       (set! gl_Position (vec4 c (fl 0) (fl 1)))
       (set! gl_PointSize (+ (fl 1 20) (* a_meta.y (fl 2 60))))
       (set! v_life a_meta.y)
       (set! v_gate gate)
       (set! v_seed a_meta.z)))
   '((precision mediump float)
     (varying float v_life)
     (varying float v_gate)
     (varying float v_seed)
     (uniform float time)
     (define (main) void
       (if (< v_gate (fl 0 02)) (discard))
       (local vec2 d (- gl_PointCoord (vec2 (fl 0 50) (fl 0 50))))
       (local float r2 (dot d d))
       (if (> r2 (fl 0 25)) (discard))
       (local float soft (- (fl 1) (* r2 (fl 4))))
       (local float flick (+ (fl 0 70) (* (fl 0 30) (sin (+ (* time "27.0") (* v_seed "50.0"))))))
       (local vec3 c (mix (vec3 (fl 0 85) (fl 0 22) (fl 0 02))
                          (vec3 (fl 1) (fl 0 66) (fl 0 20))
                          (smoothstep (fl 0 20) (fl 1) v_life)))
       (set! gl_FragColor
             (vec4 (* (* c flick) (+ (fl 1) (* "1.4" (smoothstep (fl 0 60) (fl 1) v_life))))
                   (* (* v_gate soft) (smoothstep (fl 0) (fl 0 30) v_life))))))))

;; ================= WORD: GOETEIA text particles (hero.ss) =============
;; the physics IS the vertex shader: as u_asm rises the spring to the
;; text home engages, so the frozen dots let go of the lattice and fly in
(define word-update
  (fx-tf-program!
   '((attribute vec2 a_pos)
     (attribute vec2 a_vel)
     (attribute vec2 a_homeg)
     (attribute vec2 a_homei)
     (attribute vec2 a_hive)
     (attribute float a_seed)
     (uniform float u_dt)
     (uniform float u_t)
     (uniform float u_grip)             ; 0 = free (rest at hive), 1 = spring on
     (uniform float u_form)             ; 0 = dispersed at hive, 1 = formed
     (uniform float u_word)             ; 0 = GOETEIA, 1 = IGROPYR
     (varying vec2 v_pos)
     (varying vec2 v_vel)
     (varying vec2 v_homeg)
     (varying vec2 v_homei)
     (varying vec2 v_hive)
     (varying float v_seed)
     (define (main) void
       (local vec2 wh (mix a_homeg a_homei u_word))
       (local vec2 target (mix a_hive wh u_form))
       (set! target (+ target
                       (* (vec2 (sin (+ (* u_t "1.3") (* a_seed "6.28")))
                                (cos (+ (* u_t "1.7") (* a_seed "6.28"))))
                          "0.8")))
       (local vec2 spring (* (- target a_pos) (* (fl 24) u_grip)))
       (local vec2 vel (* (+ a_vel (* spring u_dt))
                          (max (- (fl 1) (* (fl 8) u_dt)) (fl 0))))
       (set! v_pos (+ a_pos (* vel u_dt)))
       (set! v_vel vel)
       (set! v_homeg a_homeg)
       (set! v_homei a_homei)
       (set! v_hive a_hive)
       (set! v_seed a_seed)
       (set! gl_Position (vec4 (fl 0) (fl 0) (fl 0) (fl 1)))))
   '((precision mediump float)
     (define (main) void
       (set! gl_FragColor (vec4 (fl 0) (fl 0) (fl 0) (fl 1)))))))

(define word-draw
  (fx-program!
   '((attribute vec2 a_pos)
     (attribute vec2 a_vel)
     (attribute vec2 a_homeg)
     (attribute vec2 a_homei)
     (attribute vec2 a_hive)
     (attribute float a_seed)
     (uniform float u_word)
     (uniform float u_alpha)
     (varying float v_hx)
     (varying float v_speed)
     (varying float v_word)
     (define (main) void
       (set! gl_Position (vec4 (- (* (/ a_pos.x (fl 1120)) (fl 2)) (fl 1))
                               (- (fl 1) (* (/ a_pos.y (fl 760)) (fl 2)))
                               (fl 0) (fl 1)))
       (set! gl_PointSize (+ (fl 2 40) (* a_seed (fl 0 90))))
       (local vec2 wh (mix a_homeg a_homei u_word))
       (set! v_hx (/ wh.x (fl 1120)))
       (set! v_speed (length a_vel))
       (set! v_word u_word)))
   '((precision mediump float)
     (varying float v_hx)
     (varying float v_speed)
     (varying float v_word)
     (uniform float u_alpha)
     (define (main) void
       (local vec2 pc (- gl_PointCoord (vec2 (fl 0 50) (fl 0 50))))
       (local float d2 (dot pc pc))
       ;; GOETEIA is lapis->azure; IGROPYR is the igropyr site's orange->amber
       (local vec3 blue (mix (vec3 (fl 0 08) (fl 0 31) (fl 0 77))
                             (vec3 (fl 0 28) (fl 0 53) (fl 0 93)) v_hx))
       (local vec3 warm (mix (vec3 (fl 0 91) (fl 0 35) (fl 0 05))
                             (vec3 (fl 1) (fl 0 66) (fl 0 20)) v_hx))
       (local vec3 c (mix blue warm v_word))
       ;; flight makes them glint toward a lighter tint of their own hue
       (local vec3 glint (mix (vec3 (fl 0 70) (fl 0 82) (fl 1))
                              (vec3 (fl 1) (fl 0 88) (fl 0 60)) v_word))
       (set! c (mix c glint (min (* v_speed "0.0035") (fl 0 65))))
       (local float hot (+ (fl 1) (* "0.6" (smoothstep "40.0" "260.0" v_speed))))
       (set! gl_FragColor
             (vec4 (* c hot) (* u_alpha (- (fl 1) (smoothstep (fl 0 04) (fl 0 25) d2)))))))))

;; ================= HDR bloom (fire.ss) ================================
(define scene-t (fx-target-hdr! 1120 760))
(define glow-a (fx-target! 560 380))
(define glow-b (fx-target! 560 380))

(define bright-q
  (fx-fullscreen!
   '((precision mediump float)
     (uniform sampler2D u_scene)
     (uniform vec2 u_texel)
     (define (main) void
       (local vec2 uv (* gl_FragCoord.xy u_texel))
       (local vec4 c (texture2D u_scene uv))
       (local float l (dot c.rgb (vec3 "0.2126" "0.7152" "0.0722")))
       (set! gl_FragColor (vec4 (* c.rgb (* c.a (smoothstep "1.0" "2.2" l))) (fl 1)))))))

(define blur-q
  (fx-fullscreen!
   '((precision mediump float)
     (uniform sampler2D u_src)
     (uniform vec2 u_texel)
     (uniform vec2 u_dir)
     (define (tap (vec2 uv) (float o) (float w)) vec3
       (local vec4 c (texture2D u_src (+ uv (* (* u_dir u_texel) o))))
       (return (* c.rgb w)))
     (define (main) void
       (local vec2 uv (* gl_FragCoord.xy u_texel))
       (local vec3 acc (tap uv (fl 0) "0.227027"))
       (set! acc (+ acc (tap uv (fl 1) "0.1945946")))
       (set! acc (+ acc (tap uv (- (fl 1)) "0.1945946")))
       (set! acc (+ acc (tap uv (fl 2) "0.1216216")))
       (set! acc (+ acc (tap uv (- (fl 2)) "0.1216216")))
       (set! acc (+ acc (tap uv (fl 3) "0.054054")))
       (set! acc (+ acc (tap uv (- (fl 3)) "0.054054")))
       (set! acc (+ acc (tap uv (fl 4) "0.016216")))
       (set! acc (+ acc (tap uv (- (fl 4)) "0.016216")))
       (set! gl_FragColor (vec4 acc (fl 1)))))))

(define comp-q
  (fx-fullscreen!
   '((precision mediump float)
     (uniform sampler2D u_scene)
     (uniform sampler2D u_glow)
     (uniform vec2 u_texel)
     (define (main) void
       (local vec2 uv (* gl_FragCoord.xy u_texel))
       (local vec4 c (texture2D u_scene uv))
       (local vec4 g (texture2D u_glow uv))
       (local vec3 sum (+ c.rgb (* g.rgb "1.15")))
       (local float mx (max (max sum.r sum.g) sum.b))
       (set! sum (/ sum (max mx (fl 1))))
       (local float ga (dot g.rgb (vec3 "0.5" "0.35" "0.15")))
       (set! gl_FragColor (vec4 sum (clamp (+ c.a (* ga "0.9")) (fl 0) (fl 1))))))))

(define (glow-pass! q tgt tex setup)
  (if tgt (fx-bind-target! tgt) (fx-bind-canvas!))
  (fx-fullscreen-use! q 0.0)
  (cmd-bind-texture! 0 tex)
  (setup (fx-quad-program q))
  (fx-fullscreen-draw! q))

;; ================= ember state (fire.ss) ==============================
(define EMB (fx-alloc! (* NEMBER 36)))
(let seedp ((i 0))
  (when (< i NEMBER)
    (let* ((p (%fl->fx (fl* (rnd) (fixnum->flonum npoints))))
           (src (+ POS (* p 16)))
           (o (+ EMB (* i 36))))
      (%mem-f32-set! o (%mem-f32-ref src))
      (%mem-f32-set! (+ o 4) (%mem-f32-ref (+ src 4)))
      (%mem-f32-set! (+ o 8) 0.0)
      (%mem-f32-set! (+ o 12) 0.0)
      (%mem-f32-set! (+ o 16) (%mem-f32-ref src))
      (%mem-f32-set! (+ o 20) (%mem-f32-ref (+ src 4)))
      (%mem-f32-set! (+ o 24) (%mem-f32-ref (+ src 8)))
      (%mem-f32-set! (+ o 28) (rnd))
      (%mem-f32-set! (+ o 32) (rnd)))
    (seedp (+ i 1))))

;; ================= buffers ============================================
(define fuse-buf (fx-buffer!))
(define fill-buf (fx-buffer!))
(define emb-a (fx-buffer!))
(define emb-b (fx-buffer!))
(define word-a (fx-buffer!))
(define word-b (fx-buffer!))
(cmd-begin!)
(cmd-bind-buffer! fuse-buf) (cmd-buffer-data! POS (* npoints 16))
(cmd-bind-buffer! fill-buf) (cmd-buffer-data! FILLV (* nfillv 20))
(cmd-bind-buffer! emb-a) (cmd-buffer-data! EMB (* NEMBER 36))
(cmd-bind-buffer! emb-b) (cmd-buffer-data! EMB (* NEMBER 36))
(cmd-bind-buffer! word-a) (cmd-buffer-data! WST (* pool 44))
(cmd-bind-buffer! word-b) (cmd-buffer-data! WST (* pool 44))
(cmd-flush!)

;; ================= the timeline =======================================
;; fire.ss's pace: tw = t*PACE, front = tw/CYCLE*TRAVEL
(define CYCLE 8.5)
(define TRAVEL (fl+ maxd 380.0))
(define PACE 1.4)
(define FIRE-END (fl/ CYCLE PACE))          ; ashes gone by here (~6.1s)
(define PAUSE 1.0)                        ; ashes gone -> ice starts (was 3s)
(define ICE-START (fl+ FIRE-END PAUSE))
(define ICE-DUR 5.5)                      ; the line reaches the far corner here
(define ICE-SPEED (fl/ maxd ICE-DUR))     ; front-distance per second
(define ICE-LAG (fl* ICE-SPEED 1.0))      ; cells freeze one second behind it
(define ICE-CAP (fl+ maxd (fl+ ICE-LAG 250.0)))    ; grow until the last cell fills
(define ICE-HOLD (fl+ 1.2 (fl/ 250.0 ICE-SPEED)))  ; front-done -> everything frozen
(define WORD-START (fl+ ICE-START (fl+ ICE-DUR ICE-HOLD)))
;; the word era, relative to WORD-START: assemble GOETEIA, hold, disperse,
;; gap, assemble IGROPYR, hold, disperse, gap -- then the whole cycle loops
(define A-IN 2.6) (define A-HOLD 2.6) (define A-OUT 1.6) (define GAP1 0.7)
(define B-IN 2.4) (define B-HOLD 2.6) (define B-OUT 1.6) (define GAP2 1.2)
(define WA1 A-IN)                          ; GOETEIA formed
(define WA2 (fl+ WA1 A-HOLD))              ; start dispersing GOETEIA
(define WA3 (fl+ WA2 A-OUT))               ; GOETEIA dispersed
(define WA4 (fl+ WA3 GAP1))                ; start assembling IGROPYR
(define WA5 (fl+ WA4 B-IN))                ; IGROPYR formed
(define WA6 (fl+ WA5 B-HOLD))              ; start dispersing IGROPYR
(define WA7 (fl+ WA6 B-OUT))               ; IGROPYR dispersed
(define WORD-DUR (fl+ WA7 GAP2))
(define TOTAL (fl+ WORD-START WORD-DUR))   ; one full loop

(define (clamp01 x) (if (fl<? x 0.0) 0.0 (if (fl<? 1.0 x) 1.0 x)))
(define (seg a b w) (clamp01 (fl/ (fl- w a) (fl- b a))))  ; ramp 0->1 over [a,b]

;; the word "form" factor (0 dispersed at hive <-> 1 formed) at word-time w
(define (word-form w)
  (cond ((fl<? w WA1) (seg 0.0 WA1 w))            ; GOETEIA assemble
        ((fl<? w WA2) 1.0)                        ; hold
        ((fl<? w WA3) (fl- 1.0 (seg WA2 WA3 w)))  ; disperse
        ((fl<? w WA4) 0.0)                        ; gap
        ((fl<? w WA5) (seg WA4 WA5 w))            ; IGROPYR assemble
        ((fl<? w WA6) 1.0)                        ; hold
        ((fl<? w WA7) (fl- 1.0 (seg WA6 WA7 w)))  ; disperse
        (else 0.0)))
;; which word (0 GOETEIA, 1 IGROPYR); flips in the dispersed gap between them
(define (word-which w) (if (fl<? w (fl+ WA3 (fl* GAP1 0.5))) 0.0 1.0))
(define cyc-base 0.0)

(define embufs (cons emb-a emb-b))
(define wbufs (cons word-a word-b))

(fx-loop!
 (lambda (t dt)
   (let ((dtc (if (fl<? dt 0.05) dt 0.05)))
     ;; loop the whole sequence: wrap the clock at TOTAL. The dispersed
     ;; state targets the hive points, so the dots are already home at the
     ;; seam and the next cycle starts clean without any buffer reset.
     (when (fl<? (fl+ cyc-base TOTAL) t) (set! cyc-base (fl+ cyc-base TOTAL)))
     ;; ---- phase-driven controls ----
     (let* ((tc (fl- t cyc-base))
            (firing (fl<? tc FIRE-END))
            (tw (let ((x (fl* tc PACE))) (if (fl<? CYCLE x) CYCLE x)))
            (front (fl* (fl/ tw CYCLE) TRAVEL))
            (fade (clamp01 (fl- 1.0 (fl/ (fl- front (fl+ maxd 60.0)) 300.0))))
            (ice (if (fl<? tc ICE-START) 0.0
                     (let ((x (fl* ICE-SPEED (fl- tc ICE-START))))
                       (if (fl<? ICE-CAP x) ICE-CAP x))))
            (wt (fl- tc WORD-START))              ; word-era time (<0 before it)
            (in-word (fl<? 0.0 wt))
            (u-grip (if in-word 1.0 0.0))
            (u-form (if in-word (word-form wt) 0.0))
            (u-word (if in-word (word-which wt) 0.0))
            ;; the hive fades out as the first word (GOETEIA) assembles
            (hive-a (if in-word (clamp01 (fl- 1.0 (fl/ wt A-IN))) 1.0)))
       ;; ---- step the GPU particle systems ----
       (when firing
         (fx-use! ember-update (car embufs))
         (fx-uniform! ember-update 'u_dt dtc)
         (fx-uniform! ember-update 'u_time tw)
         (cmd-tf-buffer! (cdr embufs))
         (cmd-tf-begin!) (cmd-draw-arrays! GL-POINTS 0 NEMBER) (cmd-tf-end!))
       (fx-use! word-update (car wbufs))
       (fx-uniform! word-update 'u_dt dtc)
       (fx-uniform! word-update 'u_t tc)
       (fx-uniform! word-update 'u_grip u-grip)
       (fx-uniform! word-update 'u_form u-form)
       (fx-uniform! word-update 'u_word u-word)
       (cmd-tf-buffer! (cdr wbufs))
       (cmd-tf-begin!) (cmd-draw-arrays! GL-POINTS 0 pool) (cmd-tf-end!)
       ;; ---- render the scene into the HDR target ----
       (cmd-unbind-texture! 0)
       (cmd-unbind-texture! 1)
       (fx-bind-target! scene-t)
       (cmd-blend! 'alpha)
       (cmd-clear! 0.0 0.0 0.0 0.0)
       (cond
        ;; movement 1: fire + embers
        (firing
         (fx-use! fire-p fuse-buf)
         (fx-uniform! fire-p 'front front)
         (fx-uniform! fire-p 'time tw)
         (fx-uniform! fire-p 'fade fade)
         (cmd-draw-arrays! GL-POINTS 0 npoints)
         (fx-use! ember-draw (cdr embufs))
         (fx-uniform! ember-draw 'front front)
         (fx-uniform! ember-draw 'time tw)
         (cmd-draw-arrays! GL-POINTS 0 NEMBER))
        ;; movements 2-5: ice + frost, then GOETEIA and IGROPYR
        ((fl<? ICE-START tc)
         (when (fl<? 0.004 hive-a)
           ;; the cells frost over first (behind the lines)
           (when (> nfillv 0)
             (fx-use! frost-p fill-buf)
             (fx-uniform! frost-p 'ice ice)
             (fx-uniform! frost-p 'lag ICE-LAG)
             (fx-uniform! frost-p 'time tc)
             (fx-uniform! frost-p 'alpha hive-a)
             (cmd-draw-arrays! GL-TRIANGLES 0 nfillv))
           ;; then the ice lines on top
           (fx-use! ice-p fuse-buf)
           (fx-uniform! ice-p 'ice ice)
           (fx-uniform! ice-p 'time tc)
           (fx-uniform! ice-p 'alpha hive-a)
           (cmd-draw-arrays! GL-POINTS 0 npoints))
         (when (fl<? 0.004 u-form)
           (fx-use! word-draw (cdr wbufs))
           (fx-uniform! word-draw 'u_word u-word)
           (fx-uniform! word-draw 'u_alpha u-form)
           (cmd-draw-arrays! GL-POINTS 0 pool))))
       ;; ---- bloom: what burns past white becomes a halo ----
       (cmd-blend! 'off)
       (glow-pass! bright-q glow-a (fx-target-texture scene-t)
                   (lambda (p) (fx-uniform! p 'u_scene 0)
                     (fx-uniform! p 'u_texel (fl/ 1.0 560.0) (fl/ 1.0 380.0))))
       (glow-pass! blur-q glow-b (fx-target-texture glow-a)
                   (lambda (p) (fx-uniform! p 'u_src 0) (fx-uniform! p 'u_dir 1.0 0.0)
                     (fx-uniform! p 'u_texel (fl/ 1.0 560.0) (fl/ 1.0 380.0))))
       (glow-pass! blur-q glow-a (fx-target-texture glow-b)
                   (lambda (p) (fx-uniform! p 'u_src 0) (fx-uniform! p 'u_dir 0.0 1.0)
                     (fx-uniform! p 'u_texel (fl/ 1.0 560.0) (fl/ 1.0 380.0))))
       (glow-pass! comp-q #f (fx-target-texture scene-t)
                   (lambda (p) (cmd-bind-texture! 1 (fx-target-texture glow-a))
                     (fx-uniform! p 'u_scene 0) (fx-uniform! p 'u_glow 1)
                     (fx-uniform! p 'u_texel (fl/ 1.0 1120.0) (fl/ 1.0 760.0))))
       (when firing (set! embufs (cons (cdr embufs) (car embufs))))
       (set! wbufs (cons (cdr wbufs) (car wbufs)))))))
