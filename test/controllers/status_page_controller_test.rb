require "test_helper"

class StatusPageControllerTest < ActionDispatch::IntegrationTest
  setup do
    @org = Organization.create!(name: "Acme Cloud Services", slug: "acme-cloud")
  end

  test "bare /status redirects to the configured platform organization status page" do
    previous = ENV["PLATFORM_STATUS_SLUG"]
    ENV["PLATFORM_STATUS_SLUG"] = @org.slug

    get public_status_url

    assert_redirected_to org_public_status_url(org_slug: @org.slug)
  ensure
    ENV["PLATFORM_STATUS_SLUG"] = previous
  end

  test "should get organization-specific tenant public status page by slug" do
    get org_public_status_url(org_slug: @org.slug)
    assert_response :success
    assert_select "div", text: "Acme Cloud Services Status"
  end

  test "status page structured metadata escapes tenant controlled names" do
    hostile = Organization.create!(name: "</script><script>alert(1)</script>", slug: "hostile")

    get org_public_status_url(org_slug: hostile.slug)

    assert_response :success
    assert_no_match %r{</script><script>alert\(1\)</script>}, response.body
    assert_includes response.body, "\\u003c/script\\u003e\\u003cscript\\u003ealert(1)\\u003c/script\\u003e"
  end
end
