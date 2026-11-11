from datetime import datetime, timedelta
from pagination import User, page_after

T0 = datetime(2026, 1, 1)


def users():
    # Three users share a timestamp: ordering must fall back to id.
    return [User(i, T0 + timedelta(seconds=i // 3), f"u{i}@example.com") for i in range(10)]


def collect(limit):
    seen, cursor = [], None
    for _ in range(100):           # a cursor that never advances must fail, not hang
        page, cursor = page_after(users(), cursor, limit)
        seen += [u.id for u in page]
        if cursor is None:
            return seen
    raise AssertionError(f"pagination did not terminate (limit={limit}, last cursor={cursor})")


def test_pages_cover_everyone_once():
    for limit in (1, 2, 3, 4, 7):
        assert collect(limit) == list(range(10)), limit


def test_last_page_has_no_cursor():
    page, cursor = page_after(users(), None, 10)
    assert len(page) == 10 and cursor is None
