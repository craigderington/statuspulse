require "test_helper"

class StatusPageTenancyTest < ActionDispatch::IntegrationTest
  setup do
    @first = Organization.create!(name: "First Tenant", slug: "first-tenant")
    @second = Organization.create!(name: "Second Tenant", slug: "second-tenant")

    @first_service = service_for(@first, "First Tenant Private API")
    @second_service = service_for(@second, "Second Tenant Private API")
  end

  def service_for(org, name)
    org.services.create!(
      name: name,
      url: "https://example.test/#{org.slug}",
      http_method: "GET",
      expected_status_code: 200,
      timeout_seconds: 10,
      status: "operational",
      check_interval_seconds: 60
    )
  end

  test "a tenant status page shows only that tenant's services" do
    get org_public_status_url(org_slug: @first.slug)

    assert_response :success
    assert_includes response.body, @first_service.name
    assert_not_includes response.body, @second_service.name
  end

  test "bare /status does not fall through to whichever organization is first" do
    # Without PLATFORM_STATUS_SLUG there is no platform page to serve, and it
    # must not quietly serve tenant #1.
    get public_status_url

    assert_response :not_found
    assert_not_includes response.body, @first_service.name
  end

  test "bare /status serves the explicitly configured platform organization" do
    with_platform_slug(@second.slug) do
      get public_status_url

      assert_response :success
      assert_includes response.body, @second_service.name
      assert_not_includes response.body, @first_service.name
    end
  end

  test "a configured platform slug that does not exist is not found, not tenant one" do
    with_platform_slug("no-such-org") do
      get public_status_url

      assert_response :not_found
      assert_not_includes response.body, @first_service.name
    end
  end

  test "an unknown tenant slug is not found rather than another tenant's page" do
    get org_public_status_url(org_slug: "does-not-exist")

    assert_response :not_found
  end

  test "an anonymous request is not assigned an organization" do
    get root_url

    assert_response :success
    assert_nil Current.organization,
      "anonymous visitors must not inherit a tenant from row order"
  end

  private

  def with_platform_slug(slug)
    previous = ENV["PLATFORM_STATUS_SLUG"]
    ENV["PLATFORM_STATUS_SLUG"] = slug
    yield
  ensure
    ENV["PLATFORM_STATUS_SLUG"] = previous
  end
end
