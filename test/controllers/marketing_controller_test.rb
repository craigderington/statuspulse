require "test_helper"

class MarketingControllerTest < ActionDispatch::IntegrationTest
  test "the landing page is reachable without signing in" do
    get root_url

    assert_response :success
  end

  test "the landing page states the multi-tenant position" do
    get root_url

    assert_select "h1", /one console/i
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
    assert_select "meta[property='og:image']"
    assert_select "meta[name=description]"
  end
end
