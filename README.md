# tutorial_catalog

Answers **what teaches this page** from two sources with different authorities.

| | authority | changes |
| --- | --- | --- |
| curriculum (`tutorials.yml`) | what tutorials exist, where each belongs | committed; only on deploy |
| publish manifest (`manifest.json`) | which of them actually play, and from where | written onto a live mount by a publish step |

Plain Ruby — no Rails, no database, no notion of a request. Paths and the
journey source are injected; the route set is passed in when you want anchors
validated.

```ruby
catalog = TutorialCatalog::Catalog.new(
  curriculum_path: "config/tutorials.yml",
  tours_path:      "config/tutorial_tours.yml",
  manifest_path:   "public/tutorials/manifest.json",
  journeys:        -> { TurboTour.journeys }
)

catalog.for_page("prospects#show", locale: "nl")        # => [Tutorial], course order
catalog.tours_for_page("product_wizard#show", step: "market", locale: "en")
catalog.all(locale: "en")
catalog.find("create-an-icp", locale: "en")
catalog.problems(known_routes: routes)                  # => [Problem]
```

## Locale is part of every question

There is no "any locale" query, so an English video cannot leak to a Dutch
reader. A leaf whose `locales:` omits the requested one is **absent**, not shown
as coming soon — the curriculum is saying that video will never exist in that
language, and promising it anyway would be a lie. Titles are the exception: a
missing translation falls back to English, because a row with no words is worse
than a row in the wrong language.

## The two files fail differently, on purpose

A broken curriculum **raises** — it is committed and CI-checked, so a bad one is
a deploy bug, and an empty library looks like a product that teaches nothing.

A broken manifest is **treated as absent and retried** — it is written onto a
live mount, so a truncated read is an ordinary race. Briefly showing a landing
video as planned beats a 500 on every page with a help menu.

## Development

```sh
bundle install
bundle exec rspec
```
