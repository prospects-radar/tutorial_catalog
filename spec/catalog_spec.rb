# frozen_string_literal: true

require "spec_helper"

# The seam every surface reads through. These assert what a caller can observe —
# never that a file was parsed once rather than twice, or that a mutex was taken.
RSpec.describe TutorialCatalog::Catalog do
  def build(curriculum: "curriculum.yml", tours: "tours.yml", manifest: "manifest.json", journeys: default_journeys)
    described_class.new(
      curriculum_path: fixture(curriculum),
      tours_path: tours && fixture(tours),
      manifest_path: manifest && fixture(manifest),
      journeys: journeys
    )
  end

  # Shaped like TurboTour.journeys: key => steps, each step's title a locale hash.
  def default_journeys
    {
      "product_wizard_market_help" => [ { "title" => { "en" => "Market", "nl" => "Markt" } } ],
      "prospects_index_help" => [ { "title" => { "en" => "Prospects", "nl" => "Prospects" } } ],
      "english_only_help" => [ { "title" => { "en" => "English only" } } ]
    }
  end

  describe "#all" do
    it "returns every leaf the locale can see, in course order" do
      numbers = build.all(locale: "en").map(&:number)

      expect(numbers).to eq(%w[1.1.1 1.1.2 1.2.1 1.2.2 2.1.1 2.1.2])
    end

    it "drops a leaf whose declared locales exclude the requested one" do
      slugs = build.all(locale: "nl").map(&:slug)

      expect(slugs).not_to include("english-only")
    end

    it "drops a blocked leaf in every locale" do
      expect(build.all(locale: "en").map(&:slug)).not_to include("blocked-leaf")
      expect(build.all(locale: "nl").map(&:slug)).not_to include("blocked-leaf")
    end

    it "carries the chapter and subchapter labels on every value" do
      leaf = build.all(locale: "en").first

      expect(leaf).to have_attributes(
        chapter_number: 1, chapter_title: "First chapter",
        subchapter_number: "1.1", subchapter_title: "First subchapter"
      )
    end
  end

  describe "titles" do
    it "resolves the requested locale" do
      expect(build.find("published-leaf", locale: "nl").title).to eq("Gepubliceerd")
    end

    it "falls back to English when the locale has no title" do
      expect(build.find("no-dutch-title", locale: "nl").title).to eq("No Dutch title")
    end

    it "never falls back to the slug" do
      expect(build.find("no-dutch-title", locale: "nl").title).not_to include("no-dutch")
    end

    it "reports the locale it resolved for" do
      expect(build.find("published-leaf", locale: "nl").locale).to eq("nl")
    end
  end

  describe "status" do
    it "is watchable when the manifest has the slug in that locale" do
      leaf = build.find("published-leaf", locale: "en")

      expect(leaf).to be_watchable
      expect(leaf.status).to eq(:watchable)
      expect(leaf.url).to eq("/tutorials/published-leaf_en.mp4?v=abc123")
      expect(leaf.duration).to eq(170)
    end

    it "is planned in a locale the manifest does not carry" do
      leaf = build.find("published-leaf", locale: "nl")

      expect(leaf).not_to be_watchable
      expect(leaf.url).to be_nil
      expect(leaf.duration).to be_nil
    end

    it "is planned for a leaf no manifest entry names" do
      expect(build.find("planned-leaf", locale: "en")).not_to be_watchable
    end

    it "leaves duration nil when the manifest entry has none" do
      expect(build.find("no-duration", locale: "en")).to have_attributes(watchable?: true, duration: nil)
    end

    it "ignores a manifest entry with no matching leaf" do
      slugs = build.all(locale: "en").map(&:slug)

      expect(slugs).not_to include("orphan-video")
    end
  end

  describe "an absent or unreadable manifest" do
    it "reports zero watchable videos rather than raising" do
      catalog = build(manifest: nil)

      expect(catalog.all(locale: "en")).to all(satisfy { |t| !t.watchable? })
    end

    it "treats a truncated manifest as absent" do
      catalog = build(manifest: "truncated_manifest.json")

      expect(catalog.all(locale: "en")).to all(satisfy { |t| !t.watchable? })
    end

    it "picks up a manifest that appears after the first read" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "manifest.json")
        catalog = described_class.new(
          curriculum_path: fixture("curriculum.yml"), tours_path: fixture("tours.yml"),
          manifest_path: path, journeys: default_journeys
        )
        expect(catalog.find("published-leaf", locale: "en")).not_to be_watchable

        File.write(path, File.read(fixture("manifest.json")))

        expect(catalog.find("published-leaf", locale: "en")).to be_watchable
      end
    end
  end

  describe "a broken curriculum" do
    it "raises, because that is a deploy bug rather than a race" do
      expect { build(curriculum: "broken_curriculum.yml").all(locale: "en") }
        .to raise_error(TutorialCatalog::CurriculumError)
    end

    it "raises when the curriculum is missing entirely" do
      catalog = described_class.new(curriculum_path: "/nonexistent/tutorials.yml",
                                    tours_path: nil, manifest_path: nil, journeys: {})

      expect { catalog.all(locale: "en") }.to raise_error(TutorialCatalog::CurriculumError)
    end
  end

  describe "course order neighbours" do
    it "leaves prev nil at the first leaf and next nil at the last" do
      first, *, last = build.all(locale: "en")

      expect(first.prev_slug).to be_nil
      expect(last.next_slug).to be_nil
    end

    it "links each leaf to the one either side of it" do
      leaf = build.find("published-leaf", locale: "en")

      expect(leaf).to have_attributes(prev_slug: "first-leaf", next_slug: "no-dutch-title")
    end

    it "computes neighbours within the locale, skipping leaves that locale cannot see" do
      leaf = build.find("no-dutch-title", locale: "nl")

      expect(leaf.next_slug).to eq("planned-leaf")
    end
  end

  describe "#for_page" do
    it "matches on controller#action" do
      slugs = build.for_page("prospects#index", locale: "en").map(&:slug)

      expect(slugs).to contain_exactly("first-leaf", "published-leaf", "english-only")
    end

    it "returns them in course order" do
      expect(build.for_page("prospects#index", locale: "en").map(&:number)).to eq(%w[1.1.1 1.1.2 1.2.2])
    end

    it "carries the tab qualifier through without narrowing the match" do
      leaves = build.for_page("prospects#show", locale: "en")

      expect(leaves.map(&:slug)).to contain_exactly("no-dutch-title")
      expect(leaves.first.tab).to eq("scoring")
    end

    it "is empty for a page nothing anchors to" do
      expect(build.for_page("nowhere#index", locale: "en")).to be_empty
    end

    it "never returns a leaf the locale cannot see" do
      expect(build.for_page("prospects#index", locale: "nl").map(&:slug)).not_to include("english-only")
    end
  end

  describe "#tours_for_page" do
    it "returns tours anchored to the route" do
      expect(build.tours_for_page("prospects#index", locale: "en").map(&:key))
        .to eq(%w[prospects_index_help])
    end

    it "resolves the tour title for the locale" do
      expect(build.tours_for_page("prospects#index", locale: "nl").first.title).to eq("Prospects rondleiding")
    end

    it "omits a tour whose journey does not exist in that locale" do
      expect(build.tours_for_page("prospects#index", locale: "nl").map(&:key))
        .not_to include("english_only_help")
    end

    it "omits a tour the journey source does not know at all" do
      catalog = build(journeys: { "prospects_index_help" => [ { "title" => { "en" => "P" } } ] })

      expect(catalog.tours_for_page("product_wizard#show", step: "market", locale: "en")).to be_empty
    end

    describe "the step qualifier, which does narrow" do
      it "matches when the step is the one anchored" do
        expect(build.tours_for_page("product_wizard#show", step: "market", locale: "en").map(&:key))
          .to eq(%w[product_wizard_market_help])
      end

      it "does not match a different step" do
        expect(build.tours_for_page("product_wizard#show", step: "details", locale: "en")).to be_empty
      end

      it "does not match when no step is given" do
        expect(build.tours_for_page("product_wizard#show", locale: "en")).to be_empty
      end
    end

    it "is empty when no tours file is configured" do
      expect(build(tours: nil).tours_for_page("prospects#index", locale: "en")).to be_empty
    end
  end

  describe "#problems" do
    it "reports an anchor naming a route that does not exist" do
      problems = build.problems(known_routes: [ "prospects#index" ])

      expect(problems.select { |p| p.kind == :unknown_route }.map(&:subject))
        .to include("prospects#show")
    end

    it "treats an unknown route as blocking" do
      problem = build.problems(known_routes: []).find { |p| p.kind == :unknown_route }

      expect(problem.severity).to eq(:error)
    end

    it "reports an anchor inside an internal namespace" do
      problems = build.problems(known_routes: all_fixture_routes)

      expect(problems.map(&:kind)).to include(:internal_namespace)
    end

    it "reports a journey the tours file never anchors" do
      problems = build.problems(known_routes: all_fixture_routes)

      expect(problems.select { |p| p.kind == :unanchored_journey }.map(&:subject))
        .to include("english_only_help")
    end

    it "reports a manifest entry with no matching leaf, as a warning" do
      problem = build.problems(known_routes: all_fixture_routes).find { |p| p.kind == :orphan_video }

      expect(problem).to have_attributes(subject: "orphan-video", severity: :warning)
    end

    it "is quiet about a leaf with no page anchor at all" do
      problems = build.problems(known_routes: all_fixture_routes)

      expect(problems.map(&:kind)).not_to include(:missing_anchor)
    end

    def all_fixture_routes
      %w[prospects#index prospects#show product_wizard#show api/v1/things#index]
    end
  end

  describe "#reload!" do
    it "re-reads a curriculum edited underneath it" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "tutorials.yml")
        FileUtils.cp(fixture("curriculum.yml"), path)
        catalog = described_class.new(curriculum_path: path, tours_path: nil,
                                      manifest_path: nil, journeys: {})
        before = catalog.all(locale: "en").size

        File.write(path, File.read(path).sub("First chapter", "Renamed chapter"))
        catalog.reload!

        expect(catalog.all(locale: "en").size).to eq(before)
        expect(catalog.all(locale: "en").first.chapter_title).to eq("Renamed chapter")
      end
    end
  end
end
