// Scroll-triggered reveal — assigns .is-in to .reveal elements as they
// enter the viewport. Pure IntersectionObserver, no library.
(() => {
  const targets = document.querySelectorAll(".feature, .strip-card, .setup__step");
  targets.forEach((el) => el.classList.add("reveal"));

  if (!("IntersectionObserver" in window)) {
    // Fallback: just reveal everything immediately.
    targets.forEach((el) => el.classList.add("is-in"));
    return;
  }

  const io = new IntersectionObserver((entries) => {
    for (const e of entries) {
      if (e.isIntersecting) {
        e.target.classList.add("is-in");
        io.unobserve(e.target);
      }
    }
  }, { rootMargin: "0px 0px -10% 0px", threshold: 0.05 });

  targets.forEach((el) => io.observe(el));
})();

// Hero headline cycler — toggles `.is-on` between the 5 states stacked
// inside `.hero__cycle`. Container is grid-sized to the longest word
// so nothing around it reflows. Loops every 18 s; respects
// prefers-reduced-motion.
(() => {
  const states = document.querySelectorAll(".hero__cycle-state");
  if (!states.length) return;
  if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;

  // States are in DOM order: [active, L0, L1, L2, L3]. We want to
  // start on "active", then walk L0 → L1 → L2 → L3 → back to active.
  const HOLD = 900;       // ms each state stays visible
  const LOOP = 18000;     // ms between full cycles

  let current = 0;        // index of the currently lit state

  function show(next) {
    states[current].classList.remove("is-on");
    states[next].classList.add("is-on");
    current = next;
  }

  function runCycle() {
    // Sequence: active(0) → L0(1) → L1(2) → L2(3) → L3(4) → active(0)
    const order = [1, 2, 3, 4, 0];
    order.forEach((idx, step) => {
      setTimeout(() => show(idx), HOLD * (step + 1));
    });
  }

  setTimeout(runCycle, HOLD);
  setInterval(runCycle, LOOP);
})();

// Live version sync — fetches the latest release from GitHub on load
// and updates the eyebrow, version pill, .dmg filename label and download
// hrefs to match. The HTML still ships with a current hardcoded version
// so anyone behind a firewall (or hitting a rate-limited API) sees a
// correct fallback rather than a blank.
(async () => {
  let version = null;
  let assetUrl = null;

  try {
    const res = await fetch(
      "https://api.github.com/repos/FireBall1725/LayerLens/releases/latest",
      { headers: { Accept: "application/vnd.github+json" } }
    );
    if (res.ok) {
      const data = await res.json();
      const tag = (data.tag_name || "").replace(/^v/, "");
      if (/^\d+\.\d+\.\d+/.test(tag)) {
        version = tag;
        const dmg = (data.assets || []).find((a) => /\.dmg$/i.test(a.name));
        if (dmg) assetUrl = dmg.browser_download_url;
      }
    }
  } catch (_) {
    // Network or API failure — silently keep the hardcoded fallback.
  }

  if (!version) return;

  const fallbackHref =
    `https://github.com/FireBall1725/LayerLens/releases/latest/download/LayerLens-${version}.dmg`;

  document.querySelectorAll("[data-version-target]").forEach((el) => {
    switch (el.dataset.versionTarget) {
      case "eyebrow":
        el.innerHTML = `v${version} &nbsp;·&nbsp; macOS 14+`;
        break;
      case "pill":
        el.textContent = `v${version}`;
        break;
      case "filename":
        el.textContent = `LayerLens-${version}.dmg`;
        break;
      case "href":
        el.href = assetUrl || fallbackHref;
        break;
    }
  });
})();

// Ambient-keys parallax — translates the .page-keys__inner layer at a
// fraction of the page scroll so the keys drift past at their own pace.
// The wrapping .page-keys has overflow:hidden, so the inner's
// translation can run unbounded without growing document height. Each
// key's keyFloat/keyAppear animation composes on top of this parent
// translate without conflict.
(() => {
  const layer = document.querySelector(".page-keys__inner");
  if (!layer) return;
  if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
  // The CSS hides .page-keys below 720px (they fight content on mobile),
  // so don't bother running the listener there either.
  if (window.matchMedia("(max-width: 720px)").matches) return;

  // Apparent scroll speed of the keys vs the page. 1.0 = same as page,
  // 0.5 = half speed (keys appear to "stick around"). Lower is more
  // dramatic. Tuned by feel.
  const SPEED = 0.55;

  let frame = null;
  const update = () => {
    frame = null;
    // Page scrolls at 1.0; layer translates at (1 - SPEED) of scrollY,
    // which makes its content appear to move at SPEED.
    const offset = window.scrollY * (1 - SPEED);
    layer.style.transform = `translate3d(0, ${offset.toFixed(1)}px, 0)`;
  };

  const onScroll = () => {
    if (frame == null) frame = requestAnimationFrame(update);
  };

  window.addEventListener("scroll", onScroll, { passive: true });
  update();
})();
