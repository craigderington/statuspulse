require "test_helper"

class StatusPageControllerTest < ActionDispatch::IntegrationTest
  setup do
    @org = Organization.create!(name: "Acme Cloud Services", slug: "acme-cloud")
  end

  test "bare /status serves the configured platform organization" do
    previous = ENV["PLATFORM_STATUS_SLUG"]
    ENV["PLATFORM_STATUS_SLUG"] = @org.slug

    get public_status_url

    assert_response :success
  ensure
    ENV["PLATFORM_STATUS_SLUG"] = previous
  end

  test "should get organization-specific tenant public status page by slug" do
    get org_public_status_url(org_slug: @org.slug)
    assert_response :success
    assert_select "div", text: "Acme Cloud Services Status"
  end
end
