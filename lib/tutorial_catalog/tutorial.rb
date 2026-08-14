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
  # `url`, `poster`, `captions`, `version` and `duration` are nil unless the
  # video is watchable — and `poster`, `captions` and `duration` may be nil even
  # then, because the publish step only records what it actually found.
  Tutorial = Data.define(
    :slug, :number, :title, :scope,
    :chapter_number, :chapter_title, :subchapter_number, :subchapter_title,
    :locale, :page_key, :tab, :tracks, :status,
    :url, :poster, :captions, :version, :duration,
    :prev_slug, :next_slug
  ) do
    def watchable? = status == :watchable
    def planned? = status == :planned
  end
end
