require "test_helper"

class OrganizationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @org = Organization.create!(name: "Northwind", slug: "northwind")
    @admin = user_for(@org, "admin@northwind.test", "admin")
    @member = user_for(@org, "member@northwind.test", "member")
    @other_org = Organization.create!(name: "Meridian", slug: "meridian")
  end

  def user_for(org, email, role)
    org.users.create!(
      name: email.split("@").first, email: email, role: role,
      password: "a-long-enough-password", password_confirmation: "a-long-enough-password"
    )
  end

  def sign_in_as(user)
    post login_url, params: { email: user.email, password: "a-long-enough-password" }
  end

  test "an admin can open workspace settings" do
    sign_in_as(@admin)

    get edit_organization_url

    assert_response :success
    assert_select "input[name='organization[slug]']"
  end

  test "a member cannot open workspace settings" do
    sign_in_as(@member)

    get edit_organization_url

    assert_redirected_to dashboard_path
    assert_match(/only workspace admins/i, flash[:alert])
  end

  test "a signed-out visitor cannot open workspace settings" do
    get edit_organization_url

    assert_redirected_to login_path
  end

  test "an admin can rename the workspace" do
    sign_in_as(@admin)

    patch organization_url, params: { organization: { name: "Northwind Logistics" } }

    assert_equal "Northwind Logistics", @org.reload.name
  end

  test "changing the slug moves the public status page and says so" do
    sign_in_as(@admin)

    patch organization_url, params: { organization: { slug: "northwind-logistics" } }

    assert_equal "northwind-logistics", @org.reload.slug
    assert_match(%r{/status/northwind-logistics}, flash[:notice])
    assert_match(%r{/status/northwind no longer resolves}, flash[:notice])
  end

  test "a member cannot change the slug even by posting directly" do
    sign_in_as(@member)

    patch organization_url, params: { organization: { slug: "hijacked" } }

    assert_equal "northwind", @org.reload.slug
  end

  test "an invalid slug is rejected rather than saved" do
    sign_in_as(@admin)

    patch organization_url, params: { organization: { slug: "Not A Slug!" } }

    assert_response :unprocessable_entity
    assert_equal "northwind", @org.reload.slug
  end

  test "a slug already taken by another workspace is rejected" do
    sign_in_as(@admin)

    patch organization_url, params: { organization: { slug: @other_org.slug } }

    assert_response :unprocessable_entity
    assert_equal "northwind", @org.reload.slug
  end

  test "an admin edits only their own workspace, whatever they post" do
    sign_in_as(@admin)

    patch organization_url, params: { organization: { name: "Renamed", id: @other_org.id } }

    assert_equal "Renamed", @org.reload.name
    assert_equal "Meridian", @other_org.reload.name
  end

  test "a rejected save reports the error and does not advertise the rejected address" do
    sign_in_as(@admin)

    patch organization_url, params: { organization: { slug: "Not A Slug!" } }

    assert_response :unprocessable_entity
    assert_select ".flash-alert", /public address/i
    # The hint must link to the address that is actually live, not the one just
    # refused.
    assert_select "a[href=?]", org_public_status_path(org_slug: "northwind")
    assert_select "a[href*=?]", "Not A Slug", count: 0
  end

  test "search indexing can be turned off and back on" do
    sign_in_as(@admin)

    patch organization_url, params: { organization: { status_page_indexable: "0" } }
    assert_not @org.reload.status_page_indexable?

    patch organization_url, params: { organization: { status_page_indexable: "1" } }
    assert @org.reload.status_page_indexable?
  end
end
