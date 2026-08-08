require "test_helper"

class StatusPageControllerTest < ActionDispatch::IntegrationTest
  setup do
    @org = Organization.create!(name: "Acme Cloud Services", slug: "acme-cloud")
  end

  test "should get public status page" do
    get public_status_url
    assert_response :success
  end

  test "should get organization-specific tenant public status page by slug" do
    get org_public_status_url(org_slug: @org.slug)
    assert_response :success
    assert_select "div", text: "Acme Cloud Services Status"
  end
end
