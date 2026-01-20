require "application_system_test_case"

class TracksTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    login_as @user
  end

  def login_as(user)
    visit "/test/login?user_id=#{user.id}"
  end

  test "creating a new track" do
    visit tracks_url
    click_on "New Track"

    fill_in "Search Query (Optional)", with: "testing rails"
    execute_script("document.getElementById('track_threshold').value = 0.8")

    # Simulate adding a tag
    find("[data-tags-target='input']").send_keys("ruby", :enter)

    click_on "Save Track"

    assert_text "Track was successfully created"
    assert_text "testing rails"
    assert_text "0.8"
  end

  test "creating a track with only keywords" do
    visit tracks_url
    click_on "New Track"

    find("[data-tags-target='input']").send_keys("elixir", :enter)
    find("[data-tags-target='input']").send_keys("phoenix", :enter)

    click_on "Save Track"

    assert_text "Track was successfully created"
    # Verify keywords form (though index might not show them yet, we check for success)
  end

  test "creating a track fails without query or keywords" do
    visit tracks_url
    click_on "New Track"
    click_on "Save Track"

    assert_text "You must provide either a search query or at least one keyword"
  end

  test "updating a track" do
    @track = tracks(:one)
    visit tracks_url

    within "tr", text: @track.query do
      click_on "Edit"
    end

    fill_in "Search Query (Optional)", with: "updated query"
    click_on "Save Track"

    assert_text "Track was successfully updated"
    assert_text "updated query"
  end

  test "removing keywords from a track" do
    # Create a track with keywords
    visit tracks_url
    click_on "New Track"
    fill_in "Search Query (Optional)", with: "base query"
    find("[data-tags-target='input']").send_keys("removable", :enter)
    click_on "Save Track"
    assert_text "Track was successfully created"

    # Edit it
    click_on "Edit", match: :first

    # Remove the keyword (find the remove button inside the tag)
    find("[data-tags-target='container'] button").click

    click_on "Save Track"

    assert_text "Track was successfully updated"
    # Verify DB state directly or via UI if we were showing keywords (we aren't yet showing them in index explicitly)
    assert_equal [], Track.order(created_at: :desc).first.keywords
  end

  test "deactivating a track" do
    visit tracks_url

    # Target "python django" track
    within "tr", text: "python django" do
      click_on "Deactivate"
      assert_text "Inactive"
      assert_no_text "Deactivate"
      assert_selector "button", text: "Activate"
    end

    assert_text "Track was successfully deactivated"
  end

  test "activating an inactive track from list" do
    visit tracks_url

    # Deactivate first
    within "tr", text: "python django" do
      click_on "Deactivate"
      assert_text "Inactive"

      # Now Activate
      click_on "Activate"
    end

    assert_text "Track was successfully activated"

    within "tr", text: "python django" do
      assert_text "Active"
      assert_no_text "Activate"
      assert_selector "button", text: "Deactivate"
    end
  end

  test "activating an inactive track from edit" do
    visit tracks_url

    # Deactivate first
    within "tr", text: "python django" do
      click_on "Deactivate"
    end
    assert_text "Track was successfully deactivated"

    # Go to Edit
    within "tr", text: "python django" do
      click_on "Edit"
    end

    # Verify Activate button is present instead of Save
    assert_selector "input[value='Activate']"

    # Make a change and click Activate
    fill_in "Search Query (Optional)", with: "activated python"
    click_on "Activate"

    assert_text "Track was updated and activated"
    assert_text "activated python"

    # Verify active status in list
    within "tr", text: "activated python" do
      assert_text "Active"
    end
  end

  test "preview modal interaction" do
    visit new_track_path

    assert_selector "button", text: "Preview Matches"

    # Fill in query so validation passes
    fill_in "Search Query (Optional)", with: "preview test"

    # Open modal
    click_on "Preview Matches"

    # Check modal visibility logic (checking for text that is only in modal)
    assert_text "Live Match Preview"
    assert_text "Live - Waiting for matches...", wait: 10

    # Close modal
    click_on "Close Preview"
    assert_no_text "Live Match Preview"
  end

  test "preview with pending keyword" do
    visit new_track_path

    # Type keyword but DO NOT press enter
    find("[data-tags-target='input']").send_keys("pendingkeyword")

    # Open preview (should succeed finding the keyword)
    click_on "Preview Matches"

    assert_text "Live Match Preview"
    # Should NOT show error
    assert_no_text "Error: Must provide query or keywords"
    # Should show verifying status
    assert_text "Live - Waiting for matches...", wait: 10
  end

  test "destroying a track" do
    visit tracks_url
    accept_confirm do
      first(:button, "Delete").click
    end

    assert_text "Track was successfully destroyed"
  end
end
