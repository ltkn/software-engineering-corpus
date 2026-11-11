from dataclasses import dataclass
from datetime import datetime


@dataclass(frozen=True)
class User:
    id: int
    created_at: datetime
    email: str


def page_after(users: list[User], cursor: tuple[datetime, int] | None, limit: int) -> tuple[list[User], tuple[datetime, int] | None]:
    """Return up to `limit` users after `cursor`, ordered by (created_at, id), and the next cursor."""
    ordered = sorted(users, key=lambda u: (u.created_at, u.id))
    if cursor is not None:
        ordered = [u for u in ordered if (u.created_at, u.id) > cursor]
    page = ordered[:limit]
    has_more = len(ordered) > limit
    next_cursor = (page[-1].created_at, page[-1].id) if has_more else None
    return page, next_cursor
