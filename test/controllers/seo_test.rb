require "test_helper"

class SeoTest < ActionDispatch::IntegrationTest
  setup do
    @listed = Organization.create!(name: "Northwind", slug: "northwind")
    @unlisted = Organization.create!(name: "Private Co", slug: "private-co", status_page_indexable: false)
  end

  test "status pages are indexable by default so customers can find them" do
    get org_public_status_url(org_slug: @listed.slug)

    assert_response :success
    assert_select "meta[name=robots]", count: 0
  end

  test "a tenant can opt its status page out of search" do
    get org_public_status_url(org_slug: @unlisted.slug)

    assert_response :success
    assert_select "meta[name=robots][content*=noindex]"
  end

  test "status pages declare a canonical url" do
    get org_public_status_url(org_slug: @listed.slug)

    assert_select "link[rel=canonical]"
  end

  test "status pages use the dedicated social preview image" do
    get org_public_status_url(org_slug: @listed.slug)

    assert_response :success
    assert_select "meta[property='og:image'][content='http://www.example.com/og/statuspulse-card.png']"
    assert_select "meta[property='og:image:alt']"
    assert_select "meta[name='twitter:card'][content='summary_large_image']"
    assert_select "meta[name='twitter:image'][content='http://www.example.com/og/statuspulse-card.png']"
    assert_select "meta[name='twitter:image:alt']"
  end

  test "the sitemap lists public landing, SEO pages, and opted-in status pages only" do
    get sitemap_url

    assert_response :success
    assert_equal "application/xml", response.media_type
    assert_includes response.body, org_public_status_url(org_slug: @listed.slug)
    assert_not_includes response.body, org_public_status_url(org_slug: @unlisted.slug)
    assert_not_includes response.body, signup_url
    assert_includes response.body, root_url
    assert_includes response.body, "http://www.example.com/uptime-monitoring-for-agencies"
    assert_includes response.body, "http://www.example.com/multi-tenant-uptime-monitoring"
    assert_includes response.body, "http://www.example.com/client-uptime-reports"
  end

  test "the web manifest is routed and served as JSON" do
    get pwa_manifest_url

    assert_response :success
    assert_equal "application/manifest+json", response.media_type

    manifest = JSON.parse(response.body)
    assert_equal "StatusPulse", manifest.fetch("name")
    assert_equal "/", manifest.fetch("start_url")
  end

  test "the service worker route is public JavaScript" do
    get pwa_service_worker_url

    assert_response :success
    assert_equal "text/javascript", response.media_type
  end

  test "the social preview image is a large PNG link card" do
    path = Rails.root.join("public/og/statuspulse-card.png")

    assert path.exist?, "expected #{path} to exist"
    bytes = path.binread
    assert_equal "\x89PNG\r\n\x1a\n".b, bytes.byteslice(0, 8)
    assert_equal [ 1200, 630 ], bytes.byteslice(16, 8).unpack("NN")
  end

  test "signed-in pages carry a noindex directive, not merely a robots.txt disallow" do
    user = @listed.users.create!(
      name: "Ops", email: "ops@northwind.test",
      password: "a-long-enough-password", password_confirmation: "a-long-enough-password",
      role: "admin"
    )
    post login_url, params: { email: user.email, password: "a-long-enough-password" }

    get dashboard_url

    assert_response :success
    assert_select "meta[name=robots][content*=noindex]"
  end

  test "robots.txt points crawlers at the sitemap and keeps them out of the app" do
    body = Rails.root.join("public/robots.txt").read

    assert_match %r{Sitemap: https://statuspulse\.org/sitemap\.xml}, body
    assert_match(/Disallow: \/dashboard/, body)
    assert_match(/Disallow: \/login/, body)
    assert_no_match(/^Disallow: \/up$/, body)
    assert_match(/^Disallow: \/up\$$/, body)
  end
end
