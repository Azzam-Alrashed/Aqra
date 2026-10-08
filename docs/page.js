// The language toggle of the privacy and support pages (index.html has its own copy, with its titles).
(function () {
  var html = document.documentElement;
  function title(lang) { return document.querySelector('meta[name="title-' + lang + '"]').content; }
  function apply(lang) {
    html.lang = lang;
    html.dir = lang === 'ar' ? 'rtl' : 'ltr';
    document.title = title(lang);
    document.querySelectorAll('[data-lang-toggle]').forEach(function (b) {
      b.textContent = lang === 'ar' ? 'English' : 'العربية';
      b.lang = lang === 'ar' ? 'en' : 'ar';
    });
    try { localStorage.setItem('aqra-lang', lang); } catch (e) {}
  }
  apply(html.lang === 'en' ? 'en' : 'ar');
  document.querySelectorAll('[data-lang-toggle]').forEach(function (b) {
    b.addEventListener('click', function (e) { e.preventDefault(); apply(html.lang === 'ar' ? 'en' : 'ar'); });
  });
})();
