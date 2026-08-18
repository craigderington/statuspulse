require "test_helper"

class IncidentServiceTest < ActiveSupport::TestCase
  test "rejects a service from another workspace" do
    incident = incidents(:one)
    join = IncidentService.new(incident: incident, service: services(:two))

    assert_not join.valid?
    assert_includes join.errors[:service], "must belong to the incident workspace"
  end

  test "copies the incident workspace onto the join" do
    join = IncidentService.new(incident: incidents(:one), service: services(:one))

    assert join.valid?
    assert_equal incidents(:one).organization, join.organization
  end
end
