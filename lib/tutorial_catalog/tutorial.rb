# frozen_string_literal: true

module TutorialCatalog
  # One video, resolved for one locale.
  #
  # `number` is for display and ordering only. Renumbering happens when the
  # curriculum is reorganised, so identity is always `slug`.
  #
  # `page_key` is the first page this teaches, as "controller#action" — enough
  # for a deep link to land somewhere sensible. Nil for a leaf that teaches no
  # page of ours, which is legitimate: a tutorial about another site, or about a
  # control present everywhere.
  #
  # `url`, `poster`, `thumb`, `captions`, `version` and `duration` are nil
  # unless the video is watchable — and `poster`, `thumb`, `captions` and
  # `duration` may be nil even then, because the publish step only records what
  # it actually found.
  #
  # `thumb` is the poster at row size: a few kilobytes against the poster's few
  # hundred, for the surfaces that show a frame beside a title rather than
  # behind a player. A list of four posters is two megabytes of picture for
  # 40px of screen, which is the whole reason the two are separate fields.
  #
  # `references` is the other leaves this one hands off to, each with the window
  # in THIS file's timeline where the handoff is spoken:
  # `[{ "slug" => ..., "at" => 27.44, "until" => 42.56 }]`. Empty for a video
  # that points at nothing, which is nearly all of them. The seconds belong to
  # the rendered file, so on a borrowed render they are the fallback locale's.
  #
  # `locale` is the reader's language: the one the title, the chapter label and
  # everything else on the row were resolved for. `media_locale` is the language
  # of the file behind `url`, which is the same thing until the catalog falls
  # back — a leaf rendered in English but not yet in Dutch is watchable for a
  # Dutch reader, in English. Keeping the two apart is what lets a caption track
  # declare the language it is actually in, and a row say so out loud.
  Tutorial = Data.define(
    :slug, :number, :title, :scope,
    :chapter_number, :chapter_title, :subchapter_number, :subchapter_title,
    :locale, :page_key, :tab, :tracks, :status,
    :url, :poster, :thumb, :captions, :version, :duration,
    :prev_slug, :next_slug, :media_locale, :references
  ) do
    # Defaults to `locale`, so every caller that does not care about the
    # distinction — and every one written before it existed — keeps working and
    # still reads a meaningful value rather than a nil.
    def initialize(media_locale: nil, references: nil, thumb: nil, **rest)
      super(media_locale: media_locale || rest[:locale], references: references || [], thumb: thumb, **rest)
    end

    def watchable? = status == :watchable
    def planned? = status == :planned

    # True when this plays in a language the reader did not ask for.
    def fallback_media? = watchable? && media_locale.to_s != locale.to_s
  end
end
