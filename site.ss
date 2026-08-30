;; igropyr.com — the origin-story page, authored in Scheme and rendered by
;; Goeteia. Runs at build time (node rt/run.mjs) and writes index.html:
;; the whole document as static (web html) SXML, its stylesheet as
;; (web css) data. No hand-written HTML or CSS.
(import (web html) (web css) (rnrs))

;; ---- stylesheet, as (web css) data ----
;; one palette in :root; fractional lengths encode the decimal in the
;; second argument as hundredths -- (rem 1 50) is 1.5rem, (rem 1 15) 1.15.
(define styles
 `((:root
    (--bg "#fbf9f6") (--ink "#1c1a17") (--dim "#6b6558")
    (--accent "#e8590c") (--line "#e7e0d6"))

   ("*" (box-sizing border-box))
   ;; the page colour lives on <html> so the fixed z-index:-1 background
   ;; canvas paints above it (root background) yet behind the text
   (html (-webkit-text-size-adjust (pct 100)) (background (var bg)) (overflow-x hidden))
   (body
    (margin 0) (background transparent) (color (var ink))
    (font-family "\"Iowan Old Style\", \"Palatino Linotype\", Palatino, Georgia, serif")
    (line-height (dec 1 70)) (font-size (px 19)))

   ;; the WebGL background: fire -> ice -> GOETEIA, behind everything.
   ;; below the large-screen breakpoint it fills the viewport
   ("#bg"
    (position fixed) (top 0) (left 0) (width (vw 100)) (height (vh 100))
    ;; the canvas buffer is 1120x760; cover keeps that aspect instead of
    ;; stretching (which squished it on tall phone screens)
    (object-fit cover) (object-position center)
    (z-index -1) (pointer-events none) (opacity (dec 0 50)))
   ;; on large screens it shrinks to a block bled off the top-right corner,
   ;; placed like the igropyr site's hero fire
   (@media "(min-width: 1000px)"
     ("#bg" (top "-80px") (right "-120px") (left auto) (bottom auto)
            (width "min(72vw, 1120px)") (height auto) (opacity (dec 0 72))))
   ;; on phones the animation fills the top of the page (aspect kept) like
   ;; the igropyr site's hero, instead of cover-zooming the whole viewport
   (@media "(max-width: 700px)"
     ("#bg" (position absolute) (top 0) (left (pct 50)) (right auto) (bottom auto)
            (transform "translateX(-50%)") (width "160vw") (height auto)
            (object-fit fill)))

   (.wrap (max-width (rem 40)) (margin 0 auto) (position relative) (z-index 1)
          (padding (vh 12) (rem 1 50) (vh 16)))
   (.mark (font-size (rem 2 60)) (color (var accent)) (line-height 1)
          (margin-bottom (rem 1 50)))
   (h1 (font-size (rem 2 75)) (letter-spacing "-0.01em")
       (margin 0 0 (rem 0 25)) (font-weight 600))
   (.kicker
    (font-family "-apple-system, system-ui, \"Segoe UI\", sans-serif")
    (text-transform uppercase) (letter-spacing (em 0 18))
    (font-size (rem 0 72)) (color (var dim)) (margin 0 0 (rem 3)))
   (.rule (width (rem 3)) (height (px 3)) (background (var accent))
          (border 0) (margin 0 0 (rem 2 50)))
   (p (margin 0 0 (rem 1 50)))
   ("p.lead" (font-size (rem 1 15)) (color (var ink)))
   (em (font-style italic))
   (.quote (font-style italic) (color (var dim)))
   ("p a" (color (var accent)) (text-decoration none)
          (border-bottom (px 1) solid (rgba 232 89 12 (dec 0 35))))
   ("p a:hover" (border-bottom-color (var accent)))
   (footer
    (margin-top (rem 5)) (padding-top (rem 1 50))
    (border-top (px 1) solid (var line))
    (font-family "-apple-system, system-ui, \"Segoe UI\", sans-serif")
    (font-size (rem 0 85)) (color (var dim)))
   ("footer a" (color (var accent)) (text-decoration none))
   ("footer a:hover" (text-decoration underline))
   ;; the Goeteia link wears Goeteia's own site colour (lapis)
   ("footer a.gt" (color "#1550c4"))
   ;; stacks "pure Scheme" over "Powered by Goeteia." with both lines left-
   ;; aligned, so "Powered" sits directly under "pure"
   (".foot-stack" (display inline-block) (vertical-align top))
   (@media "(max-width: 480px)"
     (body (font-size (px 18)))
     (h1 (font-size (rem 2 10)))
     (.wrap (padding (vh 8) (rem 1 25) (vh 12))))))

;; ---- the document ----
(define page
  `(html (@ (lang "en"))
     (head
      (meta (@ (charset "utf-8")))
      (meta (@ (name "viewport") (content "width=device-width, initial-scale=1")))
      (link (@ (rel "icon") (type "image/svg+xml") (href "favicon.svg")))
      (title "Igropyr — Origins")
      (meta (@ (name "description")
               (content "How Igropyr began: the search for a Scheme web server built for production, from a libuv prototype to an Erlang-style rebuild.")))
      (style ,(raw (css->string styles))))
     (body
      (canvas (@ (id "bg") (width "1120") (height "760")))
      (main (@ (class "wrap"))
        (div (@ (class "mark")) "λ")
        (h1 "Igropyr")
        (p (@ (class "kicker")) "Origins")
        (hr (@ (class "rule")))

        (p (@ (class "lead"))
           "The Igropyr project contains two parts: "
           (a (@ (href "https://igropyr.dev")) "Igropyr")
           " on the backend, and "
           (a (@ (href "https://goeteia.dev")) "Goeteia")
           " in the browser.")

        (p "I started Igropyr back in 2018 simply because I wanted to "
           "write Scheme. I was hunting for a modern, production-ready "
           "Scheme web server—something that wasn't just an academic "
           "toy—and came up completely empty. Even now, most Scheme web "
           "servers still treat HTTP like glorified string concatenation. "
           "They're missing all the baseline stuff a real backend needs "
           "today: proper JSON handling, real concurrency, async I/O.")

        (p "So I hacked something together. I tried Apache with CGI for a "
           "bit, then looked at Node and wrote a thin wrapper over libuv. "
           "That was the first real prototype.")

        (p "Later on, I fell down the Erlang rabbit hole and got hooked "
           "on its philosophy: message passing and " (em "let it crash")
           ". Around that time, " (span (@ (class "quote")) "Swish")
           " came out with an Erlang-style system on top of Chez Scheme. "
           "It was brilliant, but its network layer was still stuck in "
           "that primitive string-building era. Still, Swish was the push "
           "I needed. It convinced me to tear Igropyr down and rebuild it "
           "from scratch.")

        (p "Today's Igropyr goes a lot further. If a handler crashes or "
           "times out, it doesn't just silently drop the connection; it "
           "tells the client exactly what went wrong and hands back the "
           "steering wheel. The client can retry, tweak parameters, or "
           "bail out. In practice, this hides server-side hiccups from "
           "the user and cuts down wait times. Better yet, it talks "
           "natively in s-expressions. When both ends speak Scheme, you "
           "don't need a codec. Data just crosses the wire exactly as it "
           "is, down to the exact integers. Scheme finally has its own "
           "JSON.")

        (p "It actually pulled off continuation-based web programming, "
           "too—that old pipe dream of the functional programming world. "
           "You wouldn't use it for a simple web form, but for strictly "
           "transactional flows? It's magic. A single transaction can "
           "stretch right across the wire, parked and waiting between the "
           "server and the client. At this point, it's packed with what "
           "you'd expect from a modern backend: JWT, non-blocking DB and "
           "Redis clients, auto-clustering, hot code swapping, and even "
           "BLAS-accelerated vector search.")

        (p "Then there's Goeteia, which came from the itch to write the "
           "frontend in pure Scheme, too. I messed around with "
           "Scheme-to-JS compilers at first, but targeting WebAssembly "
           "ended up being the real answer. And I didn't even lose JS "
           "support in the process: the compiler spits out both from the "
           "same source. If a browser is too old for Wasm GC, it "
           "gracefully falls back to a generated JS twin. You never have "
           "to manually sync them.")

        (p "The Goeteia compiler itself is a tiny 50kB footprint that "
           "runs directly in the browser, heavily dialed in for 3D. It "
           "can render heavy web effects on the fly straight from Scheme, "
           "or precompile them if you need raw speed and game-level "
           "performance. I also took a weird, distinctly Scheme approach "
           "to the DOM. Instead of a heavy virtual DOM tree, it uses "
           "macro-based state management and pretext effects.")

        (p "Lately, Goeteia has kind of outgrown its original scope. "
           "Because everything about it is so small and fast—compiles "
           "take milliseconds, and testing logic requires zero GPU "
           "overhead, just pure math—you can run a ton of instances side "
           "by side. I'm currently using it to drive highly concurrent AI "
           "pipelines. You feed it video footage, and it extracts the "
           "skeleton, textures, skinning, and motion data. Stuff that "
           "used to require a mocap suit and a soundstage now just needs "
           "a raw video file.")

        (p "AI is already great at generating reference art, turntables, "
           "and motion video. The missing link was getting from those "
           "pixels to actual, usable 3D assets. Goeteia is that last "
           "piece of the puzzle. Like any AI workflow, it's not a "
           "one-shot process; it loops, tweaking and converging on the "
           "target until the code decides it's right.")

        (p "Both parts of this project are fully open source and free for "
           "anything, including commercial use. Have fun with it.")

        (footer
          (a (@ (href "https://github.com/guenchi/Igropyr/blob/master/LICENSE")) "MIT")
          " · Built in "
          (span (@ (class "foot-stack"))
            "pure Scheme" (br)
            "Powered by " (a (@ (href "https://goeteia.dev") (class "gt")) "Goeteia") ".")))
      (script (@ (type "module") (src "boot.js")))
      )))

(call-with-output-file "index.html"
  (lambda (p) (display (html->document page) p)))
