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

  test "the sitemap lists the landing page and opted-in status pages only" do
    get sitemap_url

    assert_response :success
    assert_equal "application/xml", response.media_type
    assert_includes response.body, org_public_status_url(org_slug: @listed.slug)
    assert_not_includes response.body, org_public_status_url(org_slug: @unlisted.slug)
    assert_not_includes response.body, signup_url
    assert_includes response.body, root_url
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
  end
end
