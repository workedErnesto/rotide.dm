// rotide.dm preview driver. Runs in its own WKContentWorld: the document's own scripts are blocked by the page
// policy, and nothing in the page can reach these functions or the message handler.
(() => {
  // WKWebView (macOS) or WebView2 (Windows).
  const post = (message) => window.webkit?.messageHandlers?.rotide
    ? window.webkit.messageHandlers.rotide.postMessage(message)
    : window.chrome?.webview?.postMessage(message);
  const content = () => document.getElementById("content");

  function decorate() {
    for (const block of content().querySelectorAll(".highlight")) {
      if (block.querySelector(".copy-code")) continue;
      const button = document.createElement("button");
      button.className = "copy-code";
      button.type = "button";
      button.textContent = "копировать";
      button.setAttribute("aria-label", "копировать код");
      button.addEventListener("click", (event) => {
        event.preventDefault();
        post({ type: "copy", text: block.querySelector("code")?.innerText ?? "" });
        button.textContent = "скопировано";
        button.classList.add("done");
        clearTimeout(button._reset);
        button._reset = setTimeout(() => { button.textContent = "копировать"; button.classList.remove("done"); }, 1600);
      });
      block.appendChild(button);
    }
    for (const box of content().querySelectorAll("li > input[type=checkbox]")) box.tabIndex = -1;
  }

  // The heading whose top passed the upper quarter of the viewport is the current one.
  let current = null;
  let pending = false;
  function reportHeading() {
    pending = false;
    const anchors = content().querySelectorAll("a.anchor");
    const line = window.innerHeight * 0.25;
    let found = anchors.length ? anchors[0].id : null;
    for (const anchor of anchors) {
      if (anchor.parentElement.getBoundingClientRect().top - line <= 0) found = anchor.id; else break;
    }
    if (window.innerHeight + window.scrollY >= document.documentElement.scrollHeight - 2 && anchors.length) {
      const last = anchors[anchors.length - 1];
      if (last.parentElement.getBoundingClientRect().top < window.innerHeight) found = last.id;
    }
    if (found !== current) { current = found; post({ type: "heading", id: found }); }
  }
  addEventListener("scroll", () => { if (!pending) { pending = true; requestAnimationFrame(reportHeading); } }, { passive: true });
  addEventListener("resize", () => requestAnimationFrame(reportHeading));

  const reduced = () => matchMedia("(prefers-reduced-motion: reduce)").matches;

  window.rotide = {
    update(html) {
      const y = window.scrollY;
      content().innerHTML = html;
      decorate();
      window.scrollTo(0, y);
      requestAnimationFrame(reportHeading);
    },
    scrollTo(id, animated) {
      const target = document.getElementById(id);
      if (!target) return false;
      const element = target.classList.contains("anchor") ? target.parentElement : target;
      element.scrollIntoView({ behavior: animated && !reduced() ? "smooth" : "auto", block: "start" });
      return true;
    },
    scrollFraction(fraction) {
      const max = document.documentElement.scrollHeight - window.innerHeight;
      window.scrollTo(0, Math.max(0, max * fraction));
    },
    selectionText() { return String(window.getSelection() ?? ""); },
  };

  decorate();
  requestAnimationFrame(reportHeading);
  post({ type: "ready" });
})();
