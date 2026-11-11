// Progressive enhancement only; reduced motion and no-JS always show the content.
if (
  !matchMedia("(prefers-reduced-motion: reduce)").matches &&
  !CSS.supports("animation-timeline: view()")
) {
  document.documentElement.classList.add("motion-fallback");
  const observer = new IntersectionObserver(
    (entries) =>
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.remove("awaiting");
          observer.unobserve(entry.target);
        }
      }),
    { threshold: 0.12 },
  );
  document
    .querySelectorAll(
      ".flat .screen, .loan-screens .screen, .trip-steps .screen",
    )
    .forEach((el) => {
      el.classList.add("awaiting");
      observer.observe(el);
    });
}
