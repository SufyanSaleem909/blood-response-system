def test_valid_response_statuses():
    valid = {"accepted", "declined"}
    assert "accepted" in valid
    assert "declined" in valid
    assert "maybe" not in valid