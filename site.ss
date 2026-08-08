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
           " on the server, and "
           (a (@ (href "https://goeteia.dev")) "Goeteia")
           " in the browser.")

        (p "Igropyr began in 2018. Out of love for Scheme, I was looking "
           "for a modern Scheme web server I could actually run in "
           "production — not a proof of concept content to stay in "
           "academia — and I found nothing.")

        (p "Back then, and still today, Scheme web servers stop at raw "
           "string concatenation to build a request and its response. "
           "They lack the modern conveniences — proper JSON responses, "
           "concurrency, asynchrony, and the like — that a real application "
           "backend needs.")

        (p "So I improvised. I tried Apache calling out to CGI. Then, "
           "inspired by Node, I wrote a first thin wrapper over libuv. "
           "That was Igropyr's earliest prototype.")

        (p "In the years that followed I came to know Erlang, and took "
           "its ideas to heart: message passing, and " (em "let it crash")
           ". Around that time " (span (@ (class "quote")) "Swish")
           " had built the earliest Erlang-style system on Chez Scheme — "
           "but its network programming still lived in that same "
           "primitive, string-concatenation world.")

        (p "Swish is what convinced me. Inspired by it, I decided to "
           "rebuild Igropyr from the ground up.")

        (p "Today Igropyr goes further than that Erlang prototype ever "
           "did. When a handler crashes or a request times out, the "
           "server can tell the client that the request went wrong — and "
           "hand the choice back to it: retry, retry with different "
           "parameters, or stop. In practice this shortens how long a "
           "user waits, and it makes server-side failures invisible from "
           "the user's side.")

        (p "And it carries messages as s-expressions themselves: when "
           "both ends speak Scheme, a request and its reply need no codec "
           "at all — the data crosses the wire as it is, exact numbers "
           "intact. Scheme, at last, has a JSON of its own.")

        (p "It even supports continuation-based web programming — the "
           "functional community's most beautiful daydream. It is no fit "
           "for an ordinary form-filling page, but where the work is "
           "strongly transactional it lets a single transaction stretch "
           "across the wire, held open between the server and the remote "
           "client.")

        (p "By now Igropyr carries everything a modern web server is "
           "expected to have: JWT, non-blocking Redis and database "
           "clients, a self-forming cluster, hot code swapping, and even "
           "BLAS-accelerated vector search…")

        (p "Goeteia came from another daydream — writing the front end in "
           "pure Scheme as well. I tried the existing Scheme-to-JavaScript "
           "compilers first, but building on WebAssembly turned out to be "
           "the better foundation — and in the end it cost me nothing on "
           "the JavaScript side either: the same source compiles to both, "
           "so a browser too old for WebAssembly GC still gets the page, "
           "running a JavaScript twin that nobody has to keep in step "
           "because it is generated, never written.")

        (p "Goeteia, for its part, is a compiler just 50 kB, running right "
           "in the browser, and heavily "
           "optimized for 3D. It renders dazzling web effects from Scheme "
           "straight to the page on the fly, or precompiles them for more "
           "speed and optimization, and it supports programming web games. "
           "It also "
           "takes a fresh approach to the DOM — in this "
           "post-virtual-DOM-tree era, a distinctly Scheme one: "
           "macro-based DOM state management, and pretext effects.")

        (p "Goeteia now has gone further than I planned for it. Everything "
           "about it is small — a compile takes a moment, a check needs "
           "no eyes and no graphics card, only arithmetic — and small "
           "things can be run side by side, so it drives its AI pipelines "
           "many at a time. Each one takes a piece of video and lifts out "
           "a skeleton, its textures, its skinning, its motion: work that "
           "used to want a capture stage and someone in a suit, and now "
           "wants only footage.")

        (p "AI is already fluent at the reference imagery — the "
           "designs, the turntables, the motion video; what was missing "
           "was the road from those images to finished 3D. This is that "
           "last piece of the puzzle. And like every AI, it does not "
           "arrive in a single pass; it "
           "closes on its target by going round again, and again, until "
           "the program says it came out right.")

        (p "The project is entirely open source, free for any use — "
           "commercial included. I hope you enjoy it.")

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
