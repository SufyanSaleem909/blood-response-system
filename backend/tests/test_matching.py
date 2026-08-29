from datetime import date, timedelta
from app.services.matching import COMPATIBLE_DONORS


def is_eligible(last_donation_date):
    if last_donation_date is None:
        return True
    return date.today() >= last_donation_date + timedelta(days=90)


def test_o_negative_universal_donor_only_matches_self():
    assert COMPATIBLE_DONORS["O-"] == ["O-"]


def test_ab_positive_universal_recipient_accepts_all_types():
    assert set(COMPATIBLE_DONORS["AB+"]) == {"O-", "O+", "A-", "A+", "B-", "B+", "AB-", "AB+"}


def test_a_positive_accepts_a_and_o_types():
    assert set(COMPATIBLE_DONORS["A+"]) == {"O-", "O+", "A-", "A+"}


def test_no_donation_history_is_eligible():
    assert is_eligible(None) is True


def test_exactly_90_days_since_donation_is_eligible():
    last = date.today() - timedelta(days=90)
    assert is_eligible(last) is True


def test_89_days_since_donation_is_not_eligible():
    last = date.today() - timedelta(days=89)
    assert is_eligible(last) is False


def test_recent_donation_is_not_eligible():
    last = date.today() - timedelta(days=5)
    assert is_eligible(last) is False