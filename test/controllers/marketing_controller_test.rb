require "test_helper"

class MarketingControllerTest < ActionDispatch::IntegrationTest
  test "the landing page is reachable without signing in" do
    get root_url

    assert_response :success
  end

  test "the landing page states the multi-tenant position" do
    get root_url

    assert_select "h1", /workspace by workspace/i
    assert_select ".mk-lede", /isolated workspace/i
  end

  test "the landing page routes visitors to sign-up and to a live status page" do
    get root_url

    assert_select "a[href=?]", signup_path
    assert_select "a[href=?]", public_status_path
  end

  test "the hero wall is labelled as illustrative rather than passed off as customers" do
    get root_url

    assert_select ".mk-wall__caption", /example/i
  end

  test "the landing page carries the tags a crawler and a link preview need" do
    get root_url

    assert_select "link[rel=canonical]"
    assert_select "meta[property='og:title']"
    assert_select "meta[property='og:image'][content='http://www.example.com/og/statuspulse-card.png']"
    assert_select "meta[property='og:image:alt']"
    assert_select "meta[name='twitter:card'][content='summary_large_image']"
    assert_select "meta[name='twitter:image'][content='http://www.example.com/og/statuspulse-card.png']"
    assert_select "meta[name='twitter:image:alt']"
    assert_select "meta[name=description]"
  end

  test "agency uptime monitoring page targets agencies without unsupported claims" do
    get "/uptime-monitoring-for-agencies"

    assert_response :success
    assert_select "title", /Uptime Monitoring for Agencies/
    assert_select "meta[name=description]"
    assert_select "link[rel=canonical][href=?]", "http://example.com/uptime-monitoring-for-agencies"
    assert_select "h1", text: /Uptime monitoring for agencies/i, count: 1
    assert_select "a[href=?]", signup_path
    assert_select "a[href=?]", public_status_path
    assert_no_match(/white-?label/i, response.body)
    assert_no_match(/custom domain/i, response.body)
    assert_no_match(/subscriber notification/i, response.body)
  end

  test "multi tenant uptime monitoring page explains workspace isolation" do
    get "/multi-tenant-uptime-monitoring"

    assert_response :success
    assert_select "title", /Multi-Tenant Uptime Monitoring/
    assert_select "h1", text: /Multi-tenant uptime monitoring/i, count: 1
    assert_select ".mk-card", text: /Endpoints/i
    assert_select ".mk-card", text: /Incidents/i
    assert_select ".mk-card", text: /Reports/i
    assert_no_match(/white-?label/i, response.body)
    assert_no_match(/custom domain/i, response.body)
    assert_no_match(/one console|single dashboard/i, response.body)
  end

  test "marketing pages do not promise a cross-workspace operator console" do
    [ root_url, uptime_monitoring_for_agencies_url, multi_tenant_uptime_monitoring_url ].each do |url|
      get url

      assert_response :success
      assert_no_match(/one console|single dashboard|watch many client workspaces/i, response.body)
      assert_select "a[href=?]", public_status_path
    end
  end

  test "client uptime reports page explains SLA windows and P90 latency" do
    get "/client-uptime-reports"

    assert_response :success
    assert_select "title", /Client Uptime Reports/
    assert_select "h1", text: /Client-ready uptime reports/i, count: 1
    assert_select "body", /7.*30.*90/m
    assert_select "body", /P90 latency/i
    assert_select "a[href=?]", signup_path
    assert_no_match(/white-?label/i, response.body)
    assert_no_match(/custom domain/i, response.body)
  end
end
